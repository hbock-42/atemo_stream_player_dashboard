/// A horizontal slider built from a gesture detector and a painter.
///
/// Reports live values while dragging and a settled value on release, so the
/// caller can rate-limit what it sends and still transmit the final position.
library;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.enabled = true,
    this.height = 44,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;
  final double height;
  final String? semanticLabel;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  double? _dragValue;

  double get _effectiveValue => (_dragValue ?? widget.value).clamp(0.0, 1.0).toDouble();

  void _update(double dx, double width) {
    if (!widget.enabled) return;
    final next = (dx / width).clamp(0.0, 1.0).toDouble();
    setState(() => _dragValue = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          enabled: widget.enabled,
          label: widget.semanticLabel,
          value: '${(_effectiveValue * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled
                ? (details) {
                    widget.onChangeStart?.call();
                    _update(details.localPosition.dx, width);
                  }
                : null,
            onHorizontalDragUpdate:
                widget.enabled ? (details) => _update(details.localPosition.dx, width) : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    final settled = _effectiveValue;
                    setState(() => _dragValue = null);
                    widget.onChangeEnd?.call(settled);
                  }
                : null,
            onTapDown: widget.enabled
                ? (details) {
                    widget.onChangeStart?.call();
                    _update(details.localPosition.dx, width);
                  }
                : null,
            onTapUp: widget.enabled
                ? (_) {
                    final settled = _effectiveValue;
                    setState(() => _dragValue = null);
                    widget.onChangeEnd?.call(settled);
                  }
                : null,
            child: SizedBox(
              height: widget.height,
              width: width,
              child: CustomPaint(
                painter: _SliderPainter(
                  value: _effectiveValue,
                  track: colors.surfaceRaised,
                  fill: widget.enabled ? colors.accent : colors.textDisabled,
                  thumb: widget.enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.thumb,
  });

  final double value;
  final Color track;
  final Color fill;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 6.0;
    final centreY = size.height / 2;
    final radius = const Radius.circular(trackHeight / 2);

    canvas.drawRRect(
      RRect.fromLTRBR(0, centreY - trackHeight / 2, size.width, centreY + trackHeight / 2, radius),
      Paint()..color = track,
    );

    final filledWidth = size.width * value;
    if (filledWidth > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, centreY - trackHeight / 2, filledWidth, centreY + trackHeight / 2, radius),
        Paint()..color = fill,
      );
    }

    canvas.drawCircle(
      Offset(filledWidth.clamp(8.0, size.width - 8.0), centreY),
      8,
      Paint()
        ..color = thumb
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.fill != fill;
}
