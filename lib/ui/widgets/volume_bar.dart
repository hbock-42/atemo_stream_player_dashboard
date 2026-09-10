/// Device volume.
///
/// Shown while playing *and* while idle: volume is addressed to the receiver
/// rather than to the casting app, so it works with no app running and is the
/// one control we can rely on.
library;

import 'package:flutter/widgets.dart';

import '../../state/now_playing_controller.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_icon.dart';
import 'app_slider.dart';

class VolumeBar extends StatelessWidget {
  const VolumeBar({
    super.key,
    required this.controller,
    required this.level,
    required this.isMuted,
    required this.enabled,
  });

  final NowPlayingController controller;
  final double? level;
  final bool isMuted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    // A device that has not reported volume yet gets a neutral slider rather
    // than a jumpy one that snaps when the first status arrives.
    final value = level ?? 0.0;

    return Row(
      children: [
        AppIconButton(
          icon: isMuted ? AppIconData.volumeMuted : AppIconData.volume,
          size: 20,
          semanticLabel: isMuted ? 'Unmute' : 'Mute',
          onPressed: enabled ? controller.toggleMute : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: AppSlider(
              value: isMuted ? 0 : value,
              enabled: enabled,
              semanticLabel: 'Volume',
              onChangeStart: controller.beginVolumeDrag,
              onChanged: controller.setVolume,
              onChangeEnd: controller.endVolumeDrag,
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${((isMuted ? 0 : value) * 100).round()}',
            textAlign: TextAlign.end,
            style: AppTheme.of(context).typography.caption.copyWith(
                  color: enabled ? colors.textSecondary : colors.textDisabled,
                ),
          ),
        ),
      ],
    );
  }
}
