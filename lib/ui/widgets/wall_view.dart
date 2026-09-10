/// POL-01 — the tablet on the wall.
///
/// A different screen rather than a flag threaded through the remote: nothing
/// here is tappable, nothing is capability-gated, and there is no chrome to
/// hide because none is built. Reading distance is metres, so type is sized
/// from the viewport instead of from the token scale, which is tuned for a
/// phone in the hand.
///
/// Longevity (this thing runs for months without a reload):
///   * no timers at all — the only animations are implicit ones owned by the
///     framework and torn down with the element;
///   * exactly one listener, the browser bridge, cancelled in [dispose];
///   * artwork is keyed on its URL by `AppArtwork`, so an unchanged track does
///     not re-fetch an image every status message.
///
/// It plays nothing. There is no audio or video element anywhere in this app —
/// it is a remote and a display — so no browser autoplay policy is ever
/// engaged and no "click to enable sound" gesture is ever required (WEB-03).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/now_playing.dart';
import '../../platform/browser.dart';
import '../../state/now_playing_controller.dart';
import '../theme/app_theme.dart';
import 'app_artwork.dart';
import 'app_icon.dart';
import 'app_spinner.dart';

class WallView extends StatefulWidget {
  const WallView({super.key, required this.controller, this.browser});

  final NowPlayingController controller;

  /// Injected by tests. Left null in the app, which builds the bridge for the
  /// current platform (a real one on web, an inert one on native).
  final BrowserBridge? browser;

  @override
  State<WallView> createState() => _WallViewState();
}

class _WallViewState extends State<WallView> {
  /// Dim rather than blank on [Idle]: a wall at the back of an office should
  /// not be a nightlight, but going fully black reads as "broken".
  static const _idleOpacity = 0.28;

  late final bool _ownsBrowser = widget.browser == null;
  late final BrowserBridge _browser = widget.browser ?? createBrowserBridge();

  @override
  void initState() {
    super.initState();
    // Screen Wake Lock where it exists; where it does not — an old iPad, a
    // Firefox before 126 — this is a silent no-op and the tablet's own
    // "screen timeout: never" setting is the fallback. No plugin is added for
    // the native case; see browser_stub.dart.
    unawaited(_browser.setKeepAwake(true));
  }

  @override
  void dispose() {
    unawaited(_browser.setKeepAwake(false));
    if (_ownsBrowser) _browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final padding = MediaQuery.paddingOf(context);

    return ColoredBox(
      color: colors.background,
      child: Padding(
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom,
          left: padding.left,
          right: padding.right,
        ),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final state = widget.controller.value;
            return AnimatedOpacity(
              opacity: state is Idle ? _idleOpacity : 1,
              duration: const Duration(milliseconds: 900),
              child: LayoutBuilder(
                builder: (context, constraints) => _WallBody(
                  state: state,
                  metrics: _WallMetrics.of(constraints),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sizes derived from the viewport, so the same layout reads across a room on
/// a 10" tablet in either orientation and on a TV.
class _WallMetrics {
  const _WallMetrics({
    required this.artwork,
    required this.title,
    required this.horizontal,
    required this.gutter,
  });

  factory _WallMetrics.of(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final shortest = math.min(width, height);
    // Side by side only when there is genuinely landscape room; a tablet in
    // portrait stacks.
    final horizontal = width > height * 1.15 && width >= 640;
    final artwork = horizontal
        ? math.min(height * 0.72, width * 0.4)
        : math.min(width * 0.62, height * 0.46);

    return _WallMetrics(
      artwork: math.max(artwork, 96),
      title: (shortest * 0.082).clamp(26.0, 104.0).toDouble(),
      horizontal: horizontal,
      gutter: (shortest * 0.06).clamp(16.0, 64.0).toDouble(),
    );
  }

  final double artwork;
  final double title;
  final bool horizontal;
  final double gutter;

  double get artist => title * 0.56;
  double get caption => (title * 0.26).clamp(13.0, 30.0).toDouble();
}

class _WallBody extends StatelessWidget {
  const _WallBody({required this.state, required this.metrics});

  final NowPlaying state;
  final _WallMetrics metrics;

  @override
  Widget build(BuildContext context) => switch (state) {
        final Playing playing => _WallPlaying(state: playing, metrics: metrics),
        Idle(:final deviceName) => _WallMessage(
            headline: 'Nothing playing',
            detail: deviceName,
            metrics: metrics,
          ),
        Unreachable(:final reason) => _WallMessage(
            headline: "Can't reach the speaker",
            detail: reason,
            metrics: metrics,
            isError: true,
          ),
        Connecting() => Center(child: AppSpinner(size: metrics.title)),
      };
}

class _WallPlaying extends StatelessWidget {
  const _WallPlaying({required this.state, required this.metrics});

  final Playing state;
  final _WallMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final align = metrics.horizontal ? TextAlign.left : TextAlign.center;
    final cross =
        metrics.horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: cross,
      children: [
        if (state.castingApp != null) ...[
          _WallText(
            state.castingApp!.toUpperCase(),
            size: metrics.caption,
            weight: FontWeight.w600,
            color: colors.accent,
            align: align,
            letterSpacing: metrics.caption * 0.14,
          ),
          SizedBox(height: metrics.caption * 0.8),
        ],
        _WallText(
          state.title ?? 'Unknown track',
          size: metrics.title,
          weight: FontWeight.w600,
          color: state.title == null ? colors.textSecondary : colors.textPrimary,
          align: align,
          maxLines: 3,
        ),
        if (state.artist != null) ...[
          SizedBox(height: metrics.caption * 0.7),
          _WallText(
            state.artist!,
            size: metrics.artist,
            color: colors.textSecondary,
            align: align,
            maxLines: 2,
          ),
        ],
        if (state.isPaused) ...[
          SizedBox(height: metrics.caption),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIconData.pause,
                size: metrics.caption,
                color: colors.textDisabled,
              ),
              SizedBox(width: metrics.caption * 0.5),
              _WallText(
                'PAUSED',
                size: metrics.caption,
                color: colors.textDisabled,
                align: align,
                letterSpacing: metrics.caption * 0.14,
              ),
            ],
          ),
        ],
      ],
    );

    final artwork = AppArtwork(url: state.artworkUrl, size: metrics.artwork);

    return Padding(
      padding: EdgeInsets.all(metrics.gutter),
      child: metrics.horizontal
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                artwork,
                SizedBox(width: metrics.gutter),
                Expanded(child: text),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                artwork,
                SizedBox(height: metrics.gutter),
                Flexible(child: text),
              ],
            ),
    );
  }
}

class _WallMessage extends StatelessWidget {
  const _WallMessage({
    required this.headline,
    required this.detail,
    required this.metrics,
    this.isError = false,
  });

  final String headline;
  final String? detail;
  final _WallMetrics metrics;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    return Padding(
      padding: EdgeInsets.all(metrics.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(
            isError ? AppIconData.offline : AppIconData.note,
            size: metrics.title * 1.2,
            color: isError ? colors.error : colors.textDisabled,
          ),
          SizedBox(height: metrics.gutter),
          _WallText(
            headline,
            size: metrics.title * 0.8,
            weight: FontWeight.w600,
            color: colors.textPrimary,
            align: TextAlign.center,
            maxLines: 2,
          ),
          if (detail != null) ...[
            SizedBox(height: metrics.caption * 0.7),
            _WallText(
              detail!,
              size: metrics.artist * 0.7,
              color: colors.textSecondary,
              align: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

/// Type at a size the token scale does not cover, built from the same base
/// style so the font stack and the "no debug underline" decoration come along.
class _WallText extends StatelessWidget {
  const _WallText(
    this.text, {
    required this.size,
    required this.align,
    this.color,
    this.weight,
    this.maxLines = 1,
    this.letterSpacing,
  });

  final String text;
  final double size;
  final TextAlign align;
  final Color? color;
  final FontWeight? weight;
  final int maxLines;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) {
    final typography = AppTheme.of(context).typography;
    return Text(
      text,
      textAlign: align,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: typography.display.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
