part of annotation;

/// @Annotation Delete
///
/// 删除请求的注解
///
/// example:
/// ``` @Delete('/article/1') ```
///
/// @author luodongseu
class Delete extends Request {
  const Delete(
      [String path = '/', ResponseType responseType = ResponseType.json])
      : super(HttpMethod.DELETE, path: path, responseType: responseType);
}
