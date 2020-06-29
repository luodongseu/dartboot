library dartboot;

import 'dart:async';

import 'bootstrap/application_context.dart';

/// Dart的快速启动入口类
///
/// 调用静态方法：[ DartBootApplication.run ] 即可启动容器
/// 参数：[propertiesFilePath] 为全局配置文件文件，默认取根目录下的config.yaml
///
/// @author luodongseu
class DartBootApplication {
  static Future run({String propertiesFilePath}) async {
    ApplicationContext context = ApplicationContext();
    context.initialize();
  }
}
