/// Result of an operation that can fail.
///
/// Repositories return a [Result] instead of throwing, so no exception
/// reaches a View. Use a `switch` to handle both cases:
///
/// ```dart
/// switch (result) {
///   case Ok(:final value):
///     // use value
///   case Error(:final error):
///     // show error
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Creates a successful result holding [value].
  const factory Result.ok(T value) = Ok<T>;

  /// Creates a failed result holding [error].
  const factory Result.error(Exception error) = Error<T>;
}

/// Successful [Result] with a [value].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  String toString() => 'Result<$T>.ok($value)';
}

/// Failed [Result] with an [error].
final class Error<T> extends Result<T> {
  const Error(this.error);

  final Exception error;

  @override
  String toString() => 'Result<$T>.error($error)';
}