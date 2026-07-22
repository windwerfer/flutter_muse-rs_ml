import 'dart:ui';
import 'package:muse_ml/src/rust/api/muse.dart';

class ChartSample {
  final double t;
  final double v;
  ChartSample(this.t, this.v);
}

class SeriesSlice {
  final String name;
  final Color color;
  final String unit;
  final List<ChartSample> samples;
  final bool visible;
  SeriesSlice({
    required this.name,
    required this.color,
    required this.unit,
    required this.samples,
    this.visible = true,
  });
}

class EegDataBuffer {
  EegDataBuffer({this.maxDurationSecs = 7200});

  static const double sampleRate = 256.0;
  static const List<String> channelNames = ['TP9', 'AF7', 'AF8', 'TP10'];
  final int maxDurationSecs;

  final Map<int, List<ChartSample>> _channels = {};

  void append(EegDto dto) {
    final list = _channels.putIfAbsent(dto.electrode, () => []);
    final dt = 1.0 / sampleRate;
    for (int i = 0; i < dto.samples.length; i++) {
      list.add(ChartSample(dto.timestamp + i * dt, dto.samples[i]));
    }
    _trim(list);
  }

  void _trim(List<ChartSample> list) {
    final maxSamples = (maxDurationSecs * sampleRate).toInt();
    if (list.length > maxSamples) {
      list.removeRange(0, list.length - maxSamples);
    }
  }

  List<int> get channels => _channels.keys.toList()..sort();

  List<ChartSample> getRange(int channel, double startT, double endT) {
    final list = _channels[channel];
    if (list == null || list.isEmpty) return [];
    final lo = _lowerBound(list, startT);
    final hi = _upperBound(list, endT);
    if (lo >= hi) return [];
    return list.sublist(lo, hi);
  }

  List<SeriesSlice> slices({
    required double startT,
    required double endT,
    required Set<int> hiddenChannels,
    required List<Color> channelColors,
  }) {
    final result = <SeriesSlice>[];
    for (final ch in channels) {
      final hidden = hiddenChannels.contains(ch);
      result.add(SeriesSlice(
        name: channelNames[ch % channelNames.length],
        color: channelColors[ch % channelColors.length],
        unit: 'µV',
        samples: hidden ? const [] : getRange(ch, startT, endT),
        visible: !hidden,
      ));
    }
    return result;
  }

  bool hasDataFor(int channel) =>
      _channels[channel]?.isNotEmpty ?? false;

  double get latestTimestamp {
    double latest = 0;
    for (final list in _channels.values) {
      if (list.isNotEmpty && list.last.t > latest) latest = list.last.t;
    }
    return latest;
  }

  double get oldestTimestamp {
    double oldest = double.infinity;
    for (final list in _channels.values) {
      if (list.isNotEmpty && list.first.t < oldest) oldest = list.first.t;
    }
    return oldest == double.infinity ? 0 : oldest;
  }

  void clear() => _channels.clear();
}

int _lowerBound(List<ChartSample> list, double t) {
  int lo = 0, hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].t < t) { lo = mid + 1; } else { hi = mid; }
  }
  return lo;
}

int _upperBound(List<ChartSample> list, double t) {
  int lo = 0, hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].t <= t) { lo = mid + 1; } else { hi = mid; }
  }
  return lo;
}
