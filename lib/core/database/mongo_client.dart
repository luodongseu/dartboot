import 'dart:async';

import 'package:mutex/mutex.dart';
import './mongo_dart/mongo_dart.dart' hide Log;
import '../annotation/annotation.dart';
import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../log/logger.dart';
import '../util/string.dart';

/// 默认的Pool Size，初始化连接数
const defaultMongoPoolSize = 10;

/// 默认Pool的检查周期
const defaultPoolCheckingInterval = Duration(seconds: 15);

/// Mongodb的客户端
///
/// @author luodongseu
@Bean(conditionOnProperty: 'database.mongo')
class MongoClient {
  static MongoClient _instance;

  /// DB连接池
  Map<String, ConnectionPool> _pools = Map();

  MongoClient() {
    _instance = this;

    // 初始化DB池
    dynamic mongoConfig = ApplicationContext.instance['database.mongo'];
    if (mongoConfig is Map) {
      mongoConfig.forEach((k, config) async {
        int poolSize = isEmpty(config['pool-size'])
            ? defaultMongoPoolSize
            : int.parse('${config['pool-size']}');
        assert(poolSize > 0, 'Min pool size must larger than zero');

        // 创建连接池
        List<String> hosts = List.from(config['hosts']) ?? [];
        assert(hosts.length > 0, 'Host must present');
        _pools[k] = ConnectionPool(poolSize, () {
          return Db.pool(hosts
              .map((h) =>
                  'mongodb://${config['username']}:${config['password']}@$h/${config['db']}')
              .toList());
        });
      });
    }
  }

  static MongoClient get instance => _instance;

  /// 获取数据库操作客户端
  Future<Db> db(String db) {
    assert(_pools.isNotEmpty, 'Database not configured.');
    assert(_pools.containsKey(db), 'No database name $db configured.');

    return _pools[db].withOne();
  }

  /// 获取文档集合操作客户端
  Future<DbCollection> collection(String _db, String col) async {
    return (await db(_db)).collection(col);
  }
}

/// A function that produces an instance of [Db], whether synchronously or asynchronously.
///
/// This is used in the [ConnectionPool] class to connect to a database on-the-fly.
typedef _DbFactory = FutureOr<Db> Function();

/// A connection pool that limits the number of concurrent connections to a MongoDB server.
///
/// The connection pool lazily connects to the database; that is to say, it only opens as many
/// connections as it needs to. If it is only ever called once, then it will only ever connect once.
class ConnectionPool {
  Log log = Log('MongoConnectionPool');
  List<Db> _connections = [];

  /// The maximum number of concurrent connections allowed.
  final int maxConnections;

  /// A [_DbFactory], a parameterless function that returns a [Db]. The function can be asynchronous if necessary.
  final _DbFactory dbFactory;

  /// 定时器（心跳）
  Timer timer;

  /// Initializes a connection pool.
  ///
  /// * `maxConnections`: The maximum amount of connections to keep open simultaneously.
  /// * `dbFactory*: a parameterless function that returns a [Db]. The function can be asynchronous if necessary.
  ConnectionPool(this.maxConnections, this.dbFactory) {
    _connect();

    /// 开启定时检查连接是否可用
    timer?.cancel();
    timer = Timer.periodic(defaultPoolCheckingInterval, (t) async {
      List<Db> toRemoveDbs = [];
      for (Db db in _connections) {
        // 如果状态不正确，则直接删除
        if (db.state != State.OPEN) {
          toRemoveDbs.add(db);
          continue;
        }

        // 如果测试失败，则删除
        try {
          await db.isMaster();
        } catch (e) {
          log.error('Cannot get collection names from db:${db.toString()}. $e');
//          if (e is ConnectionException) {
          try {
            db.close();
          } finally {
            toRemoveDbs.add(db);
          }
//          }
        }
      }
      if (toRemoveDbs.isEmpty) {
        return;
      }
      await m.acquire();
      toRemoveDbs.forEach((db) => _connections.remove(db));
      await _connect(fill: true);
      m.release();
    });
  }

  /// Connects to the database, using an existent connection, only creating a new one if
  /// the number of active connections is less than [maxConnections].
  /// @param fill: 是否为补全
  _connect({bool fill = false}) async {
    if (!fill) _connections?.clear();
    log.info('Start to prepare connections for pool $this with fill: $fill...');
    List<Future<Db>> futures = [];
    for (int _i = 0;
        _i < maxConnections - (fill ? _connections.length : 0);
        _i++) {
      futures.add(Future(() async {
        var db = await dbFactory();
        await db.open();
        return db;
      }));
    }
    if (futures.isEmpty) {
      return;
    }
    List<Db> dbs = await Future.wait(futures);
    _connections.addAll(dbs);
    if (!fill) {
      log.info('Pool ready with ${_connections.length} connections.');
    } else {
      log.info(
          'Pool filled successfully with new ${futures.length} connections.');
    }
  }

  int _index = 0;
  var m = Mutex();

  /// 取出一个connection
  Future<Db> withOne({int i = 5}) async {
    if (i < 0) {
      throw CustomError('无法获取连接');
    }
    await m.acquire();
    if (++_index > _connections.length - 1) {
      _index = 0;
    }
    m.release();
    if (_connections.isNotEmpty) {
      return _connections[_index];
    }

    _connect(fill: true);

    // 等待500毫秒后重试
    await Future.delayed(Duration(milliseconds: 500));
    return await withOne(i: i - 1);
  }
}
