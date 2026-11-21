import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/app/app.dart';

void main() {
  void setScreenSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('starts on Home with the PlayTier title', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('PlayTier'), findsOneWidget);
    expect(find.text('Home screen'), findsOneWidget);
  });

  testWidgets('uses a bottom bar on narrow screens', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses a navigation rail on wide screens', (tester) async {
    setScreenSize(tester, const Size(1200, 800));
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('switches tabs', (tester) async {
    setScreenSize(tester, const Size(400, 800));
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings screen'), findsOneWidget);
  });
}