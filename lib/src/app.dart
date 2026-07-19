import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/connect_window.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/status_bar.dart';
import 'package:muse_ml/src/views/bands.dart';
import 'package:muse_ml/src/views/raw_eeg.dart';
import 'package:muse_ml/src/views/terminal.dart';
import 'package:permission_handler/permission_handler.dart';

/// The main app shell: status bar on top, a collapsible sidebar with the three
/// views, and the connect window overlay.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);

    final Widget body;
    switch (state.currentView) {
      case AppView.bands:
        body = const BandsView();
      case AppView.rawEeg:
        body = const RawEegView();
      case AppView.terminal:
        body = const TerminalView();
    }

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    if (state.sidebarOpen)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Column(
                            children: [
                              _SideBarItem(
                                label: 'Bands',
                                selected: state.currentView == AppView.bands,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.bands),
                              ),
                              _SideBarItem(
                                label: 'Raw EEG',
                                selected: state.currentView == AppView.rawEeg,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.rawEeg),
                              ),
                              _SideBarItem(
                                label: 'Terminal',
                                selected:
                                    state.currentView == AppView.terminal,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.terminal),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(child: body),
                  ],
                ),
                if (state.connectWindowOpen)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: const ConnectWindow(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideBarItem extends StatelessWidget {
  const _SideBarItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Entry point. Loads settings, initializes the Rust library, requests BLE
/// permissions, then runs the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await _requestBlePermissions();
  final settings = await Settings.load();
  runApp(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => AppStateNotifier(settings)),
      ],
      child: MaterialApp(
        title: 'Muse ML',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const AppShell(),
      ),
    ),
  );
}

/// Requests the Bluetooth LE permissions needed for scanning/connecting.
///
/// On Android 12+ this is `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`. On Android
/// 11 and below, BLE scanning additionally requires location permission, so we
/// request that too. If a permission is permanently denied we open the app
/// settings so the user can grant it manually.
Future<void> _requestBlePermissions() async {
  // permission_handler has no Linux/desktop implementation, so only request on
  // Android (where BLE requires runtime permissions).
  if (!Platform.isAndroid) return;

  final permissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  // Request everything that isn't already granted.
  final statuses = await permissions.request();

  final permanentlyDenied = statuses.values.any(
    (status) => status.isPermanentlyDenied,
  );
  if (permanentlyDenied) {
    await openAppSettings();
  }
}
