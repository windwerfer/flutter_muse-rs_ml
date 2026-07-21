import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/app.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';

/// Holds all connection + UI state for the app.
class AppStateNotifier extends StateNotifier<AppUiState> {
  AppStateNotifier(this._settings)
      : super(AppUiState(
          status: const ConnectionStatus(
            connected: false,
            name: '',
            id: '',
            firmware: '',
          ),
          currentView: _settings.lastView,
          sidebarOpen: false,
          connectWindowOpen: false,
          scanning: false,
          devices: const [],
          batteryLevel: 0,
          scanMessage: null,
          telemetry: const TelemetrySnapshot(
            batteryLevel: 0,
            fuelGaugeVoltage: 0,
            temperature: 0,
          ),
        )) {
    _init();
  }

  final Settings _settings;
  StreamSubscription<MuseEventDto>? _eventSub;
  Timer? _autoconnectTimer;

  Future<void> _init() async {
    // Start the event stream once.
    final stream = subscribeEvents();
    _eventSub = stream.listen(_onEvent);

    // Restore previous connection state from Rust (in case it persisted).
    final status = await getStatus();
    if (status.connected) {
      state = state.copyWith(status: status);
    }

    // Auto-connect to the last device if we know one.
    final lastId = _settings.lastDeviceId;
    if (lastId != null && lastId.isNotEmpty) {
      // Kick off a scan; if the last device shows up, connect to it.
      _tryAutoconnect(lastId);
    } else {
      // No known device -> show the connect window on launch.
      state = state.copyWith(connectWindowOpen: true);
    }
    openConnectWindowAndScan();
  }

  Future<void> _tryAutoconnect(String lastId) async {
    state = state.copyWith(connectWindowOpen: true, scanning: true,
        scanMessage: 'Requesting BLE permissions…');
    try {
      if (!await requestBlePermissions()) {
        state = state.copyWith(scanning: false,
            scanMessage: 'BLE permissions not granted');
        return;
      }
      state = state.copyWith(scanMessage: 'Scanning…');
      final devices = await scan(timeoutSecs: BigInt.from(15));
      final match = devices.where((d) => d.id == lastId).firstOrNull ??
          devices.where((d) => d.name == lastId).firstOrNull;
      if (match != null) {
        connectTo(match);
      } else {
        state = state.copyWith(scanning: false,
            scanMessage: 'Did not find last device (${devices.length} found)');
      }
    } catch (e) {
      state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
    }
  }

  void _onEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Connected():
        state = state.copyWith(
          status: state.status.copyWith(connected: true, name: event.field0),
          connectWindowOpen: false,
          scanning: false,
        );
      case MuseEventDto_Disconnected():
        state = state.copyWith(
          status: const ConnectionStatus(
            connected: false,
            name: '',
            id: '',
            firmware: '',
          ),
          batteryLevel: 0,
          telemetry: const TelemetrySnapshot(
            batteryLevel: 0,
            fuelGaugeVoltage: 0,
            temperature: 0,
          ),
          connectWindowOpen: true,
        );
        _settings.setLastDeviceId('');
      case MuseEventDto_Telemetry():
        state = state.copyWith(
          telemetry: event.field0,
          batteryLevel: event.field0.batteryLevel,
        );
      default:
        break;
    }
  }

  Future<void> connectTo(DeviceInfo device) async {
    state = state.copyWith(connectWindowOpen: false, scanning: true);
    try {
      final status = await connect(deviceId: device.id);
      await _settings.setLastDeviceId(device.id);
      state = state.copyWith(status: status, scanning: false);
    } catch (e) {
      state = state.copyWith(scanning: false, connectWindowOpen: true);
    }
  }

  Future<void> disconnectDevice() async {
    await disconnect();
    await _settings.setLastDeviceId('');
  }

  Future<void> openConnectWindowAndScan() async {
    state = state.copyWith(connectWindowOpen: true, scanning: true,
        scanMessage: 'Requesting BLE permissions…');
    try {
      if (!await requestBlePermissions()) {
        state = state.copyWith(scanning: false,
            scanMessage: 'BLE permissions not granted');
        return;
      }
      state = state.copyWith(scanMessage: 'Scanning…');
      final devices = await scan(timeoutSecs: BigInt.from(15));
      state = state.copyWith(devices: devices, scanning: false,
          scanMessage: 'Found ${devices.length} device(s)');
    } catch (e) {
      state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
    }
  }

  void toggleSidebar() =>
      state = state.copyWith(sidebarOpen: !state.sidebarOpen);

  void setSidebar(bool open) => state = state.copyWith(sidebarOpen: open);

  void setCurrentView(AppView view) {
    state = state.copyWith(currentView: view);
    _settings.setLastView(view);
  }

  void toggleConnectWindow() =>
      state = state.copyWith(connectWindowOpen: !state.connectWindowOpen);

  @override
  void dispose() {
    _eventSub?.cancel();
    _autoconnectTimer?.cancel();
    super.dispose();
  }
}

/// Immutable UI state snapshot.
class AppUiState {
  const AppUiState({
    required this.status,
    required this.currentView,
    required this.sidebarOpen,
    required this.connectWindowOpen,
    required this.scanning,
    required this.devices,
    required this.batteryLevel,
    required this.telemetry,
    this.scanMessage,
  });

  final ConnectionStatus status;
  final AppView currentView;
  final bool sidebarOpen;
  final bool connectWindowOpen;
  final bool scanning;
  final List<DeviceInfo> devices;
  final double batteryLevel;
  final TelemetrySnapshot telemetry;
  final String? scanMessage;

  AppUiState copyWith({
    ConnectionStatus? status,
    AppView? currentView,
    bool? sidebarOpen,
    bool? connectWindowOpen,
    bool? scanning,
    List<DeviceInfo>? devices,
    double? batteryLevel,
    TelemetrySnapshot? telemetry,
    String? scanMessage,
  }) =>
      AppUiState(
        status: status ?? this.status,
        currentView: currentView ?? this.currentView,
        sidebarOpen: sidebarOpen ?? this.sidebarOpen,
        connectWindowOpen: connectWindowOpen ?? this.connectWindowOpen,
        scanning: scanning ?? this.scanning,
        devices: devices ?? this.devices,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        telemetry: telemetry ?? this.telemetry,
        scanMessage: scanMessage ?? this.scanMessage,
      );
}

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppUiState>((ref) {
  throw UnimplementedError('Initialize with settings before use');
});
