import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';

/// A dropdown panel shown beneath the status bar that lists discovered Muse
/// devices. Selecting one connects to it.
class ConnectWindow extends ConsumerWidget {
  const ConnectWindow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.watch(appStateProvider.notifier);

    return Material(
      elevation: 8,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Connect to a Muse device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (!state.scanning)
                  TextButton.icon(
                    onPressed: notifier.openConnectWindowAndScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Rescan'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.scanning)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Scanning for devices…'),
                ],
              )
            else if (state.devices.isEmpty)
              const Text('No Muse devices found. Make sure the headset is on.')
            else
              ...state.devices.map(
                (d) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name),
                  subtitle: Text(d.id),
                  onTap: () => notifier.connectTo(d),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
