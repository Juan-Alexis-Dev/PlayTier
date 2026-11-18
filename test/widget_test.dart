import 'package:flutter_test/flutter_test.dart';

import 'package:playtier/main.dart';

void main() {
  testWidgets('Spike app shows the login button', (tester) async {
    await tester.pumpWidget(const SpikeApp());

    expect(find.text('Log in with Spotify'), findsOneWidget);
  });
}