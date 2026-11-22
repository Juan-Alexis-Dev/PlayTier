import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../features/settings/settings_view_model.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget. Expects the providers from `dependencies.dart` above it.
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // Created once so rebuilds (e.g. palette changes) keep navigation state.
  late final GoRouter _router = createRouter(
    auth: context.read<AuthRepository>(),
    settings: context.read<SettingsViewModel>(),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<SettingsViewModel>().palette;

    return MaterialApp.router(
      title: 'PlayTier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(palette),
      routerConfig: _router,
    );
  }
}