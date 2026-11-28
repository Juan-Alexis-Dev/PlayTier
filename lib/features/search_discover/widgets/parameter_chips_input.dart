import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/discover_mode.dart';
import '../../../domain/models/discover_parameter.dart';
import '../discover_view_model.dart';

/// "Own parameters" (FR-10.5): a text field with autocomplete over the
/// library's artists and genres, the chosen values as chips and a button
/// that runs Discover with them.
///
/// Needs a [DiscoverViewModel] above it.
class ParameterChipsInput extends StatelessWidget {
  const ParameterChipsInput({super.key, required this.onRun});

  /// Runs [DiscoverMode.custom] (handled by the Discover section).
  final VoidCallback onRun;

  static IconData iconOf(DiscoverParameter p) =>
      p.isArtist ? Icons.person : Icons.category;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiscoverViewModel>();
    final theme = Theme.of(context);
    final running = vm.running == DiscoverMode.custom;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DiscoverMode.custom.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              DiscoverMode.custom.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _ParameterField(enabled: vm.canAddParameter && !vm.busy),
            if (vm.selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in vm.selected)
                    InputChip(
                      avatar: Icon(iconOf(p), size: 18),
                      label: Text(p.label),
                      deleteButtonTooltipMessage: 'Remove ${p.label}',
                      onDeleted: vm.busy ? null : () => vm.removeParameter(p),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: vm.canRun(DiscoverMode.custom) ? onRun : null,
                icon: running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('Discover'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text field with the suggestion list.
class _ParameterField extends StatefulWidget {
  const _ParameterField({required this.enabled});

  final bool enabled;

  @override
  State<_ParameterField> createState() => _ParameterFieldState();
}

class _ParameterFieldState extends State<_ParameterField> {
  static const _maxListHeight = 280.0;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<DiscoverViewModel>();
    final enabled = widget.enabled;

    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<DiscoverParameter>(
        textEditingController: _controller,
        focusNode: _focusNode,
        displayStringForOption: (p) => p.label,
        optionsBuilder: (value) => vm.suggestions(value.text),
        onSelected: (p) {
          vm.addParameter(p);
          // The field shows the chosen label; clear it for the next one.
          _controller.clear();
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.add),
              hintText: enabled
                  ? 'Add an artist or genre from your library'
                  : 'Up to ${DiscoverViewModel.maxParameters} artists or '
                      'genres',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => onSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final list = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _maxListHeight,
                  maxWidth: constraints.maxWidth,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final p = list[index];
                    return ListTile(
                      leading: Icon(ParameterChipsInput.iconOf(p)),
                      title: Text(p.label),
                      subtitle: Text(p.isArtist ? 'Artist' : 'Genre'),
                      onTap: () => onSelected(p),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}