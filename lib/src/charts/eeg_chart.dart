import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/eeg_data_buffer.dart';

const _channelColors = [
  Color(0xFF4FC3F7),
  Color(0xFFFF7043),
  Color(0xFF66BB6A),
  Color(0xFFAB47BC),
  Color(0xFFFFA726),
  Color(0xFF26C6DA),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
];

class EegChartWidget extends StatefulWidget {
  final EegDataBuffer buffer;
  const EegChartWidget({super.key, required this.buffer});

  @override
  State<EegChartWidget> createState() => _EegChartWidgetState();
}

class _EegChartWidgetState extends State<EegChartWidget> {
  double _timeWindowSecs = 10;
  double _timeOffsetSecs = 0;
  final Set<int> _hiddenChannels = {};

  double get _maxTimeOffsetSecs {
    final oldest = widget.buffer.oldestTimestamp;
    final latest = widget.buffer.latestTimestamp;
    if (latest <= 0) return 0;
    return (latest - oldest).clamp(0, double.infinity);
  }

  void _ensureOffsetInBounds() {
    final maxOffset = _maxTimeOffsetSecs;
    if (_timeOffsetSecs > maxOffset) _timeOffsetSecs = maxOffset;
    _timeWindowSecs = _timeWindowSecs.clamp(1.0, 120.0);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      final prevWindow = _timeWindowSecs;
      _timeWindowSecs = (prevWindow / d.scale).clamp(1.0, 120.0);
      final effectiveDelta = d.focalPointDelta.dx * _timeWindowSecs /
          context.size!.width;
      _timeOffsetSecs = (_timeOffsetSecs + effectiveDelta)
          .clamp(0.0, _maxTimeOffsetSecs);
    });
  }

  static const _legendPad = 12.0;
  static const _legendItemHeight = 28.0;

  void _onTapUp(TapUpDetails d) {
    final size = context.size!;
    final slices = _currentSlices;
    if (slices.isEmpty) return;
    final legendRect = _legendRect(size, slices.length);
    if (!legendRect.contains(d.localPosition)) return;
    final dy = d.localPosition.dy - legendRect.top - _legendPad;
    final index = dy ~/ _legendItemHeight;
    if (index < 0 || index >= slices.length) return;

    final channels = widget.buffer.channels;
    if (index >= channels.length) return;
    final ch = channels[index];
    setState(() {
      if (_hiddenChannels.contains(ch)) {
        _hiddenChannels.remove(ch);
      } else {
        _hiddenChannels.add(ch);
      }
    });
  }

  /// The slices for the currently visible time window.
  List<SeriesSlice> get _currentSlices {
    final latest = widget.buffer.latestTimestamp;
    final visibleEnd = latest - _timeOffsetSecs;
    final visibleStart = visibleEnd - _timeWindowSecs;
    return widget.buffer.slices(
      startT: visibleStart,
      endT: visibleEnd,
      hiddenChannels: _hiddenChannels,
      channelColors: _channelColors,
    );
  }

  Rect _legendRect(Size size, int count) {
    final w = 90.0;
    final h = _legendPad * 2 + count * _legendItemHeight;
    return Rect.fromLTWH(size.width - w - 8, size.height - h - 8, w, h);
  }

  @override
  Widget build(BuildContext context) {
    _ensureOffsetInBounds();
    final latest = widget.buffer.latestTimestamp;
    final visibleEnd = latest - _timeOffsetSecs;
    final visibleStart = visibleEnd - _timeWindowSecs;
    final slices = widget.buffer.slices(
      startT: visibleStart,
      endT: visibleEnd,
      hiddenChannels: _hiddenChannels,
      channelColors: _channelColors,
    );

    return GestureDetector(
      onScaleUpdate: _onScaleUpdate,
      onTapUp: _onTapUp,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _EegChartPainter(
            slices: slices,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
          ),
        ),
      ),
    );
  }
}

class _EegChartPainter extends CustomPainter {
  _EegChartPainter({
    required this.slices,
    required this.visibleStart,
    required this.visibleEnd,
  });

  final List<SeriesSlice> slices;
  final double visibleStart;
  final double visibleEnd;

  late Size _size;
  late Rect _chartRect;
  late double _xScale;
  late double _yMin;
  late double _yMax;
  late double _niceMin;
  late double _niceMax;
  late double _yRange;
  late double _yScale;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    _computeLayout();
    _drawBackground(canvas);
    _drawGrid(canvas);
    for (final slice in slices) {
      _drawSlice(canvas, slice);
    }
    _drawBorder(canvas);
    _drawAxisLabels(canvas);
    _drawLegend(canvas);
  }

  void _computeLayout() {
    final marginL = 60.0, marginR = 100.0;
    final marginT = 24.0, marginB = 32.0;
    _chartRect = Rect.fromLTWH(
      marginL,
      marginT,
      (_size.width - marginL - marginR).clamp(100, double.infinity),
      (_size.height - marginT - marginB).clamp(50, double.infinity),
    );
    _xScale = _chartRect.width / (visibleEnd - visibleStart);

    _yMin = double.infinity;
    _yMax = double.negativeInfinity;
    for (final slice in slices) {
      for (final s in slice.samples) {
        if (s.v < _yMin) _yMin = s.v;
        if (s.v > _yMax) _yMax = s.v;
      }
    }
    if (_yMin.isInfinite || _yMax.isInfinite) {
      _yMin = -100;
      _yMax = 100;
    }
    final range = _yMax - _yMin;
    final padding = range > 0 ? range * 0.1 : 20.0;
    _niceMin = _yMin - padding;
    _niceMax = _yMax + padding;
    _yRange = _niceMax - _niceMin;
    _yScale = _chartRect.height / _yRange;
  }

  void _drawBackground(Canvas canvas) {
    final bg = Offset.zero & _size;
    canvas.drawRect(bg, Paint()..color = const Color(0xFF111218));
  }

  void _drawBorder(Canvas canvas) {
    canvas.drawRect(
      _chartRect,
      Paint()
        ..color = const Color(0xFF2A2D37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E212A)
      ..strokeWidth = 1;

    final yLines = _niceGridValues(
      _niceMin, _niceMax, _chartRect.height, 40,
    );
    for (final v in yLines) {
      final y = _niceMax - v;
      final py = _chartRect.top + y * _yScale;
      canvas.drawLine(
        Offset(_chartRect.left, py),
        Offset(_chartRect.right, py),
        gridPaint,
      );
    }

    final xLines = _niceGridValues(
      visibleStart, visibleEnd, _chartRect.width, 60,
    );
    for (final v in xLines) {
      final relative = v - visibleStart;
      final px = _chartRect.left + relative * _xScale;
      canvas.drawLine(
        Offset(px, _chartRect.top),
        Offset(px, _chartRect.bottom),
        gridPaint,
      );
    }
  }

  List<double> _niceGridValues(double min, double max, double pixelSpan, double minPxGap) {
    final range = max - min;
    if (range <= 0 || pixelSpan <= 0) return [];
    final idealCount = pixelSpan / minPxGap;
    final roughStep = range / idealCount;
    final step = _niceStep(roughStep);
    if (step <= 0) return [];
    final start = (min / step).ceil() * step;
    final result = <double>[];
    for (double v = start; v <= max; v += step) {
      result.add(v);
    }
    return result;
  }

  double _niceStep(double rough) {
    final exp = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final frac = rough / exp;
    return exp * (frac <= 1.5 ? 1 : frac <= 3.5 ? 2 : frac <= 7.5 ? 5 : 10);
  }

  void _drawSlice(Canvas canvas, SeriesSlice slice) {
    if (!slice.visible) return;
    final samples = slice.samples;
    if (samples.length < 2) return;

    final paint = Paint()
      ..color = slice.color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(
      _chartRect.left + (samples[0].t - visibleStart) * _xScale,
      _chartRect.top + (_niceMax - samples[0].v) * _yScale,
    );

    for (int i = 1; i < samples.length; i++) {
      final x = _chartRect.left + (samples[i].t - visibleStart) * _xScale;
      final y = _chartRect.top + (_niceMax - samples[i].v) * _yScale;
      final prevX = _chartRect.left + (samples[i - 1].t - visibleStart) * _xScale;
      final prevY = _chartRect.top + (_niceMax - samples[i - 1].v) * _yScale;

      final cpx1 = prevX + (x - prevX) * 0.5;
      final cpy1 = prevY;
      final cpx2 = prevX + (x - prevX) * 0.5;
      final cpy2 = y;
      path.cubicTo(cpx1, cpy1, cpx2, cpy2, x, y);
    }

    canvas.drawPath(path, paint);
  }

  void _drawAxisLabels(Canvas canvas) {
    final labelStyle = TextStyle(
      color: const Color(0xFF6B7280),
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final yLines = _niceGridValues(_niceMin, _niceMax, _chartRect.height, 40);
    for (final v in yLines) {
      final y = _niceMax - v;
      final py = _chartRect.top + y * _yScale;
      final text = '${v.toStringAsFixed(v.abs() < 10 ? 1 : 0)} µV';
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _chartRect.left - 8);
      tp.paint(canvas, Offset(_chartRect.left - tp.width - 4, py - tp.height / 2));
    }

    final xLines = _niceGridValues(visibleStart, visibleEnd, _chartRect.width, 60);
    for (final v in xLines) {
      final relative = v - visibleStart;
      final px = _chartRect.left + relative * _xScale;
      final text = _formatTime(v);
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(px - tp.width / 2, _chartRect.bottom + 6));
    }
  }

  String _formatTime(double t) {
    if (t <= 0) return '0s';
    if (t < 60) return '${t.toStringAsFixed(1)}s';
    final m = (t / 60).floor();
    final s = (t % 60).toInt();
    return '${m}m${s}s';
  }

  void _drawLegend(Canvas canvas) {
    if (slices.isEmpty) return;

    const pad = _EegChartWidgetState._legendPad;
    const itemH = _EegChartWidgetState._legendItemHeight;
    final count = slices.length;
    final w = 90.0;
    final h = pad * 2 + count * itemH;
    final rect = Rect.fromLTWH(
      _size.width - w - 8, _size.height - h - 8, w, h,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xBB111218),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFF2A2D37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (int i = 0; i < count; i++) {
      final slice = slices[i];
      final y = rect.top + pad + i * itemH;

      canvas.drawCircle(
        Offset(rect.left + 10, y + itemH / 2),
        4,
        Paint()
          ..color = slice.visible ? slice.color : slice.color.withAlpha(60)
          ..style = PaintingStyle.fill,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: slice.name,
          style: TextStyle(
            color: slice.visible ? Colors.white : Colors.white38,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 20, y + itemH / 2 - tp.height / 2));

      if (!slice.visible) {
        final cx = rect.right - pad;
        canvas.drawLine(
          Offset(cx - 5, y + itemH / 2 - 5),
          Offset(cx + 5, y + itemH / 2 + 5),
          Paint()
            ..color = Colors.white38
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          Offset(cx + 5, y + itemH / 2 - 5),
          Offset(cx - 5, y + itemH / 2 + 5),
          Paint()
            ..color = Colors.white38
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EegChartPainter old) =>
      old.visibleStart != visibleStart ||
      old.visibleEnd != visibleEnd ||
      old.slices != slices;
}
