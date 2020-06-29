import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import '../bootstrap/application_context.dart';
import '../util/date.dart';
import '../util/string.dart';
import 'logger.dart';

/// 默认的日志文件路径
const String defaultLogFileDir = 'logs';

/// 日志系统
///
/// 开启新的 [isolate] 做日志处理，日志近实时打印到控制台且输出到日志文件中
///
/// @author luodongseu
class LogSystem {
  /// 静态实例
  static LogSystem _instance = null;

  LogSystem._c();

  factory LogSystem._() => LogSystem._c();

  factory LogSystem.init(String dir) {
    if (null != _instance) {
      return _instance;
    }
    _instance = LogSystem._();
    _instance._initLog(dir);
    _instance._printBanner();
    return _instance;
  }

  /// 初始化日志系统
  ///
  /// @step1. 开启新线程，准备接收日志消息
  /// @step2. 监听Logger的日志流
  void _initLog(String dir, {Level rootLevel = INFO}) {
    ReceivePort receivePort = ReceivePort();
    SendPort _sendPort;
    Completer completer = Completer();
    receivePort.listen((d) {
      if (d is SendPort) {
        _sendPort = d;
        completer.complete();

        // 打印日志系统启动成功的日志
        LogRecord _log = LogRecord(
            rootLevel ?? INFO,
            'Log system initialized on separate isolate [${_sendPort?.hashCode}]',
            'LogSystem');
        _sendPort.send(_log);
      }
    });
    // 开启新的isolate处理日志
    LogIsolateMessage message = LogIsolateMessage(
        receivePort.sendPort, isEmpty(dir) ? defaultLogFileDir : dir);
    Isolate.spawn(_handleLog, message);
    Logger.root.level = rootLevel ?? INFO;
    Logger.root.onRecord.listen((LogRecord e) async {
      LogFragment _log = LogFragment(
          e.level,
          e.message,
          e.loggerName,
          '${e.error ?? ''}',
          e.stackTrace?.toString() ?? '',
          ApplicationContext.instance['profile.active'] ?? 'default',
          ApplicationContext.instance['server.port']);
      await completer.future;
      _sendPort.send(_log);
    });
  }

  /// Banner print func
  ///
  /// A Banner is a flag to current application
  ///
  /// 应用的水印，默认读取根目录的banner.txt文件内容
  void _printBanner() {
    File file = File('banner.txt');
    if (null != file && file.existsSync()) {
      file
          .readAsLinesSync()
          .forEach((line) => Logger.root.log(Level.OFF, line));
    }
  }

  /// 处理日志
  static void _handleLog(LogIsolateMessage message) {
    assert(null != message, '消息体内容不能为空');
    assert(isNotEmpty(message.sendPort), '消息体SendPort不能为空');
    assert(isNotEmpty(message.logDir), '消息体日志文件目录不能为空');

    // 处理目录
    Directory d = Directory(message.logDir);
    if (!d.existsSync()) {
      d.createSync();
    }

    // 写文件的日志队列
    Queue<String> logQueue = Queue();

    // 接收消息
    ReceivePort receivePort = ReceivePort();
    message.sendPort.send(receivePort.sendPort);

    // 处理日志
    receivePort.listen((dynamic e) {
      String lineLog = '';
      if (e is LogFragment) {
        lineLog = '${e.toString() ?? ''}';
        // 颜色 打印日志到控制台
//        AnsiPen pen = new AnsiPen();
//        if (e.level == Level.INFO) {
//          pen.green();
//        }
//        if (e.level == Level.SHOUT) {
//          pen.blue();
//        }
//        if (e.level == Level.SEVERE) {
//          pen.red();
//        }
//        print(pen(lineLog));
        print(lineLog);
        // 加入发送日志队列
        logQueue.add(lineLog);
      }
    });

    _startFileWriter(logQueue);
  }

  static _startFileWriter(Queue<String> logQueue) async {
    // 日志文件缓存
    RandomAccessFile openedFile;

    // 定时每1ms打印一行内容
    while (true) {
      if (logQueue.isEmpty) {
        await Future.delayed(Duration(milliseconds: 1));
        continue;
      }
      String line = logQueue.removeFirst();

      // 打印日志到文件
      try {
        String filePath = 'logs/logging.${formatDate(DateTime.now())}.log';
        if (null == openedFile || !openedFile.path.endsWith(filePath)) {
          File file = File(filePath);
          if (!file.existsSync()) {
            file.createSync();
          }
          openedFile = file.openSync(mode: FileMode.append);
        }
        if (null != openedFile) {
          openedFile.writeStringSync(line);
          openedFile.writeStringSync('\r\n');
        }
      } catch (e) {
        print('##### Write log to file failed!!! Error: $e ######');
      }
    }
  }
}

/// 日志线程消息对象
class LogIsolateMessage {
  /// Communication port
  final SendPort sendPort;

  /// Log files directory
  final String logDir;

  LogIsolateMessage(this.sendPort, this.logDir);
}

/// 日志片段
class LogFragment {
  /// Log level
  final Level level;

  /// Message to print
  final String message;

  /// StackTrace to find code quickly in error log
  final String stackTrace;

  /// Logger name, general is class name
  final String loggerName;

  /// Error message
  final String error;

  /// Active profile
  final String profile;

  /// Server port
  final int port;

  LogFragment(
    this.level,
    this.message,
    this.loggerName, [
    this.error,
    this.stackTrace,
    this.profile,
    this.port,
  ]);

  @override
  String toString() {
    if (level == Level.OFF) {
      return message ?? '';
    }
    String result =
        '[${formatTime(DateTime.now())} :${profile ?? '--'}:${port ?? '--'}:] [${level.name}] $loggerName: $message';
    if (isNotEmpty(error)) {
      result += '\n';
      result += '${error}\n';
      result += '${stackTrace}';
    }
    return result;
  }
}
