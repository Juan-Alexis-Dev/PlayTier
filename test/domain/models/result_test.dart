import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/result.dart';

String describe(Result<int> result) => switch (result) {
      Ok(:final value) => 'ok $value',
      Error(:final error) => 'error $error',
    };

void main() {
  test('Result.ok holds the value', () {
    const result = Result.ok(42);

    expect(result, isA<Ok<int>>());
    expect(describe(result), 'ok 42');
  });

  test('Result.error holds the exception', () {
    final result = Result<int>.error(Exception('boom'));

    expect(result, isA<Error<int>>());
    expect(describe(result), 'error Exception: boom');
  });
}