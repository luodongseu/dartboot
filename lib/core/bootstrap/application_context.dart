import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:yaml/yaml.dart';

import '../annotation/annotation.dart';
import '../eureka/eureka.dart';
import '../log/log_system.dart';
import '../log/logger.dart';
import '../server/server.dart';
import '../util/string.dart';
import 'application_context.g.dart' deferred as gContext;

/// DartBoot Application entry side
///
/// 应用的入口类
///
/// @加载配置文件
/// @扫描RestController
/// @启动Http服务
/// @启动Eureka客户端
///
/// @author luodongseu
@BootContext()
class ApplicationContext {
  Log logger = Log('DartBootApplication');

  /// 单例
  static ApplicationContext _instance;

  /// 全局的配置
  dynamic _properties = {};

  /// 配置文件路径
  String _configFilePath;

  /// 所有的控制器
  List<InstanceMirror> _controllers = [];

  /// 启动器，用于注册其他类的启动
  List<Completer> _starters = [];

  /// 实例
  static ApplicationContext get instance => _instance;

  ApplicationContext({configFilePath = 'config.yaml'}) {
    _configFilePath = configFilePath;
    _instance = this;
  }

  /// 获取全局配置操作
  dynamic operator [](String key) {
    if (key.contains('.')) {
      List<String> _keys = key.split('.');
      dynamic result = _properties;
      for (int i = 0; i < _keys.length; i++) {
        var _r = result[_keys[i]];
        if (null == _r) {
          return null;
        }
        result = _r;
        if (i == _keys.length - 1) {
          return result;
        }
      }
    }
    return _properties[key];
  }

  /// 初始化操作
  ///
  /// 请在[main.dart]中调用该方法启动DartBoot应用
  initialize() async {
    // 加载配置文件
    _loadProperties(propertiesFilePath: _configFilePath ?? 'config.yaml');

    // 初始化日志系统
    LogSystem.init(this['logging.dir']);

    // 扫描bean
    await _scanBeans();

    // register eureka if need
    if (isNotEmpty(this['eureka'])) {
      await EurekaClient.createSync(this['eureka.zone']);
    }

    // 开启服务
    await _startServer();

    // 等待所有启动器准备好
    while (!_startersReady) {
      logger.info('Wait starters to ready, try agin 3 secs later...');
      await Future.delayed(Duration(seconds: 3));
    }

    logger.info('Application startup completed.');
  }

  /// 加载配置文件
  _loadProperties({String propertiesFilePath}) {
    assert(isNotEmpty(propertiesFilePath), '配置文件路径不能为空');

    // 完整路径
    String fullPath = 'resource/$propertiesFilePath';

    // Bcz log system not initialize
//    print('Start to load properties from $fullPath...');

    File file = File(fullPath);
    if (null != file && file.existsSync()) {
      // 读取基本配置文件
      YamlMap yaml = loadYaml(file.readAsStringSync());
      _properties = json.decode(json.encode(yaml)) ?? {};

      // 读取profile对应的配置文件
      if (null != this['profile'] && isNotEmpty(this['profile.active'])) {
        File profileFile = File(fullPath.replaceFirst(
            RegExp('.yaml\$'), '-${this['profile.active']}.yaml'));
        if (file.existsSync()) {
          YamlMap profileYaml = loadYaml(profileFile.readAsStringSync());
          profileYaml.entries.forEach((e) {
            _properties['${e.key}'] = json.decode(json.encode(e.value));
          });
        }
      }
    }

    // Bcz log system not initialize
//    print('Config properties [$_properties] loaded.');
  }

  /// 扫描Bean
  ///
  /// 包含： [RestController]
  _scanBeans() async {
    // 1. Create BuildContext instance which created by build_runner
    // Dynamic import all controller classes
    logger.info('Start to scan beans in application...');

    await gContext.loadLibrary();
    gContext.BuildContext().load();
    logger.info('Dynamic class -> [BuildContext] loaded.');

    // 所有的镜像
    List<InstanceMirror> allMirrors = _loadAllAnnotatedMirrors();

    // 2. 扫描接口控制器
    _handleRestControllers(allMirrors);

    logger.info('Beans scan finished.');
  }

  /// 加载所有的带有注解的镜子
  ///
  /// 暂时只支持[RestController]注解
  List<InstanceMirror> _loadAllAnnotatedMirrors() {
    List<InstanceMirror> _allInstanceMirrors = [];
    currentMirrorSystem().libraries.values.forEach((lm) {
      lm.declarations.values.forEach((dm) {
        if (dm is ClassMirror &&
            dm.metadata
                .any((m) => m.hasReflectee && m.reflectee is RestController)) {
          _allInstanceMirrors.add(dm.newInstance(Symbol.empty, []));
        }
      });
    });
    return _allInstanceMirrors;
  }

  /// 加载所有的注解了[RestController]的实例
  Future _handleRestControllers(List<InstanceMirror> mirrors) async {
    mirrors.forEach((im) {
      RestController rc = im.type.metadata
          .singleWhere((m) => m.reflectee is RestController)
          .reflectee as RestController;
      if (null != rc) {
        // 处理RestController基础的路由
        String bp = rc.basePath ?? '/';
        if (!bp.startsWith('/')) {
          bp = '/' + bp;
        }
        _controllers.add(im);
      }
    });
    logger.info(
        "RestController scan finished. Total ${_controllers.length} controllers.");
    _controllers
        .forEach((c) => logger.info("RestController: ${c.type.simpleName}."));
  }

  /// 开启http服务
  _startServer() async {
    Server server = Server(_controllers);
    await server.start();
  }

  /// 添加启动器，通过[Completer] [Completer.complete()]控制生命周期
  void addStarter(Completer completer) {
    assert(null != completer, 'Parameter must not be null');

    _starters.add(completer);
  }

  /// 是否Starters全部准备好
  bool get _startersReady => !_starters.any((c) => !c.isCompleted);
}
