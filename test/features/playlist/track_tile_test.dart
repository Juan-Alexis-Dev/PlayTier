import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/playlist/widgets/track_tile.dart';

const song = Track(
  id: 't1',
  uri: 'spotify:track:t1',
  name: 'Heavy',
  artistIds: ['a1'],
  albumId: 'al1',
  albumName: 'Album',
  duration: Duration(minutes: 4, seconds: 13),
);

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    int? level,
    VoidCallback? onMore,
    VoidCallback? onLongPress,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: song,
            artists: 'The Marías',
            level: level,
            onMore: onMore,
            onLongPress: onLongPress,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the level badge for levels 2–5', (tester) async {
    await pumpTile(tester, level: 3);

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('4:13'), findsOneWidget);
  });

  testWidgets('no badge for level 1 or no level', (tester) async {
    await pumpTile(tester, level: 1);
    expect(find.byIcon(Icons.star), findsNothing);

    await pumpTile(tester);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('the More options button appears only with onMore',
      (tester) async {
    await pumpTile(tester);
    expect(find.byTooltip('More options'), findsNothing);

    var opened = false;
    await pumpTile(tester, onMore: () => opened = true);
    await tester.tap(find.byTooltip('More options'));

    expect(opened, isTrue);
  });

  testWidgets('a long press calls onLongPress', (tester) async {
    var pressed = false;
    await pumpTile(tester, onLongPress: () => pressed = true);

    await tester.longPress(find.text('Heavy'));

    expect(pressed, isTrue);
  });
}
