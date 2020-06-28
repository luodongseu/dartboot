import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../bootstrap/application_context.dart';
import '../error/custom_error.dart';
import '../util/ipaddress.dart';
import '../util/string.dart';
import '../util/uid.dart';
import 'instance.dart';

/// 心跳间隔时间
final Duration defaultHeartbeatDuration = Duration(seconds: 30);

/// 获取应用列表间隔时间
final Duration defaultFetchAppDuration = Duration(seconds: 15);

/// Eureka的客户端
///
/// step1. 注册服务
/// step2. 服务续约
/// step3. 服务下线
/// step4. 获取服务列表、刷新服务列表
class EurekaClient {
  Logger logger = Logger('EurekaClient');

  static EurekaClient _instance;

  /// APP ID
  final String _appId =
      ApplicationContext.instance['app']['name'] ?? 'APP_$uid4';

  /// 端口号
  final int _port =
      int.parse('${ApplicationContext.instance['server']['port'] ?? 8080}');

  /// 实例ID
  String _instanceId;

  /// 心跳的时间调度器
  Timer _heartbeatTimer;

  /// 获取应用列表的时间调度器
  Timer _fetchAppTimer;

  /// DIO客户端
  Dio _rc;

  /// 客户端列表
  List<App> _applications;

  /// 是否在线
  bool _isUp = true;

  /// 是否准备好
  bool _isReady = false;

  /// 中心地址
  final String defaultZone;

  /// 监听器
  List<StreamController> _appListeners = [];

  factory EurekaClient(defaultZone) {
    if (null == _instance) {
      _instance = EurekaClient._(defaultZone: defaultZone);
    }
    return _instance;
  }

  EurekaClient._({this.defaultZone = 'http://localhost:8761/eureka/'}) {
    _initRc();
    _register();
  }

  static EurekaClient get instance => _instance;

  List<App> get apps => _applications;

  bool get ready => _isReady;

  /// 监听
  void listenApp(StreamController listener) {
    _appListeners.add(listener);
    if (ready) {
      listener.add(DateTime.now());
    }
  }

  /// 初始化Rest客户端
  _initRc() {
    logger.fine('Start to init rest client...');
    _rc = Dio(BaseOptions(
        receiveDataWhenStatusError: true,
        contentType: 'application/json',
        responseType: ResponseType.json));
    _rc.interceptors
        .add(InterceptorsWrapper(onRequest: (RequestOptions options) async {
      return options; //continue
    }, onResponse: (Response response) async {
      return response; // continue
    }, onError: (DioError e) async {
      logger.severe('_rc client request failed!', e);
      return null; //continue
    }));
    logger.fine('Rest client initilized.');
  }

  /// 注册客户端
  _register() async {
    _instanceId = '${_appId}_$uid8:$_port';

    logger.fine(
        'Start to register client:[$_instanceId] to center:[$defaultZone]...');

    try {
      var url = '$defaultZone/apps/$_appId';
      var inst = await Instance(
              instanceId: _instanceId,
              ipAddr: await localIp(),
              port: _port,
              appId: _appId,
              contextPath: ApplicationContext.instance['server']['contextPath'],
              status: 'UP')
          .toJson();
      await _rc.post(url, data: {'instance': inst});

      logger.fine('Client:[$_instanceId] registered.');

      // 开始获取应用列表
      _startFetchAppTimer();

      // 开启心跳
      _startHeartbeatTimer();
    } catch (e) {
      logger.severe('Register failed!', e);
      throw CustomError('无法初始化Eureka客户端');
    }
  }

  /// 开启心跳时间定时器
  _startHeartbeatTimer() {
    if (null != _heartbeatTimer) {
      _heartbeatTimer.cancel();
    }
    _heartbeatTimer = Timer.periodic(defaultHeartbeatDuration, (t) {
      _sendHeartBeat();
    });
  }

  /// 发送心跳
  _sendHeartBeat() async {
    logger.fine('Start to send heartbeat to center:[$defaultZone]...');

    try {
      var url =
          '$defaultZone/apps/$_appId/$_instanceId?status=${_isUp ? 'UP' : 'DOWN'}';
      await _rc.put(url);
    } catch (e) {
      logger.severe('Send heartbeat failed!', e);
      throw CustomError('无法发送心跳');
    }

    logger.fine('Send heartbeat success.');
  }

  /// 下线服务
  down() async {
    logger.fine('Start to down client...');

    _isUp = false;

    logger.fine('Down client success.');
  }

  /// 上线
  up() async {
    logger.fine('Start to up client...');

    _isUp = true;

    logger.fine('Up client success.');
  }

  /// 关闭
  shutdown() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _fetchAppTimer?.cancel();
    _fetchAppTimer = null;
  }

  /// 从注册中心移除客户端
  unregister() async {
    logger.fine('Start to unregister client...');

    try {
      shutdown();
      await _rc.delete('$defaultZone/apps/$_appId/$_instanceId');
    } catch (e) {
      logger.severe('Unregister failed!', e);
      throw CustomError('无法移除Eureka客户端');
    }

    logger.fine('Unregister client success.');
  }

  /// 开启获取应用列表时间定时器
  _startFetchAppTimer() {
    if (null != _fetchAppTimer) {
      _fetchAppTimer.cancel();
    }
    _fetchApplications();
    _fetchAppTimer = Timer.periodic(defaultFetchAppDuration, (t) {
      _fetchApplications();
    });
  }

  /// 获取应用列表
  _fetchApplications() async {
    logger.fine('Start to fetch applications from center:[$defaultZone]...');

    var url = '$defaultZone/apps/';
    try {
      var res = await _rc.get(url,
          options: Options(headers: {'Accept': 'application/json'}));
      if (!isEmpty(res.data['applications']['application'])) {
        _applications = List.from(res.data['applications']['application'])
            .map((app) => App.fromJson(app))
            .toList();
      }

      // 设置为准备好
      _isReady = true;

      // 通知监听器
      _notifyAppListeners();

      logger.fine('${_applications.length} applications fetched.');

      return true;
    } catch (e) {
      logger.severe('Cannot get applications from center.', e);
      return false;
    }
  }

  /// 通知监听器
  _notifyAppListeners() {
    _appListeners
        ?.forEach((cp) => cp.add(DateTime.now().millisecondsSinceEpoch));
  }
}
