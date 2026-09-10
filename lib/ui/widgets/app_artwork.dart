/// Album artwork, with a designed placeholder.
///
/// Artwork comes from the device's own address, which is a different origin
/// from the relay — so the relay proxies it and sends a path on its own origin
/// instead. A speaker is never going to send CORS headers, and Flutter web
/// fetches images through CanvasKit, where a cross-origin image simply does not
/// load. See `RelayServer._withProxiedArtwork`.
///
/// Missing, slow or broken artwork must never produce a broken image or an
/// exception — it falls back to the placeholder.
///
/// Note for anyone debugging this against a headless browser: the placeholder
/// paints but network images do not, which is a CanvasKit limitation there and
/// not a fault in this widget. Check in a real browser.
library;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

class AppArtwork extends StatelessWidget {
  const AppArtwork({super.key, required this.url, this.size = 260});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final radius = BorderRadius.circular(size * 0.05);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: colors.surface,
        child: url == null
            ? _Placeholder(size: size)
            : Image.network(
                url!,
                // Keyed on the URL so an identical URL in successive status
                // messages does not tear the image down and reload it.
                key: ValueKey(url),
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _Placeholder(size: size),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _Placeholder(size: size),
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    return Container(
      width: size,
      height: size,
      color: colors.surface,
      alignment: Alignment.center,
      child: AppIcon(AppIconData.note, size: size * 0.22, color: colors.textDisabled),
    );
  }
}
