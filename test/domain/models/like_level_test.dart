import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/like_level.dart';

void main() {
  test('accepts values 1 to 5', () {
    for (var i = 1; i <= 5; i++) {
      expect(LikeLevel(i).value, i);
    }
  });

  test('rejects values outside 1 to 5', () {
    expect(() => LikeLevel(0), throwsRangeError);
    expect(() => LikeLevel(6), throwsRangeError);
    expect(() => LikeLevel(-1), throwsRangeError);
  });

  test('default level is 1 and not liked', () {
    expect(LikeLevel.defaultLevel.value, 1);
    expect(LikeLevel.defaultLevel.isLiked, isFalse);
  });

  test('levels 2 to 5 are liked', () {
    expect(LikeLevel(2).isLiked, isTrue);
    expect(LikeLevel(5).isLiked, isTrue);
  });

  test('equality by value', () {
    expect(LikeLevel(3), LikeLevel(3));
    expect(LikeLevel(3).hashCode, LikeLevel(3).hashCode);
    expect(LikeLevel(3), isNot(LikeLevel(4)));
    expect(LikeLevel(1), LikeLevel.defaultLevel);
  });

  test('toString shows the value', () {
    expect(LikeLevel(4).toString(), 'LikeLevel(4)');
  });
}