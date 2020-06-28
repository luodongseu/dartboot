part of annotation;

/// @Annotation Get
///
/// 查询请求的注解
///
/// example:
/// ``` @Get('/submitForm') ```
///
/// @author luodongseu
class Get extends Request {
  const Get([String path = '/', ResponseType responseType = ResponseType.json])
      : super(HttpMethod.GET, path: path, responseType: responseType);
}
