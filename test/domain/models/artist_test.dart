import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/artist.dart';

void main() {
  test('genres default to an empty list', () {
    expect(const Artist(id: 'a1', name: 'A').genres, isEmpty);
  });

  test('equality compares genres by content', () {
    const a = Artist(id: 'a1', name: 'A', genres: ['rock', 'pop']);
    final b = Artist(id: 'a1', name: 'A', genres: ['rock', 'pop'].toList());

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(a.copyWith(genres: ['rock'])));
  });

  test('copyWith keeps the other fields', () {
    const a = Artist(id: 'a1', name: 'A', genres: ['rock']);

    expect(a.copyWith(name: 'B'), const Artist(id: 'a1', name: 'B', genres: ['rock']));
  });
}