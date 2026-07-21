use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;
use muse_rs::prelude::*;

use crate::connection::{state, ActiveConnection};

// ── DTOs (serializable across the bridge) ──────────────────────────────────────

/// A Muse device discovered during a scan.
#[frb(dart_metadata = ("freezed",))]
pub struct DeviceInfo {
    pub name: String,
    pub id: String,
}

/// Connection / link status reported to the UI.
#[frb(dart_metadata = ("freezed",))]
pub struct ConnectionStatus {
    pub connected: bool,
    pub name: String,
    pub id: String,
    pub firmware: String,
}

impl Default for ConnectionStatus {
    fn default() -> Self {
        Self {
            connected: false,
            name: String::new(),
            id: String::new(),
            firmware: String::new(),
        }
    }
}

/// Telemetry snapshot (battery etc.) surfaced in the status bar.
#[frb(dart_metadata = ("freezed",))]
pub struct TelemetrySnapshot {
    pub battery_level: f32,
    pub fuel_gauge_voltage: f32,
    pub temperature: u16,
}

impl Default for TelemetrySnapshot {
    fn default() -> Self {
        Self {
            battery_level: 0.0,
            fuel_gauge_voltage: 0.0,
            temperature: 0,
        }
    }
}

/// An EEG sample batch for a single electrode channel.
#[frb(dart_metadata = ("freezed",))]
pub struct EegDto {
    pub index: u16,
    pub electrode: i32,
    pub timestamp: f64,
    pub samples: Vec<f64>,
}

/// A PPG (optical) reading for one channel.
#[frb(dart_metadata = ("freezed",))]
pub struct PpgDto {
    pub index: u16,
    pub channel: i32,
    pub timestamp: f64,
    pub samples: Vec<f64>,
}

/// A 3-axis inertial measurement.
#[frb(dart_metadata = ("freezed",))]
pub struct XyzDto {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// A batch of inertial measurements.
#[frb(dart_metadata = ("freezed",))]
pub struct ImuDto {
    pub sequence_id: u16,
    pub samples: Vec<XyzDto>,
}

/// A parsed control/status JSON response from the headset.
#[frb(dart_metadata = ("freezed",))]
pub struct ControlDto {
    pub raw: String,
    pub fields: std::collections::HashMap<String, String>,
}

/// All events streamed from the headset to the UI.
#[frb(dart_metadata = ("freezed",))]
pub enum MuseEventDto {
    Connected(String),
    Disconnected,
    Eeg(EegDto),
    Ppg(PpgDto),
    Telemetry(TelemetrySnapshot),
    Accelerometer(ImuDto),
    Gyroscope(ImuDto),
    Control(ControlDto),
}

// ── Bridge API ─────────────────────────────────────────────────────────────────

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Called from Kotlin `MainActivity.onCreate` with the JNI environment so that
/// btleplug's global Android adapter can be registered. On Android, btleplug
/// requires `btleplug::platform::init(&env)` to be called from a JNI context
/// before any BLE scan/connect; otherwise it panics with
/// "Droidplug has not been initialized".
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn Java_com_example_muse_1ml_MainActivity_museAndroidInit(
    env: *mut jni::sys::JNIEnv,
) {
    let env = unsafe { jni::JNIEnv::from_raw(env) };
    if let Ok(env) = env {
        if let Err(e) = btleplug::platform::init(&env) {
            log::error!("[muse] btleplug init failed: {e:?}");
        } else {
            log::info!("[muse] btleplug initialized");
        }
    }
}

/// Scan for nearby Muse devices for `timeout_secs` seconds and return what was
/// found. Results are cached on the Rust side so `connect` can resolve the id
/// back to a live peripheral.
pub async fn scan(timeout_secs: Option<u64>) -> anyhow::Result<Vec<DeviceInfo>> {
    let timeout = timeout_secs.unwrap_or(15);
    let client = MuseClient::new(MuseClientConfig {
        scan_timeout_secs: timeout,
        ..Default::default()
    });

    let devices = client.scan_all().await?;

    let mut map = std::collections::HashMap::new();
    let infos: Vec<DeviceInfo> = devices
        .iter()
        .map(|d| {
            map.insert(d.id.clone(), d.clone());
            DeviceInfo {
                name: d.name.clone(),
                id: d.id.clone(),
            }
        })
        .collect();

    {
        let mut guard = state().inner.lock().unwrap();
        guard.devices = map;
    }

    Ok(infos)
}

/// Connect to a previously discovered device by its BLE id and begin streaming.
/// Returns the connection status on success.
pub async fn connect(device_id: String) -> anyhow::Result<ConnectionStatus> {
    let device = {
        let guard = state().inner.lock().unwrap();
        guard
            .devices
            .get(&device_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Device {device_id} not found; scan first"))?
    };

    let name = device.name.clone();
    let client = MuseClient::new(MuseClientConfig::default());

    let (rx, handle) = client.connect_to(device).await?;
    let firmware = if handle.is_athena {
        "Athena"
    } else {
        "Classic"
    }
    .to_string();

    // Start streaming. Errors here are non-fatal for the connection itself.
    let _ = handle.start(false, false).await;

    {
        let mut guard = state().inner.lock().unwrap();
        guard.active = Some(ActiveConnection {
            handle,
            name: name.clone(),
            id: device_id.clone(),
            firmware: firmware.clone(),
        });
        guard.events = Some(rx);
    }

    spawn_event_forwarder();

    Ok(ConnectionStatus {
        connected: true,
        name,
        id: device_id,
        firmware,
    })
}

/// Disconnect from the active device, if any.
pub async fn disconnect() -> anyhow::Result<()> {
    let handle = {
        let mut guard = state().inner.lock().unwrap();
        guard.events = None;
        guard.active.take()
    };
    if let Some(conn) = handle {
        let _ = conn.handle.disconnect().await;
    }
    Ok(())
}

/// Current connection status (used on app launch to restore UI state).
pub fn get_status() -> ConnectionStatus {
    let guard = state().inner.lock().unwrap();
    match &guard.active {
        Some(conn) => ConnectionStatus {
            connected: true,
            name: conn.name.clone(),
            id: conn.id.clone(),
            firmware: conn.firmware.clone(),
        },
        None => ConnectionStatus::default(),
    }
}

/// Returns `true` if a connection is currently active. The Rust side clears
/// this as soon as muse-rs reports a disconnect, so it tracks the real link
/// state closely enough for the UI.
pub fn is_connected() -> bool {
    state().inner.lock().unwrap().active.is_some()
}

/// Subscribe to the live event stream from the connected headset.
///
/// Call this once at startup. It returns a Dart `Stream<MuseEventDto>` that
/// receives every event emitted by muse-rs for the active (or future)
/// connection. The Rust side forwards events into the provided `StreamSink`.
pub fn subscribe_events(sink: StreamSink<MuseEventDto>) {
    let mut guard = state().inner.lock().unwrap();
    guard.sink = Some(sink);
}

fn spawn_event_forwarder() {
    {
        let mut guard = state().inner.lock().unwrap();
        if guard.forwarder_running {
            return;
        }
        guard.forwarder_running = true;
    }
    tokio::spawn(async {
        loop {
            let rx = {
                let mut guard = state().inner.lock().unwrap();
                guard.events.take()
            };
            let Some(mut rx) = rx else {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                continue;
            };
            while let Some(ev) = rx.recv().await {
                let dto = map_event(ev);
                let should_stop = {
                    let mut guard = state().inner.lock().unwrap();
                    match guard.sink.as_ref() {
                        Some(sink) => {
                            if sink.add(dto).is_err() {
                                guard.sink = None;
                                true
                            } else {
                                false
                            }
                        }
                        None => false,
                    }
                };
                if should_stop {
                    break;
                }
            }
            // Receiver ended (device disconnected). Clear active state.
            {
                let mut guard = state().inner.lock().unwrap();
                guard.active = None;
                guard.events = None;
                guard.forwarder_running = false;
            }
        }
    });
}

fn map_event(ev: MuseEvent) -> MuseEventDto {
    match ev {
        MuseEvent::Connected(name) => MuseEventDto::Connected(name),
        MuseEvent::Disconnected => MuseEventDto::Disconnected,
        MuseEvent::Eeg(r) => MuseEventDto::Eeg(EegDto {
            index: r.index,
            electrode: r.electrode as i32,
            timestamp: r.timestamp,
            samples: r.samples,
        }),
        MuseEvent::Ppg(r) => MuseEventDto::Ppg(PpgDto {
            index: r.index,
            channel: r.ppg_channel as i32,
            timestamp: r.timestamp,
            samples: r.samples.into_iter().map(|s| s as f64).collect(),
        }),
        MuseEvent::Telemetry(t) => MuseEventDto::Telemetry(TelemetrySnapshot {
            battery_level: t.battery_level,
            fuel_gauge_voltage: t.fuel_gauge_voltage,
            temperature: t.temperature,
        }),
        MuseEvent::Accelerometer(imu) => MuseEventDto::Accelerometer(map_imu(imu)),
        MuseEvent::Gyroscope(imu) => MuseEventDto::Gyroscope(map_imu(imu)),
        MuseEvent::Control(c) => MuseEventDto::Control(ControlDto {
            raw: c.raw,
            fields: c
                .fields
                .into_iter()
                .map(|(k, v)| (k, v.to_string()))
                .collect(),
        }),
    }
}

fn map_imu(imu: ImuData) -> ImuDto {
    ImuDto {
        sequence_id: imu.sequence_id,
        samples: imu
            .samples
            .iter()
            .map(|s| XyzDto {
                x: s.x,
                y: s.y,
                z: s.z,
            })
            .collect(),
    }
}
