part of annotation;

/// ====================================================
/// @Annotation Bean
///
/// 实例注解，使用该注解的类会自动加入到 [ApplicationContext] 中，无参的构造函数会在启动时被系统调用
/// 然后可以通过 [mirrors] 扫描且应用
///
/// example:
/// ```dart
/// @Bean(conditionOnProperty: 'abc.def')
/// class TestService {
///
///   /// default constructor will be invoked automatic
///   TestService() {
///
///   }
/// }
///
/// ```
///
/// @author luodongseu
/// ====================================================
///
class Bean {
  /// 实例化条件：当存在指定的配置key
  final String conditionOnProperty;

  const Bean({this.conditionOnProperty});
}
