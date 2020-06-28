import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../retry/retry.dart';
import 'pageable.dart';

/// Clickhouse的数据库客户端
///
/// @author luodongseu
class ClickHouseDataBase {
  Logger logger = Logger('ClickHouseDataBase');

  /// 主机IP
  String _host = '127.0.0.1';

  /// 端口号
  int _port = 8123;

  /// clickhouse的http接口url
  String _chHttpUrl;

  /// http客户端
  static Dio _httpClient = Dio();

  /// 全局唯一实例
  static ClickHouseDataBase _instance = null;

  static get instance {
    if (null == _instance) {
      String host = null;
      int port = null;
      dynamic database = ApplicationContext.instance['database'];
      if (null != database && null != database['clickhouse']) {
        host = database['clickhouse']['host'];
        port = int.parse('${database['clickhouse']['port']}');
      }
      _instance = ClickHouseDataBase(host: host, port: port);
    }
    return _instance;
  }

  ClickHouseDataBase({String host, int port}) {
    if (null != host) {
      _host = host;
    }
    if (null != port) {
      _port = port;
    }
    _chHttpUrl = 'http://$_host:$_port/';
    logger.info("Ch initialized with host:$host and port:$port.");
  }

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
    logger.shout('Ch sql -> $finalSql');

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
      logger.severe("Ch sql [$finalSql] response -> error: $e");
      if (e is DioError) {
        throw CustomError('系统错误，无法访问数据');
      }
      throw CustomError(e);
    }

    // 打印时间和状态
    int _em = DateTime.now().millisecondsSinceEpoch;
    logger.shout('Ch sql [$finalSql] -> response in [${_em - _sm}] millsecs');
    return result;
  }

  /// 执行单个sql，获取响应结果并记录时间
  Future<Response> _getResponse(String sql, ResponseType responseType) async {
    logger.shout('Ch start run single sql -> $sql ...');
    int _sm = DateTime.now().millisecondsSinceEpoch;
    Response response = await retry(
        () => _httpClient.post(_chHttpUrl,
            data: '$sql',
            options: Options(contentType: 'text', responseType: responseType)),
        maxAttempts: 5, onRetry: (e) {
      logger.shout("Ch sql [$sql] retry execute for "
          "error:$e ...");
    });
    int _em = DateTime.now().millisecondsSinceEpoch;
    logger.shout("Ch single sql -> $sql finished in [${_em - _sm}] millsecs "
        "and response status: [${response.statusCode} "
        "${response.statusMessage}]");
    return response;
  }

  /// 统计sql查询的总记录数
  ///
  /// 返回int -> 总数
  Future<int> count(String fromSql, PageRequest pageRequest) async {
    String countSql = 'select count(*) from ($fromSql) as c';
    logger.shout('Count sql -> $countSql');
    Response countResponse = await _getResponse(countSql, ResponseType.plain);
    logger.shout('Ch count sql [$countSql] response -> $countResponse');
    return int.parse('${countResponse.data ?? '0'}');
  }
}
