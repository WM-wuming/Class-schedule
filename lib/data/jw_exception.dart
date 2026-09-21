/// 从教务系统获取课表失败。
class JwException implements Exception {
  const JwException(this.message);

  /// 给用户看的中文错误说明。
  final String message;

  @override
  String toString() => message;
}
