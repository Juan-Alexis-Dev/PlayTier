import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/weighted_shuffle.dart';
import 'package:playtier/domain/models/track.dart';

Track track(String id) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: const ['a1'],
      albumId: 'al1',
      albumName: 'al1',
      duration: const Duration(minutes: 3),
    );

List<String> ids(List<Track> tracks) => tracks.map((t) => t.id).toList();

int count(List<String> round, String id) => round.where((x) => x == id).length;

bool hasAdjacentCopies(List<String> round) {
  for (var i = 1; i < round.length; i++) {
    if (round[i] == round[i - 1]) return true;
  }
  return false;
}

/// Distances between consecutive copies of [id].
List<int> gaps(List<String> round, String id) {
  final positions = [
    for (var i = 0; i < round.length; i++)
      if (round[i] == id) i,
  ];
  return [
    for (var i = 1; i < positions.length; i++) positions[i] - positions[i - 1],
  ];
}

List<String> shuffle(
  List<String> trackIds, {
  Map<String, int> levels = const {},
  int seed = 1,
}) {
  return ids(
    WeightedShuffle.generate(
      [for (final id in trackIds) track(id)],
      levels: levels,
      random: Random(seed),
    ),
  );
}

void main() {
  test('an empty list gives an empty round', () {
    expect(shuffle([]), isEmpty);
  });

  test('level 1 tracks appear once each', () {
    final input = [for (var i = 0; i < 20; i++) 't$i'];
    final round = shuffle(input);

    expect(round, hasLength(20));
    expect(round.toSet(), input.toSet());
  });

  test('copies equal the level (FR-4.7 example)', () {
    final round = shuffle(
      ['A', 'B', 'C', 'D', 'E', 'F'],
      levels: {'E': 2, 'F': 3},
    );

    expect(round, hasLength(9));
    expect(count(round, 'A'), 1);
    expect(count(round, 'E'), 2);
    expect(count(round, 'F'), 3);
    expect(hasAdjacentCopies(round), isFalse);
  });

  test('tracks missing from levels are level 1', () {
    final round = shuffle(['A', 'B', 'C'], levels: {'A': 2});

    expect(count(round, 'B'), 1);
    expect(count(round, 'C'), 1);
  });

  test('levels outside 1–5 are clamped', () {
    final input = [for (var i = 0; i < 10; i++) 't$i'];
    final round = shuffle(input, levels: {'t0': 9, 't1': 0});

    expect(count(round, 't0'), 5);
    expect(count(round, 't1'), 1);
  });

  test('duplicate tracks in the input are used once', () {
    expect(shuffle(['A', 'A', 'B']), hasLength(2));
  });

  group('short lists drop impossible copies', () {
    test('a single track plays once', () {
      expect(shuffle(['A'], levels: {'A': 3}), ['A']);
    });

    test('A level 5 with one other track gives A B A', () {
      expect(shuffle(['A', 'B'], levels: {'A': 5}), ['A', 'B', 'A']);
    });

    test('two level 5 tracks keep all copies, alternating', () {
      final round = shuffle(['A', 'B'], levels: {'A': 5, 'B': 5});

      expect(round, hasLength(10));
      expect(hasAdjacentCopies(round), isFalse);
    });

    test('only the extra copies of the biggest track are dropped', () {
      final round = shuffle(['A', 'B', 'C'], levels: {'A': 5, 'B': 2});

      expect(count(round, 'A'), 4);
      expect(count(round, 'B'), 2);
      expect(count(round, 'C'), 1);
      expect(hasAdjacentCopies(round), isFalse);
    });
  });

  test('never two copies in a row (random lists)', () {
    final rng = Random(42);
    for (var trial = 0; trial < 500; trial++) {
      final size = rng.nextInt(12) + 1;
      final input = [for (var i = 0; i < size; i++) 't$i'];
      final levels = {for (final id in input) id: rng.nextInt(5) + 1};

      final round = shuffle(input, levels: levels, seed: trial);

      expect(hasAdjacentCopies(round), isFalse, reason: '$levels → $round');
      final total = levels.values.fold(0, (a, b) => a + b);
      final biggest = levels.values.reduce(max);
      if (biggest <= total - biggest + 1) {
        for (final id in input) {
          expect(count(round, id), levels[id], reason: '$levels → $round');
        }
      }
    }
  });

  test('copies are spread over the whole round', () {
    final input = [
      for (var i = 0; i < 200; i++) 'low$i',
      for (var i = 0; i < 20; i++) 'high$i',
    ];
    final levels = {for (var i = 0; i < 20; i++) 'high$i': 5};

    for (var seed = 0; seed < 20; seed++) {
      final round = shuffle(input, levels: levels, seed: seed);
      // 300 plays / 5 copies = ideal gap of 60.
      expect(round, hasLength(300));
      for (var i = 0; i < 20; i++) {
        expect(gaps(round, 'high$i').reduce(min), greaterThanOrEqualTo(30));
      }
    }
  });

  group('avoidFirst', () {
    test('the previous last track is never first', () {
      final input = [for (var i = 0; i < 5; i++) 't$i'];
      for (var seed = 0; seed < 100; seed++) {
        final round = ids(
          WeightedShuffle.generate(
            [for (final id in input) track(id)],
            levels: {'t0': 2},
            avoidFirst: 't0',
            random: Random(seed),
          ),
        );

        expect(round.first, isNot('t0'));
        expect(hasAdjacentCopies(round), isFalse);
      }
    });

    test('is ignored when the copies would not fit otherwise', () {
      final round = ids(
        WeightedShuffle.generate(
          [track('A'), track('B')],
          levels: {'A': 5},
          avoidFirst: 'A',
          random: Random(1),
        ),
      );

      expect(round, ['A', 'B', 'A']);
    });
  });

  test('the same seed gives the same round', () {
    final input = [for (var i = 0; i < 30; i++) 't$i'];
    final levels = {'t0': 3, 't5': 2};

    expect(
      shuffle(input, levels: levels, seed: 7),
      shuffle(input, levels: levels, seed: 7),
    );
  });

  test('different seeds give different rounds', () {
    final input = [for (var i = 0; i < 30; i++) 't$i'];

    expect(shuffle(input, seed: 1), isNot(shuffle(input, seed: 2)));
  });
}