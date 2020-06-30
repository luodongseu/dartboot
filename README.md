[![Build Status](https://travis-ci.org/Daegalus/dart-uuid.svg?branch=master)](https://travis-ci.org/Daegalus/dart-uuid)

# DartBoot

**A more simple framework to build a dart server side application, just like spring boot application in java**

Features:

* Simple configuration to startup by using config[-profile].yaml
* Auto scan `@RestController` classes which are rest api endpoints
* Write rest controllers just like springboot rest controller by use multi annotations
* Use eureka to observe and communicate to micro services
* Use mysql connection pool to keep mysql clients
* Also integrated with [ClickHouse](!https://clickhouse.tech/) by rest api
* A designed log system to capture all logs and synchronize to files

Besides，I will continue to enrich this framework to support more and more features like in spring boot.

## Getting Started

**Git clone this repository,  and you can modify anything you want to build your own application**

### Directories

- `bin` This is dart application start entry file's directory. `main.dart` is the startup script file. Use `dart bin/main.dart` to start this application
- `lib` This is source code library directory. All code should be placed to here
- `lib/core` This is dartboot core code directory. Of course, you can modify any code
> - `lib/core/annotation` Current support annotations
> - `lib/core/bootstrap` Application context library
> - `lib/core/builder` Source code generation builders, see more detail to [source_gen](!https://pub.dev/packages/source_gen)
> - `lib/core/database` ClickHouse client、Mysql connection pool、page request
> - `lib/core/error` A custom error used by core
> - `lib/core/eureka` Eureka client and rest api caller like feign client
> - `lib/core/log` A designed log system to record logs, print to console and log files also
> - `lib/core/retry` Retry class
> - `lib/core/server` Http server core code 
> - `lib/core/util` Helper classes to make code more simple
> - `lib/core/dartboot.dart` DartBootApplication class. Startup a dart boot application is very simple, just like `bin/main.dart` code invoke: `DartBootApplication.run()`
- `lib/feign` Put feign clients (which used to call other micro services) to here refer to example code
```dart
import 'package:dartboot/core/eureka/eureka.dart';

/// User服务的FeignClient
class UserFeignClient {
  static EurekaRestClient _client =
      EurekaRestClient('user', rootPath: '/api-user');

  static EurekaRestClient get client => _client;
}
``` 
- `logs` The log files directory
- `resource` A public resource directory. Config files in different profiles is in root path, and static files (like html、css files) should be in child: `static` directory. Currently, only few extensions' files could be served as static files, but you can config `server.static.supportExts` in config files to change supported static files patterns

**Static files**
- `banner.txt` If you used springboot before, you would known what is a banner for springboot application. Yes, that's it. [Make it now](!https://devops.datenkollektiv.de/banner.txt/index.html)
- `build.yaml` More details to see [build_runner config](!https://dart-pub.mirrors.sjtug.sjtu.edu.cn/packages/build_config). Please change package name in `import` configs (total 2 positions)
 > `import: "package:dartboot/core/builder/boot_builder.dart"` # 这里请使用pubspec.yaml中的name替换'dartboot'
- `pubspec.yaml` Modify basic info in this file, like name、description etc. Don't delete any exists dependencies and you can add any third packages here
- `README.md` It's me
 
### Instructions

Follow these steps, you can run and code your own dart boot application:

1. Open terminal to run command: `pub get`. Maybe you should put `pub` command in dart `bin` directory to `PATH`. This command is get all dependence packages this application needed.
2. Open terminal (before is ok) to run command: `pub run build_runner watch` to listen your code change events and generate dynamic codes (which defined in `boot_builder`). Now you can add a new rest controller class with `@RestController` annotation and application will scan it automatic right now.
3. Write any rest controllers (rest api) or services code in `lib` path. Add any directory if you want.
4. When code already, next is to run application to test. Open a new terminal to run command: `dart bin/main.dart`, and you will see `Application startup completed.` in terminal outputs which means application startup success.
5. Open a restful api client or browser to invoke your rest api like in example:`http://localhost:8700/dartboot/api/v1/example01?test=heello`, and you will see outputs:
```json
{
  "a": "Example 01 response: heello"
}
```

## Configurations

- `profile.active` Active profile identifier which used to discover config extend config file. For example , value is `dev`, then application will load `config-dev.yaml` in resources directory
> **Note:**
> **properties in `config-[profile].yaml` will override same root key properties in `config.yaml`**
- `app.name` Application identifier which will registered to eureka center server
- `server.port` Http server bind port
- `server.context-path` Http server root endpoint which will append as prefix to any http request (except for static files in `resource/static/` directory)
- `eureka.zone` Eureka server url, usually it's endWiths `/eureka`
- `eureka.fetch-registry-interval-seconds` Interval seconds for eureka client to fetch all applications registered in eureka center server
- `eureka.heartbeat-interval-seconds` Interval seconds for eureka clients send heartbeat signal to eureka center server, to keep client online
- `database` Mysql database or mongodb database configuration should be placed here
- `database.[mysql_id].host` Mysql server host address
- `database.[mysql_id].port` Mysql server port
- `database.[mysql_id].db` Mysql server database name
- `database.[mysql_id].username` Mysql server connect user name
- `database.[mysql_id].password` Mysql server connect user password
- `database.[mysql_id].min-pool-size` Mysql connection pool min keep alive size
- `database.[mysql_id].max-pool-size` Mysql connection pool max connection size

## Release notes

This project is still in development. Contact me or submit issues if you have any questions or meet any bug.


> Open source to make code world better.
