import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment();
  if (!config.isValid) {
    debugPrint('Missing config keys: ${config.missingKeys.join(', ')}. '
        'Run with --dart-define-from-file=config.json');
  }

  final providers = await buildProviders(config);
  runApp(MultiProvider(providers: providers, child: const App()));
}