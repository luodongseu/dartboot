import 'dart:async';

import 'package:mysql1/mysql1.dart';
import 'package:mysql1/src/single_connection.dart';

import '../error/custom_error.dart';
import '../log/logger.dart';
import '../util/date.dart';
import '../util/uid.dart';

/// 事务的调度器
typedef TransactionCaller = Function(TransactionContext);

/// 默认测试链接周期，毫秒
const int defaultTestQueryPeriodMills = 30 * 1000;

/// 测试的timeout
const Duration testTimeout = const Duration(milliseconds: 500);

/// 默认查询timeout
const Duration defaultQueryTimeout = const Duration(seconds: 30);

/// 默认查询timeout
const Duration defaultConnectionTimeout = const Duration(seconds: 5);

/// Mysql客户端的线程池
///
/// @支持：定义线程池的最大最小数量
/// @支持：定义测试sql语句
///
/// 快速创建连接池示例：
/// ```
/// MysqlConnectionPool.create({host:'',port:''}).then((p) => pool = p);
/// ```
///
/// @author luodong
class MysqlConnectionPool {
  Log logger = Log('MysqlConnectionPool');

  /// IP地址
  final String host;

  /// 端口号
  final int port;

  /// 用户名
  final String username;

  /// 密码
  final String password;

  /// 数据库
  final String db;

  /// 最大的连接数量
  final int maxSize;

  /// 最小的连接输了
  final int minSize;

  /// 测试连接的sql
  final String testSql;

  /// 查询的timeout
  final Duration queryTimeout;

  /// 看门狗的定时器
  Timer _testTimer;

  /// 看门狗的定时间隔
  Duration _testQueryPeriodDuration;

  /// 连接池
  List<MysqlConnection2> _pool = [];

  /// 获取连接的锁
  bool _acquireConnectionLocked = false;

  /// 获取连接的等待间隔
  Duration _acquireConnectionWaitInterval = Duration(milliseconds: 100);

  /// 使用默认的配置创建pool
  static Future<MysqlConnectionPool> create(mysqlConfig) async {
    assert(null != mysqlConfig, 'Mysql config must not be null');

    return MysqlConnectionPool(
        host: mysqlConfig['host'],
        port: int.parse('${mysqlConfig['port'] ?? 3306}'),
        db: mysqlConfig['db'],
        username: mysqlConfig['username'],
        password: mysqlConfig['password'],
        minSize: int.parse('${mysqlConfig['minPoolSize'] ?? 5}'),
        maxSize: int.parse('${mysqlConfig['maxPoolSize'] ?? 30}'),
        testQueryPeriodMills:
            int.parse('${mysqlConfig['testQueryPeriodMills'] ?? 30000}'));
  }

  /// 创建新的线程池
  ///
  /// example usage:
  /// ``` dart
  /// var pool = MysqlConnectionPool(
  ///   host: '192.168.1.199',
  ///   port: '3306',
  ///   username: 'admin',
  ///   password: '******',
  ///   db: 'test'
  /// );
  /// var c = await pool.getConnection();
  /// c.query('select * from test limit 1');
  /// ```
  MysqlConnectionPool(
      {this.host = '127.0.0.1',
      this.port = 3306,
      this.username,
      this.password,
      this.db = 'default',
      this.minSize = 5,
      this.maxSize = 30,
      this.queryTimeout,
      int testQueryPeriodMills = defaultTestQueryPeriodMills,
      this.testSql = 'select 1'}) {
    assert(minSize > 0, 'Min pool size must greater than zero');
    assert(maxSize > minSize, 'Max pool size must greater than min pool size');
    assert(testQueryPeriodMills > 1000,
        'Test query period must greater than 1 second');
    _testQueryPeriodDuration = Duration(milliseconds: testQueryPeriodMills);
    init();
  }

  /// 初始化
  init() async {
    // 填充连接池
    _fillPool();

    // 添加看门狗
    _initTestTimer();
  }

  /// 创建新的连接，并且将连接添加到连接池中
  Future<MysqlConnection2> _createConnectionAndAdd2Pool() async {
    MysqlConnection2 c = await createConnection();
    _pool.add(c);
    return c;
  }

  /// 初始化看门狗
  ///
  /// 定时检查连接池中空闲的连接是否可用
  /// 如果已断开，则标记连接被移除，并清理连接池
  _initTestTimer() {
    if (null != _testTimer) {
      _testTimer.cancel();
    }
    _testTimer = Timer.periodic(_testQueryPeriodDuration, (t) {
      Future.sync(() async {
        // 是否有移除的连接
        List cs = _pool
            .where((c) => c.state == ConnectionState.STATE_NOT_IN_USE)
            .toList();
        for (var i = 0; i < cs.length; i++) {
          bool isAlive = await isConnectionAlive(cs[i]);
          if (!isAlive) {
            // 已经断开了
            cs[i].state = ConnectionState.STATE_REMOVED;
          }
        }

        if (cs.any((c) => c.state == ConnectionState.STATE_REMOVED)) {
          await _cleanPool();
        }
      });
    });
  }

  /// 清理连接池
  ///
  /// 清理后执行填充操作
  _cleanPool() async {
    List<int> removeIndex = [];
    for (var i = 0; i < _pool.length; i++) {
      if (_pool[i].state == ConnectionState.STATE_REMOVED) {
        removeIndex.add(i);
      }
    }
    removeIndex.forEach((i) => _pool.removeAt(i));

    // 填充连接池
    _fillPool();
  }

  /// 填充连接池到[minSize]大小
  _fillPool() async {
    while (_pool.length < minSize) {
      await _createConnectionAndAdd2Pool();
    }
  }

  /// 获取Mysql的连接对象
  ///
  /// @param timeout: Duration that timeout to break acquire job
  ///                 超时时间
  Future<MysqlConnection2> getConnection(
      {Duration timeout = defaultConnectionTimeout}) async {
    Completer<MysqlConnection2> completer = Completer<MysqlConnection2>();
    StreamSubscription<MysqlConnection2> subscription = (() async {
      while (!completer.isCompleted) {
        if (_acquireConnectionLocked) {
          // wait 100ms to try get lock again
          await Future.delayed(_acquireConnectionWaitInterval);
          continue;
        }

        // lock
        _acquireConnectionLocked = true;

        MysqlConnection2 c;
        while ((c = await acquireConnection()) == null) {
          // wait 100ms to try acquirement again
          await Future.delayed(_acquireConnectionWaitInterval);
        }
        c.state = ConnectionState.STATE_IN_USE;

        // unlock
        _acquireConnectionLocked = false;

        return c;
      }
      throw TimeoutException('Get sql connection timeout');
    })()
        .asStream()
        .listen((v) {
      if (!completer.isCompleted) {
        completer.complete(v);
        return;
      }
    });

    // record time start
    int s = now;
    MysqlConnection2 c = await completer.future
        .timeout(timeout ?? defaultConnectionTimeout, onTimeout: () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.completeError('Get sql connection timeout');
        throw TimeoutException('Get sql connection timeout');
      }
      return completer.future;
    });

    // log time used
    logger.debug('Get connection in ${now - s} mills.');

    return c;
  }

  /// 从连接池中取出空闲的连接
  getFreeConnectionInPool() {
    return _pool.firstWhere((c) => c.state == ConnectionState.STATE_NOT_IN_USE,
        orElse: () => null);
  }

  /// 获取连接
  ///
  /// 1. 从[_pool]取空闲连接，如果取到，返回
  /// 2. 如果[_pool]中无空闲连接，且连接池大小不小于[maxSize]，则返回null
  /// 3. 否则[createConnectionAndAdd2Pool]创建新的连接
  acquireConnection() async {
    MysqlConnection2 c = getFreeConnectionInPool();
    if (null != c || _pool.length >= maxSize) {
      return c;
    }
    // scale
    return await _createConnectionAndAdd2Pool();
  }

  /// 判断连接是否存活
  /// 使用[testSql]进行连接测试
  Future<bool> isConnectionAlive(MysqlConnection2 conn) async {
    if (null == conn) {
      return false;
    }
    try {
      await conn.query(testSql ?? 'select 1').timeout(testTimeout,
          onTimeout: () {
        throw TimeoutException('Execute test sql:[$testSql] timeout.');
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 创建新的连接
  Future<MysqlConnection2> createConnection() async {
    ConnectionSettings settings = ConnectionSettings(
        host: host,
        port: port,
        user: username,
        password: password,
        db: db,
        timeout: queryTimeout ?? defaultQueryTimeout);
    return MysqlConnection2.connect(settings);
  }
}

/// 连接状态
enum ConnectionState {
  /// 正在占用中
  STATE_IN_USE,

  /// 空闲
  STATE_NOT_IN_USE,

  /// 已被移除
  STATE_REMOVED
}

/// 封装了部分特性的连接对象
///
/// busy -> 用于判断是否在执行sql
class MysqlConnection2 {
  Log logger = Log('MysqlConnection2');

  /// 连接的状态
  ConnectionState _state = ConnectionState.STATE_NOT_IN_USE;

  /// 连接的对象
  final MySqlConnection connection;

  set state(s) => _state = s;

  get state => _state;

  /// 执行中的ID集合
  List<String> _executingIds = [];

  MysqlConnection2(this.connection);

  @override
  String toString() {
    return 'state: $_state, executing size: ${_executingIds.length}';
  }

  /// 连接方法
  static Future<MysqlConnection2> connect(ConnectionSettings c) async {
    MySqlConnection connection = await MySqlConnection.connect(c);
    return MysqlConnection2(connection);
  }

  /// 查询单个数据
  Future<Results> query(String sql, [List<Object> values]) async {
    logger.debug('## Sql execution: [${sql}]');
    var id = uid8;
    _executingIds.add(id);
    try {
      return await connection?.query(sql, values);
    } catch (e) {
      logger.error('## Sql execution: [${sql}] error: $e');
      throw CustomError('Execute sql: [$sql] failed. $e');
    } finally {
      release(id);
    }
  }

  /// 查询结果集
  Future<List<Results>> queryMulti(
      String sql, Iterable<List<Object>> values) async {
    logger.debug('## Sql execution: [${sql}]');
    var id = uid8;
    _executingIds.add(id);
    try {
      return await connection?.queryMulti(sql, values);
    } catch (e) {
      logger.error('## Sql execution: [${sql}] error: $e');
      throw CustomError('Execute sql: [$sql] failed. $e');
    } finally {
      release(id);
    }
  }

  /// 提交事务
  ///
  /// @param caller 事务提交调用者
  Future transaction(TransactionCaller caller) async {
    var id = uid8;
    _executingIds.add(id);
    try {
      logger.debug('## Sql transaction[$id] execution start ...');
      Future r = await connection?.transaction(caller);
      logger.debug('## Sql transaction[$id] execution end.');
      return r;
    } catch (e) {
      logger.error('## Sql execution: [${id}] error: $e');
      throw CustomError('Execute sql: [$id] failed. $e');
    } finally {
      release(id);
    }
  }

  /// 释放指定的ID
  void release(id) {
    _executingIds.remove(id);
    if (_executingIds.length <= 0) {
      _state = ConnectionState.STATE_NOT_IN_USE;
    }
  }
}
