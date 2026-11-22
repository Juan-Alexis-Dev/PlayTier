import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/app/router.dart';

void main() {
  // Tests the shell only: no providers, no login redirect. Starts on
  // Settings because Home needs repositories (HomeViewModel).
  Future<void> pumpShell(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final router = createRouter(initialLocation: AppRoutes.settings);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
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

    expect(find.text('Genres screen'), findsOneWidget);
  });
}