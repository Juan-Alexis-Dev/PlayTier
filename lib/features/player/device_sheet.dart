import 'package:material_ui/material_ui.dart';

import '../../domain/models/playback_device.dart';
import 'mini_player.dart';
import 'player_view_model.dart';

/// Bottom sheet to choose where Spotify plays (FR-11.2), e.g. the PC
/// while the app runs on the phone. Only devices with Spotify open appear.
class DeviceSheet extends StatefulWidget {
  const DeviceSheet({super.key, required this.vm});

  final PlayerViewModel vm;

  static Future<void> show(BuildContext context, PlayerViewModel vm) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => DeviceSheet(vm: vm),
    );
  }

  @override
  State<DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<DeviceSheet> {
  late Future<({List<PlaybackDevice> devices, String? error})> _load =
      widget.vm.loadDevices();

  void _reload() {
    // setState must not return the Future, so the body is a block.
    setState(() {
      _load = widget.vm.loadDevices();
    });
  }

  bool _switching = false;

  /// Closes only this sheet, and only if it is still open.
  Future<void> _select(PlaybackDevice device) async {
    if (_switching) return;
    setState(() => _switching = true);
    await runPlayerCommand(context, () => widget.vm.transferTo(device));
    if (!mounted) return;
    setState(() => _switching = false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Play on', style: text.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            FutureBuilder(
              future: _load,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final error = data.error;
                if (error != null || data.devices.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      error ??
                          'No devices found. Open Spotify on the device '
                              'you want to use and refresh.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final device in data.devices)
                      _DeviceTile(
                        device: device,
                        onTap: device.isActive || _switching
                            ? null
                            : () => _select(device),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final PlaybackDevice device;
  final VoidCallback? onTap;

  static IconData _icon(String type) => switch (type) {
        'Computer' => Icons.computer,
        'Smartphone' => Icons.smartphone,
        'Tablet' => Icons.tablet,
        'Speaker' => Icons.speaker,
        'TV' => Icons.tv,
        _ => Icons.devices_other,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = device.isActive;

    return ListTile(
      leading: Icon(_icon(device.type), color: active ? colors.primary : null),
      title: Text(
        device.name,
        style: active ? TextStyle(color: colors.primary) : null,
      ),
      subtitle: Text(active ? 'Playing now' : device.type),
      trailing: active ? Icon(Icons.check, color: colors.primary) : null,
      onTap: onTap,
    );
  }
}