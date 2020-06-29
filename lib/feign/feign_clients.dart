import '../core/eureka/eureka.dart';

/// ////////////////////////////////////////////////
/// Eureka客户端集合
/// ////////////////////////////////////////////////

/// 自身的FeignClient
class SelfFeignClient {
  static EurekaRestClient _client =
      EurekaRestClient('dartboot', rootPath: '/dartboot');

  static EurekaRestClient get client => _client;
}

/// 其他FeignClient
///
// class OtherFeignClient {
//  static EurekaRestClient _client =
//      EurekaRestClient('other', rootPath: '/other-api-context');
//
//  static EurekaRestClient get client => _client;
//}
