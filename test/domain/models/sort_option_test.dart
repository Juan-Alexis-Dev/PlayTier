import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/sort_option.dart';

void main() {
  test('default is date added, newest first', () {
    expect(SortOption.defaultOption.field, SortField.dateAdded);
    expect(SortOption.defaultOption.isAscending, isFalse);
  });

  test('reversed flips only the direction', () {
    const option = SortOption(SortField.title, SortDirection.ascending);
    expect(option.reversed.field, SortField.title);
    expect(option.reversed.direction, SortDirection.descending);
    expect(option.reversed.reversed, option);
  });

  test('equality and copyWith', () {
    const option = SortOption(SortField.album, SortDirection.ascending);
    expect(option, const SortOption(SortField.album, SortDirection.ascending));
    expect(option.copyWith(field: SortField.duration).field, SortField.duration);
    expect(option.copyWith(field: SortField.duration), isNot(option));
  });
}