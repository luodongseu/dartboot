import 'package:mongo_dart_query/mongo_dart_query.dart';

import '../core/annotation/annotation.dart';
import '../core/log/logger.dart';
import '../util/database_utils.dart';
import '../feign/feign_clients.dart';

/// RestController 接口示例
///
/// Example 01:
///
@Api('示例接口类')
@RestController('/api/v1')
class Example01Controller {

  @Api('示例：返回json数据')
  @Get('/example01')
  dynamic get01(@Query('test', required: false) String test) {
    Log.rootLevel = DEBUG;
    return {'a': 'Example 01 response: ${test ?? 'test'}'};
  }

//  @Api('示例：通过Mysql数据库连接池连接数据库')
//  @Get('/example02')
//  Future<int> get02(@Query('test', required: false) String test) async {
//    return (await (await pool?.getConnection())
//            .query('select count(*) from t_user'))
//        .first[0];
//  }

  @Api('示例：通过Eureka客户端访问微服务')
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

  @Api('示例：通过MySQL数据库查询数据')
  @Get('/example04')
  Future<int> get04() async {
    return (await DatabaseUtils.db1()).count('select count(*) from test');
  }

  @Api('示例：通过MongoDB数据库查询数据')
  @Get('/example05')
  Future<int> get05() async {
    return (await DatabaseUtils.record()).count(where.eq('fieldX', 'valueY'));
  }
}
