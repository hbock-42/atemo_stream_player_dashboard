/// The one screen.
///
/// Four states, visibly distinct. "Nothing is playing" and "I cannot see the
/// speaker" must never look the same.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/now_playing.dart';
import '../../state/now_playing_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_artwork.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_spinner.dart';
import '../widgets/app_text.dart';
import '../widgets/display_mode.dart';
import '../widgets/volume_bar.dart';
import '../widgets/wall_view.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller, this.mode});

  final NowPlayingController controller;

  /// Normally read from the page URL — `?wall` puts this instance into
  /// wall-display mode (POL-01, see `display_mode.dart`). Passed explicitly
  /// only by tests.
  final DisplayMode? mode;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final padding = MediaQuery.paddingOf(context);

    // Uri.base is the page URL on web; on native it is a file: path with no
    // query, so the native build simply never selects wall mode this way.
    if ((mode ?? displayModeFromUri(Uri.base)) == DisplayMode.wall) {
      return WallView(controller: controller);
    }

    return ColoredBox(
      color: colors.background,
      child: Padding(
        // No Scaffold, so safe areas are ours to handle.
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom,
          left: padding.left,
          right: padding.right,
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _FlickerGuard(
            state: controller.value,
            builder: (context, state) => Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: KeyedSubtree(
                      key: ValueKey(state.runtimeType),
                      child: _body(state),
                    ),
                  ),
                ),
                if (controller.lastError != null)
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom: AppSpacing.lg,
                    child: _ErrorBanner(message: controller.lastError!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(NowPlaying state) => switch (state) {
        Playing() => _PlayingView(controller: controller, state: state),
        Idle() => _IdleView(controller: controller, state: state),
        Unreachable() => _UnreachableView(controller: controller, state: state),
        Connecting() => const _ConnectingView(),
      };
}

/// Suppresses a [Connecting] state that lasts less than half a second, so a
/// fast reconnect is not visible as a flash of spinner over a live screen.
class _FlickerGuard extends StatefulWidget {
  const _FlickerGuard({required this.state, required this.builder});

  final NowPlaying state;
  final Widget Function(BuildContext, NowPlaying) builder;

  @override
  State<_FlickerGuard> createState() => _FlickerGuardState();
}

class _FlickerGuardState extends State<_FlickerGuard> {
  static const _grace = Duration(milliseconds: 500);

  late NowPlaying _shown = widget.state;
  Timer? _timer;

  @override
  void didUpdateWidget(_FlickerGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.state;

    if (next is Connecting && _shown is! Connecting) {
      _timer ??= Timer(_grace, () {
        _timer = null;
        if (mounted && widget.state is Connecting) {
          setState(() => _shown = widget.state);
        }
      });
      return;
    }

    _timer?.cancel();
    _timer = null;
    if (next != _shown) setState(() => _shown = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}

class _Frame extends StatelessWidget {
  const _Frame({required this.children});

  /// A phone-shaped column, centred, however wide the browser window is. Text
  /// stretched across a 27" monitor is unreadable, and the artwork clamp above
  /// already stops the image growing — without this the two disagree.
  static const _maxContentWidth = 520.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - 1),
          child: Padding(
            // Horizontal padding stays modest so a 360px phone — the narrowest
            // we support — still has room for the controls row.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      );
}

class _PlayingView extends StatelessWidget {
  const _PlayingView({required this.controller, required this.state});

  final NowPlayingController controller;
  final Playing state;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final canControl = controller.canControl;
    final capabilities = state.capabilities;
    final width = MediaQuery.sizeOf(context).width;
    final artworkSize = (width - AppSpacing.lg * 2).clamp(120.0, 320.0).toDouble();

    return _Frame(
      children: [
        Center(child: AppArtwork(url: state.artworkUrl, size: artworkSize)),
        const SizedBox(height: AppSpacing.lg),
        if (state.castingApp != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppText(
              state.castingApp!.toUpperCase(),
              style: AppTextStyleName.caption,
              color: colors.accent,
              align: TextAlign.center,
            ),
          ),
        AppText(
          state.title ?? 'Unknown track',
          style: AppTextStyleName.display,
          color: state.title == null ? colors.textSecondary : colors.textPrimary,
          maxLines: 2,
          align: TextAlign.center,
        ),
        if (state.artist != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppText(
            state.artist!,
            style: AppTextStyleName.title,
            color: colors.textSecondary,
            maxLines: 1,
            align: TextAlign.center,
          ),
        ],
        if (state.album != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppText(
            state.album!,
            style: AppTextStyleName.body,
            color: colors.textSecondary,
            maxLines: 1,
            align: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (canControl) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconButton(
                icon: AppIconData.previous,
                size: 24,
                semanticLabel: 'Previous track',
                // Disabled rather than absent: the control exists, this app
                // just doesn't support it.
                onPressed: capabilities.canSkipPrevious ? controller.previous : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              AppIconButton(
                icon: state.isPaused ? AppIconData.play : AppIconData.pause,
                size: 30,
                emphasised: true,
                semanticLabel: state.isPaused ? 'Play' : 'Pause',
                onPressed: capabilities.canPause
                    ? (state.isPaused ? controller.play : controller.pause)
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              AppIconButton(
                icon: AppIconData.next,
                size: 24,
                semanticLabel: 'Next track',
                onPressed: capabilities.canSkipNext ? controller.next : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          VolumeBar(
            controller: controller,
            level: state.volumeLevel,
            isMuted: state.isMuted,
            enabled: true,
          ),
        ] else
          const _ViewOnlyNote(),
      ],
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.controller, required this.state});

  final NowPlayingController controller;
  final Idle state;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;

    return _Frame(
      children: [
        Center(
          child: AppIcon(AppIconData.note, size: 56, color: colors.textDisabled),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppText(
          'Nothing playing',
          style: AppTextStyleName.display,
          align: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppText(
          '${state.deviceName ?? 'The Streamplayer'} is connected and idle',
          style: AppTextStyleName.body,
          align: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        // Volume is device-level, so it still works with nothing playing.
        if (controller.canControl)
          VolumeBar(
            controller: controller,
            level: state.volumeLevel,
            isMuted: state.isMuted,
            enabled: true,
          )
        else
          const _ViewOnlyNote(),
      ],
    );
  }
}

class _UnreachableView extends StatelessWidget {
  const _UnreachableView({required this.controller, required this.state});

  final NowPlayingController controller;
  final Unreachable state;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;

    return _Frame(
      children: [
        Center(child: AppIcon(AppIconData.offline, size: 56, color: colors.error)),
        const SizedBox(height: AppSpacing.lg),
        AppText(
          "Can't reach the speaker",
          style: AppTextStyleName.display,
          align: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppText(state.reason, style: AppTextStyleName.body, align: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        // Retrying happens on its own; this is a shortcut, not a requirement,
        // and the caption says so.
        Center(
          child: AppTextButton(
            label: 'Try now',
            icon: AppIconData.retry,
            onPressed: controller.retry,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppText(
          'Still trying automatically',
          style: AppTextStyleName.caption,
          color: colors.textDisabled,
          align: TextAlign.center,
        ),
      ],
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) => _Frame(
        children: [
          const Center(child: AppSpinner()),
          const SizedBox(height: AppSpacing.md),
          AppText(
            'Looking for the Streamplayer',
            style: AppTextStyleName.body,
            align: TextAlign.center,
          ),
        ],
      );
}

/// Shown when the source offers no control at all — a different situation from
/// an app that lacks a capability, so it looks different: the controls are
/// absent rather than disabled.
class _ViewOnlyNote extends StatelessWidget {
  const _ViewOnlyNote();

  @override
  Widget build(BuildContext context) => AppText(
        'View only',
        style: AppTextStyleName.caption,
        color: AppTheme.of(context).colors.textDisabled,
        align: TextAlign.center,
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error),
      ),
      child: AppText(
        message,
        style: AppTextStyleName.body,
        color: colors.textPrimary,
        align: TextAlign.center,
        maxLines: 2,
      ),
    );
  }
}
