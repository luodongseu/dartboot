import '../annotation/annotation.dart';
import '../bootstrap/application_context.dart';
import '../util/string.dart';
import 'mysql_connection_pool.dart';

/// Mysql的客户端帮助类
///
/// example:
/// ```
/// MysqlConnection2 c = await MysqlClientHelper.getClient('dev');
/// c.query(xxxxx);
/// ```
///
/// @author luodongseu
@Bean(conditionOnProperty: 'database.mysql')
class MysqlClientHelper {
  /// 单例
  static MysqlClientHelper _instance;

  /// 连接池的集合
  Map<String, MysqlConnectionPool> _pools = Map();

  MysqlClient() {
    // 初始化连接池
    _instance = this;
    dynamic mysqlConf = ApplicationContext.instance['database.mysql'];
    if (mysqlConf is Map && mysqlConf.keys.length > 0) {
      mysqlConf.keys.forEach((k) {
        MysqlConnectionPool.create(mysqlConf[k]).then((p) => _pools[k] = p);
      });
    }
  }

  /// 获取Mysql连接客户端
  ///
  /// Usage:
  /// ```
  /// MysqlClientHelper.getClient().then();
  /// MysqlClientHelper.getClient('dev').then();
  /// ```
  static Future<MysqlConnection2> getClient([String id]) {
    assert(_instance._pools.isNotEmpty, 'No any mysql configured.');

    if (isEmpty(id)) {
      return _instance._pools.values.elementAt(0).getConnection();
    }

    assert(_instance._pools.containsKey(id), 'Not found mysql:[$id] configuration.');
    return _instance._pools[id].getConnection();
  }
}
