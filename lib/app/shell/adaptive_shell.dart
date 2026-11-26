import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/mini_player.dart';

/// Hosts the 5 tabs: bottom bar on narrow screens, navigation rail on wide
/// ones, plus the [MiniPlayer] (above the bar on phones, along the bottom
/// on desktop).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Width from which the navigation rail is used (Material "medium").
  static const _railBreakpoint = 600.0;

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home, label: 'Home'),
    (icon: Icons.search_outlined, selected: Icons.search, label: 'Search'),
    (icon: Icons.category_outlined, selected: Icons.category, label: 'Genres'),
    (icon: Icons.person_outline, selected: Icons.person, label: 'Artists'),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings,
      label: 'Settings'
    ),
  ];

  void _onSelect(int index) {
    // Tapping the current tab again goes back to its first page.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final useRail = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final index = navigationShell.currentIndex;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
        bottomNavigationBar: const MiniPlayer(),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _onSelect,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}