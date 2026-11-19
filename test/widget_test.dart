import 'package:flutter_test/flutter_test.dart';

import 'package:playtier/app/app.dart';

void main() {
  testWidgets('App starts and shows its name', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('PlayTier'), findsOneWidget);
  });
}
