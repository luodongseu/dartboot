import 'dart:async';
import 'dart:io';

import 'package:dartboot/core/dartboot.dart';

/// 应用的真正运行入口:
///   `dart bin/main.dart`
///
/// 目前支持运行参数:
/// -port=XXXX 端口号，会覆盖配置文件中的配置，至少4位数字
main(List<String> args) async {
  /// 项目路径
  String projectPath = FileSystemEntity.parentOf(
      FileSystemEntity.parentOf(Platform.script.toString()));
  projectPath =
      projectPath.replaceFirst('file://${Platform.isWindows ? '/' : ''}', '');

  print('Starting dart main script on root path: $projectPath...');

  /// 入口函数调用该方法即可
  runZoned(() {
    DartBootApplication.run(rootPath: projectPath, args: args);
  }, onError: (e) {
    if (e is Error) {
      print('''
##########################################
[DartBoot application error] ${e?.toString() ?? ''}
${e?.stackTrace ?? ''}
##########################################
''');
    } else {
      print('## DartBoot application error: ${e} ##');
    }
  });
}
