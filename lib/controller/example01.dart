import 'package:dartboot/core/annotation/annotation.dart';
import 'package:dartboot/core/database/mysql_pool.dart';
import 'package:dartboot/core/log/logger.dart';
import 'package:dartboot/feign/self_feign_client.dart';

/// RestController 接口示例
///
/// Example 01:
///
@RestController('/api/v1')
class Example01Controller {
  MysqlClientPool pool;

  Example01Controller() {
    /// 初始化MysqlClientPool
    MysqlClientPool.create().then((p) => pool = p);
  }

  /// 示例：返回json数据
  @Get('/example01')
  dynamic get01(@Query('test', required: false) String test) {
    Log.rootLevel = DEBUG;
    return {'a': 'Example 01 response: ${test ?? 'test'}'};
  }

  /// 示例：通过Mysql数据库连接池连接数据库
  @Get('/example02')
  Future<int> get02(@Query('test', required: false) String test) async {
    return (await (await pool?.getConnection())
            .query('select count(*) from t_user'))
        .first[0];
  }

  /// 示例：通过Eureka客户端访问微服务
  @Get('/example03')
  Future<int> get03(@Query('count', required: false) int count) async {
    int c = count ??= 3;
    if (c <= 0) {
      return c;
    }
    int prefValue = (await SelfFeignClient.client
            .get('/api/v1/example03', queryParameters: {'count': c - 1}))
        .data;
    return prefValue + c;
  }
}
