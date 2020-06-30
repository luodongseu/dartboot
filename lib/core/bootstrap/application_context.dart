import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:yaml/yaml.dart';

import '../annotation/annotation.dart';
import '../database/clickhouse.dart';
import '../eureka/eureka.dart';
import '../log/log_system.dart';
import '../log/logger.dart';
import '../server/server.dart';
import '../util/string.dart';
import 'application_context.g.dart' deferred as gContext;

typedef ExitEvent = Function();

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

  /// 所有的Bean
  List<InstanceMirror> _beans = [];

  /// 所有的控制器
  List<InstanceMirror> _controllers = [];

  /// 启动器，用于注册其他类的启动
  List<Completer> _starters = [];

  /// 系统退出监听器器
  List<ExitEvent> _exitListeners = [];

  /// 是否正在退出
  bool _exiting = false;

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

    // 初始化退出事件监听器
    _listenSystemExit();

    // 扫描带注解的类
    await _scanAnnotatedClasses();

    // register eureka if need
    if (isNotEmpty(this['eureka'])) {
      await EurekaClient.createSync(this['eureka.zone']);
    }

    // init clickhouse if need
    if (isNotEmpty(this['database.clickhouse'])) {
      await ClickHouseDataBase.createSync();
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

  /// 初始化系统进程关闭监听
  _listenSystemExit() {
    // Ctrl+C handler.
    ProcessSignal.sigint.watch().listen((_) async {
      if (_exiting) {
        return;
      }
      _exiting = true;
      try {
        _exitListeners.forEach((f) => f());
      } catch (e) {
        logger.error('Exit listener invoke failed.', e);
      } finally {
        Future.delayed(Duration(milliseconds: 300), () {
          exit(0);
        });
      }
    });
  }

  /// 扫描带注解的所有dart类
  _scanAnnotatedClasses() async {
    // 1. Create BuildContext instance which created by build_runner
    // Dynamic import all controller classes
    logger.info('Start to scan annotated classes in application...');

    await gContext.loadLibrary();
    gContext.BuildContext().load();
    logger.info('Dynamic class -> [BuildContext] loaded.');

    // 所有的镜像
    List<InstanceMirror> allMirrors = _loadAllAnnotatedMirrors();

    // 注解类
    _handleBeans(allMirrors);
    _handleRestControllers(allMirrors);

    logger.info('All annotated classes scanned.');
  }

  /// 加载所有的带有注解的镜子
  ///
  /// 暂时只支持[RestController]、[Bean]注解
  List<InstanceMirror> _loadAllAnnotatedMirrors() {
    List<InstanceMirror> _allInstanceMirrors = [];

    // 是否为合法的对象
    bool isLegalMirror(InstanceMirror m) =>
        m.hasReflectee &&
        (m.reflectee is RestController || m.reflectee is Bean);
    Queue<ClassMirror> classMirrors = Queue();
    currentMirrorSystem().libraries.values.forEach((lm) {
      lm.declarations.values.forEach((dm) {
        if (dm is ClassMirror && dm.metadata.any((m) => isLegalMirror(m))) {
          classMirrors.add(dm);
        }
      });
    });
    int retry = classMirrors.length;
    while (classMirrors.isNotEmpty) {
      assert(retry >= 0, 'Retry initial annotated mirrors failed!');

      ClassMirror dm = classMirrors.removeFirst();
      try {
        _allInstanceMirrors.add(dm.newInstance(Symbol.empty, []));
      } catch (e) {
        logger.debug(
            'Initial class mirror ${dm.simpleName} error $e and it will be initialized again in end.');
        classMirrors.addLast(dm);
        retry--;
      }
    }
    return _allInstanceMirrors;
  }

  /// 加载所有的注解了[Bean]的实例
  _handleBeans(List<InstanceMirror> mirrors) {
    mirrors.forEach((im) {
      bool hasAnn = im.type.metadata.any((m) => m.reflectee is Bean);
      if (hasAnn) {
        Bean bean = im.type.metadata
            .singleWhere((m) => m.reflectee is Bean)
            .reflectee as Bean;
        if (isNotEmpty(bean.conditionOnProperty) &&
            isEmpty(this[bean.conditionOnProperty])) {
          return;
        }
        _beans.add(im);
      }
    });
    logger.info("Bean scan finished. Total ${_beans.length} beans.");
    _beans
        .forEach((c) => logger.info("Bean: ${c.type.simpleName} registered."));
  }

  /// 加载所有的注解了[RestController]的实例
  _handleRestControllers(List<InstanceMirror> mirrors) {
    mirrors.forEach((im) {
      bool hasAnn = im.type.metadata.any((m) => m.reflectee is RestController);
      if (hasAnn) {
        RestController rc = im.type.metadata
            .singleWhere((m) => m.reflectee is RestController)
            .reflectee as RestController;
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
    _controllers.forEach(
        (c) => logger.info("RestController: ${c.type.simpleName} registered."));
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

  /// 添加退出监听器
  void listenExit(ExitEvent event) {
    assert(null != event, 'Parameter must not be null');

    _exitListeners.add(event);
  }

  /// 是否Starters全部准备好
  bool get _startersReady => !_starters.any((c) => !c.isCompleted);
}
