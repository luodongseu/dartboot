part of annotation;

const bean = const Bean();

/// ====================================================
/// @Annotation Bean
///
/// 实例注解，使用该注解的类会自动加入到 [ApplicationContext] 中，无参的构造函数会在启动时被系统调用
/// 然后可以通过 [mirrors] 扫描且应用
///
/// example:
/// ```dart
/// @bean
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
  const Bean();
}
