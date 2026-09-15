/// A track-position line: a thin progress bar and elapsed/total times.
///
/// The device reports position only when something changes — it does not tick.
/// So this interpolates: it records when a new position arrived and, while
/// playing, advances the displayed position by the wall-clock time since. A
/// fresh report from the device resets the baseline, so drift never
/// accumulates.
///
/// Display only. The speaker can seek, but this is a passive now-playing view;
/// making the bar draggable would be a separate piece of work.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class TrackProgress extends StatefulWidget {
  const TrackProgress({
    super.key,
    required this.position,
    required this.duration,
    required this.isPaused,
    this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;

  /// When non-null the bar is draggable, and this is called with the target
  /// position on release. Null makes it a read-only indicator — the app is a
  /// display first, and not every source or app permits seeking.
  final ValueChanged<Duration>? onSeek;

  @override
  State<TrackProgress> createState() => _TrackProgressState();
}

class _TrackProgressState extends State<TrackProgress> {
  static const _tick = Duration(seconds: 1);

  Duration _base = Duration.zero;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  /// The fraction the finger is at while dragging, or null when not dragging.
  double? _dragFraction;

  @override
  void initState() {
    super.initState();
    _resample();
    _syncTicker();
  }

  @override
  void didUpdateWidget(TrackProgress old) {
    super.didUpdateWidget(old);
    // A new report from the device, or play/pause toggling, resets the
    // baseline so the interpolation tracks the truth rather than drifting.
    if (widget.position != old.position || widget.isPaused != old.isPaused) {
      _resample();
      _syncTicker();
    }
  }

  void _resample() {
    _base = widget.position;
    _elapsed = Duration.zero;
  }

  void _syncTicker() {
    _ticker?.cancel();
    // No point ticking a paused track — the position is not moving. Elapsed is
    // accumulated from the ticker rather than read from the wall clock, so the
    // display advances by the same rule under a test's fake clock as in
    // production, and stays testable.
    if (widget.isPaused) {
      _ticker = null;
    } else {
      _ticker = Timer.periodic(_tick, (_) => setState(() => _elapsed += _tick));
    }
  }

  /// The position to show now: the last report plus accumulated ticks if
  /// playing, clamped to the duration so it never overshoots the end.
  Duration get _displayed {
    final raw = _base + (widget.isPaused ? Duration.zero : _elapsed);
    if (raw > widget.duration) return widget.duration;
    return raw.isNegative ? Duration.zero : raw;
  }

  Widget _bar(AppTheme theme, double fraction) {
    final track = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        children: [
          Container(height: 3, color: theme.colors.surfaceRaised),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(height: 3, color: theme.colors.accent),
          ),
        ],
      ),
    );

    if (widget.onSeek == null) return track;

    // A 3px line is unhittable, so give it a taller transparent hit area and a
    // thumb, and drive seeking off the finger's x within the bar's width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void update(double dx) =>
            setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
        void commit() {
          final f = _dragFraction;
          setState(() => _dragFraction = null);
          if (f != null) widget.onSeek!(widget.duration * f);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition.dx),
          onTapUp: (_) => commit(),
          onHorizontalDragStart: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          onHorizontalDragEnd: (_) => commit(),
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                track,
                Align(
                  alignment: Alignment(fraction * 2 - 1, 0),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final shown = _dragFraction != null
        ? widget.duration * _dragFraction!
        : _displayed;
    final fraction = _dragFraction ??
        (widget.duration.inMilliseconds == 0
            ? 0.0
            : (shown.inMilliseconds / widget.duration.inMilliseconds)
                .clamp(0.0, 1.0));

    final label = theme.typography.caption.copyWith(color: theme.colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(theme, fraction),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatDuration(shown), style: label),
            Text(formatDuration(widget.duration), style: label),
          ],
        ),
      ],
    );
  }
}

/// `m:ss`, or `h:mm:ss` once past an hour — so a 3-hour mix reads correctly.
String formatDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}
