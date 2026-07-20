use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;
use flutter_rust_bridge::frb_generated::StreamSink;
use log::{Level, LevelFilter, Metadata, Record};

/// Forwards `log` records (from muse-rs, btleplug, and our own code) into a
/// Dart `StreamSink<String>` so they can be displayed in the app's Terminal
/// view. Replaces the default no-op logger.
struct DartLogForwarder {
    sink: Mutex<Option<StreamSink<String>>>,
}

static FORWARDER: OnceLock<DartLogForwarder> = OnceLock::new();

fn forwarder() -> &'static DartLogForwarder {
    FORWARDER.get_or_init(|| DartLogForwarder {
        sink: Mutex::new(None),
    })
}

impl log::Log for DartLogForwarder {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= Level::Info
    }

    fn log(&self, record: &Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let line = format!(
            "[{}] {}: {}",
            record.level(),
            record.target(),
            record.args()
        );
        if let Some(sink) = forwarder().sink.lock().unwrap().as_ref() {
            let _ = sink.add(line);
        }
    }

    fn flush(&self) {}
}

/// Install the Dart log forwarder as the global logger (once) and, if a sink is
/// provided, start streaming logs into it. Safe to call multiple times; later
/// calls just (re)attach the sink.
#[frb(init)]
pub fn init_logging(sink: Option<StreamSink<String>>) {
    let _ = log::set_boxed_logger(Box::new(DartLogForwarder))
        .map(|()| log::set_max_level(LevelFilter::Info));
    if let Some(sink) = sink {
        *forwarder().sink.lock().unwrap() = Some(sink);
    }
    log::info!("logging initialised");
}

/// (Re)attach or detach the Dart-side log sink at runtime.
#[frb(init)]
pub fn set_log_sink(sink: Option<StreamSink<String>>) {
    *forwarder().sink.lock().unwrap() = sink;
}

