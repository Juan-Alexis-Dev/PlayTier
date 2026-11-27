import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/app/router.dart';
import 'package:playtier/data/repositories/levels_repository.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/features/player/player_view_model.dart';
import 'package:provider/provider.dart';

class MockPlayback extends Mock implements PlaybackRepository {}

class MockLevels extends Mock implements LevelsRepository {}

class MockLibrary extends Mock implements LibraryRepository {}

void main() {
  // Tests the shell only: no login redirect, and only the PlayerViewModel
  // the mini-player needs (logged out, so nothing plays and it is hidden).
  // Starts on Settings because Home needs repositories (HomeViewModel).
  Future<void> pumpShell(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final router = createRouter(initialLocation: AppRoutes.settings);
    addTearDown(router.dispose);
    final loggedIn = ValueNotifier(false);
    addTearDown(loggedIn.dispose);
    final player = PlayerViewModel(
      playback: MockPlayback(),
      levels: MockLevels(),
      library: MockLibrary(),
      loggedIn: loggedIn,
    )..init();
    addTearDown(player.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: player,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the initial location', (tester) async {
    await pumpShell(tester);

    expect(find.text('Settings screen'), findsOneWidget);
  });

  testWidgets('uses a bottom bar on narrow screens', (tester) async {
    await pumpShell(tester, size: const Size(400, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses a navigation rail on wide screens', (tester) async {
    await pumpShell(tester, size: const Size(1200, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('switches tabs', (tester) async {
    await pumpShell(tester, size: const Size(400, 800));

    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();

    // Hint of the Browse search bar.
    expect(find.text('Search genres'), findsOneWidget);
  });
}