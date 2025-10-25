// Resultado tipo Either simple
class Result<T> {
  final T? data;
  final String? error;

  const Result._({this.data, this.error});

  factory Result.ok(T data) => Result._(data: data);
  factory Result.err(String error) => Result._(error: error);

  bool get isOk => error == null;
}