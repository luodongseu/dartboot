import '../core/database/mongo_client.dart';
import '../core/database/mongo_dart/mongo_dart.dart';
import '../core/database/mysql_client_helper.dart';
import '../core/database/mysql_connection_pool.dart';

/// 数据库连接工具类示例
///
/// 当前提供了2种数据库操作：MySQL & MongoDB
///
/// @author luodongseu
class DatabaseUtils {
  /// MySQL连接客户端
  ///
  /// 直接使用MysqlClientHelper.getClient('{数据库配置名称}')获取连接实例
  static Future<MysqlConnection2> db1() => MysqlClientHelper.getClient('db1');

//  static Future<MysqlConnection2> stat() => MysqlClientHelper.getClient('db2');

  /// MongoDB连接客户端
  ///
  /// MongoClient.instance.collection('{数据库配置名称}', '{文档名称}');
  static Future<DbCollection> record() =>
      MongoClient.instance.collection('lesson', 'doc_lesson_record');
}
