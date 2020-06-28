import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

String dateFormat(DateTime dateTime) {
  return "${dateTime.year.toString()}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
}

String timeFormat(DateTime dateTime) {
  return "${dateTime.year.toString()}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}:${dateTime.millisecond.toString().padLeft(3, '0')}";
}

/// 日志系统
///
/// 开启新的 [isolate] 做日志处理，日志近实时打印到控制台且输出到日志文件中
///
/// @author luodongseu
class LogSystem {
  static LogSystem _instance = null;

  LogSystem();

  factory LogSystem.init() {
    if (null != _instance) {
      return _instance;
    }
    _instance = LogSystem();
    _instance._initLog();
    _instance._printBanner();
    return LogSystem();
  }

  void _initLog() {
    ReceivePort receivePort = ReceivePort();
    SendPort _sendPort;
    Completer completer = Completer();
    receivePort.listen((d) {
      if (d is SendPort) {
        _sendPort = d;
        completer.complete();
      }
    });
    // 开启新的isolate处理日志
    Isolate.spawn(_handleLog, receivePort.sendPort);
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((LogRecord e) async {
      LogRecord _log = LogRecord(e.level, e.message, e.loggerName);
      await completer.future;
      _sendPort.send(_log);
    });

    Logger.root.info('Log system initialized on separate isolate.');
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
  static void _handleLog(SendPort sendPort) {
    // 处理目录
    Directory d = Directory('logs');
    if (!d.existsSync()) {
      d.createSync();
    }

    // 写文件的日志队列
    Queue<String> logQueue = Queue();

    // 接收消息
    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    // 处理日志
    receivePort.listen((dynamic e) {
      String lineLog = '';
      if (e is LogRecord) {
        if (e.level == Level.OFF) {
          lineLog = e.message;
        } else {
          lineLog = '[${timeFormat(DateTime.now())}] ${e.toString() ?? ''}';
        }

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

    // 日志文件缓存
    Map<String, RandomAccessFile> openedFiles = HashMap();

    // 定时每10ms打印一行内容
    Timer.periodic(Duration(milliseconds: 1), (t) {
      if (logQueue.isNotEmpty) {
        String line = logQueue.removeFirst();

        // 打印日志到文件
        try {
          String filePath = 'logs/logging.${dateFormat(DateTime.now())}.log';
          RandomAccessFile f;
          if (!openedFiles.containsKey(filePath)) {
            File file = File(filePath);
            if (!file.existsSync()) {
              file.createSync();
            }
            f = file.openSync(mode: FileMode.append);
            openedFiles.putIfAbsent(filePath, () => f);
          } else {
            f = openedFiles[filePath];
          }
          if (null != f) {
            f.writeStringSync(line);
            f.writeStringSync('\r\n');
          }
        } catch (e) {
          print('##### Write log to file failed!!! Error: $e ######');
        }
      }
    });
  }
}
