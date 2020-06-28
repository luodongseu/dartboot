import 'package:dartboot/core/eureka/eureka.dart';

/// 自身的FeignClient
class SelfFeignClient {
  static EurekaRestClient _client =
      EurekaRestClient('dartboot', rootPath: '/dartboot');

  static EurekaRestClient get client => _client;
}
