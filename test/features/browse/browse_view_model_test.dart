import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/features/browse/browse_view_model.dart';

BrowseItem item(String name, {int count = 1}) =>
    (id: name, name: name, trackCount: count, coverUrls: const <String>[]);

/// Lets the stream deliver its events.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<List<BrowseItem>> source;
  late BrowseViewModel vm;

  setUp(() {
    source = StreamController<List<BrowseItem>>();
    vm = BrowseViewModel(source.stream)..init();
  });
  tearDown(() {
    vm.dispose();
    source.close();
  });

  test('is loading until the first list arrives', () async {
    expect(vm.loading, isTrue);
    expect(vm.items, isEmpty);

    source.add([item('rock')]);
    await pump();

    expect(vm.loading, isFalse);
    expect(vm.items, [item('rock')]);
  });

  test('keeps the source order', () async {
    source.add([item('rock', count: 9), item('pop', count: 5)]);
    await pump();
    expect([for (final i in vm.items) i.name], ['rock', 'pop']);
  });

  test('query filters by name, ignoring case and accents', () async {
    source.add([
      item('Rock en español'),
      item('Pop'),
      item('Café Tacvba'),
    ]);
    await pump();

    vm.setQuery('ESPANOL');
    expect([for (final i in vm.items) i.name], ['Rock en español']);

    vm.setQuery('  café ');
    expect([for (final i in vm.items) i.name], ['Café Tacvba']);

    vm.setQuery('');
    expect(vm.items, hasLength(3));
    expect(vm.totalCount, 3);
  });

  test('new source lists keep the current query', () async {
    source.add([item('rock')]);
    await pump();
    vm.setQuery('pop');
    expect(vm.items, isEmpty);

    source.add([item('rock'), item('k-pop')]);
    await pump();

    expect([for (final i in vm.items) i.name], ['k-pop']);
    expect(vm.totalCount, 2);
  });

  test('notifies listeners on new data and on query changes', () async {
    var notified = 0;
    vm.addListener(() => notified++);

    source.add([item('rock')]);
    await pump();
    vm.setQuery('r');
    vm.setQuery('r'); // same query: no extra notification

    expect(notified, 2);
  });

  test('a source error shows a message', () async {
    source.addError(Exception('db closed'));
    await pump();

    expect(vm.loading, isFalse);
    expect(vm.errorMessage, isNotNull);
  });
}