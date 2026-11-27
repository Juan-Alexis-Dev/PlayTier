import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:playtier/features/browse/browse_screen.dart';
import 'package:playtier/features/browse/browse_view_model.dart';
import 'package:provider/provider.dart';

BrowseItem item(String name, {int count = 2}) =>
    (id: name, name: name, trackCount: count, coverUrls: const <String>[]);

void main() {
  Future<StreamController<List<BrowseItem>>> pumpScreen(
    WidgetTester tester, {
    void Function(BrowseItem)? onOpen,
  }) async {
    final source = StreamController<List<BrowseItem>>();
    addTearDown(source.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => BrowseViewModel(source.stream)..init(),
          child: BrowseScreen(kind: BrowseKind.genres, onOpen: onOpen),
        ),
      ),
    );
    return source;
  }

  testWidgets('shows a spinner, then the cards', (tester) async {
    final source = await pumpScreen(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    source.add([item('rock', count: 12), item('pop', count: 1)]);
    await tester.pump();

    expect(find.text('rock'), findsOneWidget);
    expect(find.text('12 tracks'), findsOneWidget);
    expect(find.text('1 track'), findsOneWidget);
  });

  testWidgets('an empty library shows the empty state', (tester) async {
    final source = await pumpScreen(tester);
    source.add([]);
    await tester.pump();

    expect(find.textContaining('No genres yet'), findsOneWidget);
  });

  testWidgets('typing filters; clear restores every card', (tester) async {
    final source = await pumpScreen(tester);
    source.add([item('rock'), item('pop')]);
    await tester.pump();

    await tester.enterText(find.byType(SearchBar), 'po');
    await tester.pump();
    expect(find.text('rock'), findsNothing);
    expect(find.text('pop'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'jazz');
    await tester.pump();
    expect(find.textContaining('No genres match'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('rock'), findsOneWidget);
    expect(find.text('pop'), findsOneWidget);
    expect(find.text('jazz'), findsNothing);
  });

  testWidgets('tapping a card calls onOpen with its item', (tester) async {
    BrowseItem? opened;
    final source = await pumpScreen(tester, onOpen: (i) => opened = i);
    source.add([item('rock')]);
    await tester.pump();

    await tester.tap(find.text('rock'));
    expect(opened?.id, 'rock');
  });
}