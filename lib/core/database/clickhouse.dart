import 'dart:async';

import 'package:dio/dio.dart';

import '../annotation/annotation.dart' hide ResponseType;
import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../log/logger.dart';
import '../retry/retry.dart';
import 'pageable.dart';

/// Clickhouse的数据库客户端
///
/// @author luodongseu
@Bean(conditionOnProperty: 'database.clickhouse')
class ClickHouseClient {
  static Log logger = Log('ClickHouseDataBase');

  /// 主机IP
  String _host;

  /// 端口号
  int _port;

  /// clickhouse的http接口url
  String _chHttpUrl;

  /// http客户端
  static Dio _httpClient;

  /// 全局唯一实例
  static ClickHouseClient _instance = null;

  ClickHouseClient() {
    _instance = this;
    _host =
        ApplicationContext.instance['database.clickhouse.host'] ?? '127.0.0.1';
    _port = int.parse(
        '${ApplicationContext.instance['database.clickhouse.port'] ?? 8123}');
    _chHttpUrl = 'http://$_host:$_port/';

    logger.info(
        "Start to connect clickhouse client to server:[$_host:$_port]...");

    _httpClient =
        Dio(BaseOptions(contentType: 'application/json;charset=UTF-8'));
    _httpClient.interceptors.add(InterceptorsWrapper(onError: (e) {
      logger.error('Run sql failed [$e].', e.error);
      return null;
    }));

    _instance.execute('select 1').then((v) {
      logger.info(
          "Clickhouse client connected to server:[$_host:$_port] success.");
    });
  }

  static ClickHouseClient get instance => _instance;

  /// 执行SQL语句
  ///
  /// [_sql] 为原始的sql语句，该方法会删除sql语句中多余的空字符:
  /// 1. 开头的所有空字符会被删除
  /// 2. 结尾的所有空字符会被删除
  /// 3. sql中间的连续2个以上的空字符会被替换只留1个空字符
  ///
  /// [pageRequest] 为分页信息
  /// 不传[pageRequest]表示不分页
  /// 传了[pageRequest]会返回Pageable对象
  Future<dynamic> execute(String _sql, [PageRequest pageRequest]) async {
    // 记录时间
    int _sm = DateTime.now().millisecondsSinceEpoch;

    var result;

    // 过滤多余的空字符
    String sql = '$_sql'
        .toLowerCase()
        .replaceFirst(RegExp(r'^\s+'), '')
        .replaceFirst(RegExp(r'\s+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    bool isSelectSql = sql.startsWith('select');
    String format = '';
    ResponseType responseType = ResponseType.plain;
    String limit = '';
    if (isSelectSql) {
      format = ' format JSON';
      responseType = ResponseType.json;
    }
    if (null != pageRequest) {
      assert(pageRequest.limit > 0, 'Page size must bigger than zero.');
      assert(pageRequest.page >= 0,
      'Page index must bigger than or equal to zero.');
      limit = ' limit ${pageRequest.offset},${pageRequest.limit}';
    }
    String finalSql = '$sql$limit';
    logger.debug('Ch sql -> $finalSql');

    try {
      List<Future> requests = [
        _getResponse('$finalSql$format', responseType),
      ];
      if (isSelectSql && null != pageRequest) {
        requests.add(count(sql, pageRequest));
      }
      // 并发执行sql
      var res = await Future.wait(requests);
      if (res.length == 2) {
        // 分页查询
        result = PageImpl(
            res[0].data['data'], pageRequest.page, pageRequest.limit, res[1]);
      } else {
        result = res[0].data['data'] ?? res[0].data;
      }
    } catch (e) {
      logger.error("Ch sql [$finalSql] response -> error: $e");
      throw CustomError(e);
    }

    // 打印时间和状态
    int _em = DateTime.now().millisecondsSinceEpoch;
    logger.debug('Ch sql [$finalSql] -> response in [${_em - _sm}] millsecs');
    return result;
  }

  /// 执行单个sql，获取响应结果并记录时间
  Future<Response> _getResponse(String sql, ResponseType responseType) async {
    logger.info('Ch start run single sql -> $sql ...');
    int _sm = DateTime.now().millisecondsSinceEpoch;
    Response response = await retry(
            () => _httpClient.post(_chHttpUrl,
            data: '$sql',
            options: Options(contentType: 'text', responseType: responseType)),
        maxAttempts: 5, onRetry: (e) {
      logger.debug("Ch sql [$sql] retry execute for "
          "error:$e ...");
    });
    int _em = DateTime.now().millisecondsSinceEpoch;
    logger.debug("Ch single sql -> $sql finished in [${_em - _sm}] millsecs "
        "and response status: [${response.statusCode} "
        "${response.statusMessage}]");
    return response;
  }

  /// 统计sql查询的总记录数
  ///
  /// 返回int -> 总数
  Future<int> count(String fromSql, PageRequest pageRequest) async {
    String countSql = 'select count(*) from ($fromSql) as c'.toLowerCase();
    logger.debug('Count sql -> $countSql');
    Response countResponse = await _getResponse(countSql, ResponseType.plain);
    logger.debug('Ch count sql [$countSql] response -> $countResponse');
    return int.parse('${countResponse.data ?? '0'}');
  }
}
