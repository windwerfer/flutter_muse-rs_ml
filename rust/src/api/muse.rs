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
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Debug)
                .with_tag("muse_ml"),
        );
    }
    #[cfg(not(target_os = "android"))]
    {
        env_logger::Builder::from_env(
            env_logger::Env::default().default_filter_or("info"),
        )
        .init();
    }
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
/// found. Results are **merged** into the existing device cache so that the UI
/// can call `scan` repeatedly in short chunks without losing previously
/// discovered peripherals (which `connect` needs via `MuseDevice`).
pub async fn scan(timeout_secs: Option<u64>) -> anyhow::Result<Vec<DeviceInfo>> {
    let timeout = timeout_secs.unwrap_or(15);
    let client = MuseClient::new(MuseClientConfig {
        scan_timeout_secs: timeout,
        ..Default::default()
    });

    let devices = client.scan_all().await.map_err(|e| {
        log::error!("[muse] scan_all failed: {e:?}");
        e
    })?;

    let infos: Vec<DeviceInfo> = devices
        .iter()
        .map(|d| DeviceInfo {
            name: d.name.clone(),
            id: d.id.clone(),
        })
        .collect();

    {
        let mut guard = state().inner.lock().unwrap();
        for d in devices {
            guard.devices.insert(d.id.clone(), d);
        }
    }

    Ok(infos)
}

/// Connect to a previously discovered device by its BLE id and begin streaming.
/// Returns the connection status on success.
///
/// The entire operation is guarded by an overall timeout so the caller never
/// waits more than ≈18 s.  Inside, each BLE step already has its own shorter
/// timeout (10 s connect, 15 s discover services, 8 s startup commands).
pub async fn connect(device_id: String) -> anyhow::Result<ConnectionStatus> {
    // Tear down any existing connection first so the BLE link is released
    // before we attempt a new one.  Without this the device may still think
    // it is connected and reject (or ignore) the new connection attempt.
    {
        let old = state().inner.lock().unwrap().active.take();
        if let Some(old) = old {
            let _ = old.handle.disconnect().await;
        }
    }

    let device = {
        let guard = state().inner.lock().unwrap();
        guard.devices.get(&device_id).cloned().ok_or_else(|| {
            anyhow::anyhow!("Device {device_id} not found; scan first")
        })?
    };

    let name = device.name.clone();
    let client = MuseClient::new(MuseClientConfig::default());

    tokio::time::timeout(std::time::Duration::from_secs(18), async {
        let (rx, handle) = client.connect_to(device).await?;
        let firmware = if handle.is_athena {
            "Athena"
        } else {
            "Classic"
        }
        .to_string();

        // Start streaming — best-effort with its own timeout.  The BLE link
        // from connect_to() is already established, so a timeout here still
        // leaves a usable (but silent) connection.
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(8),
            handle.start(false, false),
        )
        .await;

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
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
    })
    .await
    .map_err(|_| anyhow::anyhow!("connect timed out after 18 s"))?
}

/// Disconnect from the active device, if any.
///
/// Takes the active connection but does NOT drop `guard.events`, so the event
/// receiver stays alive.  The disconnect watcher inside muse-rs will fire
/// `MuseEvent::Disconnected` through the channel, the event forwarder will
/// deliver it to Dart, and the forwarder loop will clean up `guard.events`
/// (and set `forwarder_running = false`) when the channel ends naturally.
pub async fn disconnect() -> anyhow::Result<()> {
    let conn = {
        let mut guard = state().inner.lock().unwrap();
        guard.active.take()
    };
    if let Some(conn) = conn {
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
    let epoch = {
        let mut guard = state().inner.lock().unwrap();
        if guard.forwarder_running {
            return;
        }
        guard.forwarder_running = true;
        guard.connection_epoch
    };
    tokio::spawn(async move {
        let mut counts = [0u64; 8]; // eeg, ppg, telemetry, accel, gyro, control, connected, other
        let mut last_print = tokio::time::Instant::now();
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
                match &ev {
                    MuseEvent::Eeg(_) => counts[0] += 1,
                    MuseEvent::Ppg(_) => counts[1] += 1,
                    MuseEvent::Telemetry(_) => counts[2] += 1,
                    MuseEvent::Accelerometer(_) => counts[3] += 1,
                    MuseEvent::Gyroscope(_) => counts[4] += 1,
                    MuseEvent::Control(_) => counts[5] += 1,
                    MuseEvent::Connected(_) => counts[6] += 1,
                    _ => counts[7] += 1,
                }
                if last_print.elapsed() >= std::time::Duration::from_secs(1) {
                    log::info!(
                        "[muse] pkt/s: eeg={} ppg={} telem={} accel={} gyro={} ctrl={} conn={} other={}",
                        counts[0], counts[1], counts[2], counts[3],
                        counts[4], counts[5], counts[6], counts[7],
                    );
                    counts = [0; 8];
                    last_print = tokio::time::Instant::now();
                }
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
            // Receiver ended (device disconnected).  Only clear active state
            // if no newer connection has been established since this forwarder
            // was spawned — otherwise we would tear down the new connection's
            // handle without calling disconnect(), leaving a stale BLE link.
            {
                let mut guard = state().inner.lock().unwrap();
                if guard.connection_epoch == epoch {
                    guard.active = None;
                    guard.events = None;
                }
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
