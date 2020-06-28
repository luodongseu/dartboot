/// 分页的抽象接口
///
/// 用于处理接口分页查询
///
/// [offset]表示分页的其实下标，从0开始
///
/// @author luodongseu
abstract class Pageable<T> {

  /// 当前页码，0表示第一页
  int get page;

  /// 每页大小
  int get pageSize;

  /// 总记录数
  int get total;

  /// 数据内容，列表
  List<T> get content;

  /// 查询的起始偏移下标
  /// [offset] = [page] * [pageSize]
  int get offset => page * pageSize;

  Map<String, dynamic> toJson() =>
      {
        'page': page ?? 0,
        'pageSize': pageSize ?? 0,
        'total': total ?? 0,
        'content': content ?? [],
      };
}

/// 分页的简单实现
class PageImpl<T> extends Pageable<T> {

  final int _page;

  final int _pageSize;

  final int _total;

  final List<T> _content;

  PageImpl(this._content, this._page, this._pageSize, this._total);

  @override
  int get page => _page ?? 0;

  @override
  int get pageSize => _pageSize ?? 10;

  @override
  int get total => _total ?? 0;

  @override
  List<T> get content => _content ?? [];

}

/// 分页请求，用于查询参数
///
/// example:
/// ``` PageRequest(page: 1, limit: 10) ```
///
/// 或者使用工厂函数构造：
/// ``` PageRequest.of(0, 10) ```
class PageRequest {

  /// 页码
  final int page;

  /// 每页大小
  final int limit;

  /// 起始偏移
  int get offset => page * limit;

  PageRequest({this.page = 0, this.limit = 10});

  factory PageRequest.of(int page, int limit) {
    return PageRequest(page: page ?? 0, limit: limit ?? 10);
  }

}