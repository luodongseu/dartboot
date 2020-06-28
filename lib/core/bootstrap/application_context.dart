import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import '../annotation/annotation.dart';
import '../eureka/eureka.dart';
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
  Logger logger = Logger('DartBootApplication');

  /// 单例
  static ApplicationContext _instance;

  /// 全局的配置
  Map<String, dynamic> _properties = Map();

  /// 配置文件路径
  final String propertiesFilePath;

  /// 所有的控制器
  List<InstanceMirror> controllers = [];

  /// 实例
  static ApplicationContext get instance => _instance;

  /// 配置信息
  dynamic operator [](String key) {
    if (key.contains('.')) {
      List<String> _keys = key.split('.');
      var result = _properties;
      for (int i = 0; i < _keys.length; i++) {
        if (i == _keys.length - 1) {
          return result;
        }
        var _r = result[_keys[i]];
        if (null == _r) {
          return null;
        }
        result = _r;
      }
    }
    return _properties[key];
  }

  ApplicationContext({this.propertiesFilePath}) {
    _instance = this;
  }

  /// 初始化操作
  ///
  /// 请在[main.dart]中调用该方法启动DartBoot应用
  initialize() async {
    // 加载配置文件
    loadProperties(
        propertiesFilePath: propertiesFilePath ?? 'resource/config.yaml');

    // 扫描bean
    await scanBeans();

    // 开启服务
    startServer();

    // register erueka if need
    if (!isEmpty(_properties['eureka'])) {
      EurekaClient(_properties['eureka']['zone']);
    }
  }

  /// 加载配置文件
  Future loadProperties({String propertiesFilePath}) async {
    File file = File(propertiesFilePath);
    if (null != file && file.existsSync()) {
      // 读取基本配置文件
      YamlMap yaml = loadYaml(file.readAsStringSync());
      yaml.entries.forEach((e) {
        _properties['${e.key}'] = e.value;
      });

      // 读取profile对应的配置文件
      if (null != _properties['profile'] &&
          !isEmpty(_properties['profile']['active'])) {
        File profileFile = File(propertiesFilePath.replaceFirst(
            RegExp('.yaml\$'), '-${_properties['profile']['active']}.yaml'));
        if (file.existsSync()) {
          YamlMap profileYaml = loadYaml(profileFile.readAsStringSync());
          profileYaml.entries.forEach((e) {
            _properties['${e.key}'] = e.value;
          });
        }
      }

      logger.info('Properties load finished. $_properties');
    }
  }

  /// 扫描Bean
  ///
  /// 包含： [RestController]
  void scanBeans() async {
    // 1. Create BuildContext instance which created by build_runner
    // Dynamic import all controller classes
    logger.info('Start to scan beans in application...');

    await gContext.loadLibrary();
    gContext.BuildContext().load();
    logger.info('Dynamic class -> BuildContext loaded.');

    // 所有的镜像
    List<InstanceMirror> allMirrors = _loadAllAnnotatedMirrors();

    // 2. 扫描接口控制器
    _handleRestControllers(allMirrors);

    logger.info('Known beans scan finished.');
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
        controllers.add(im);
      }
    });
    logger.info(
        "RestController scan finished. ${controllers.map((c) => c.type.simpleName).toList()}");
  }

  /// 开启http服务
  startServer() {
    logger.info('Start to start http server...');
    Server server = Server(controllers);
    server.start();
  }
}
