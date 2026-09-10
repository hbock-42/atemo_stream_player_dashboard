/// The hidden way in to [DiagnosticsScreen].
///
/// A wrapper rather than a button on the main screen: nothing about the normal
/// UI changes, and the now-playing screen does not have to know diagnostics
/// exist. Long-pressing the top-left corner — a deliberately unremarkable
/// patch with no affordance — swaps the screen for the diagnostics view.
///
/// A corner rather than the whole screen so the gesture cannot fight the
/// transport buttons or the volume drag: holding a control still for half a
/// second must not teleport the user somewhere else.
library;

import 'package:flutter/widgets.dart';

import '../../domain/diagnostics.dart';
import 'diagnostics_screen.dart';

class DiagnosticsGate extends StatefulWidget {
  const DiagnosticsGate({
    super.key,
    required this.child,
    required this.read,
    this.hotZone = const Size(76, 76),
  });

  final Widget child;

  /// Where the facts come from. Source-agnostic by construction.
  final SourceDiagnostics Function() read;

  /// Size of the invisible corner target.
  final Size hotZone;

  @override
  State<DiagnosticsGate> createState() => _DiagnosticsGateState();
}

class _DiagnosticsGateState extends State<DiagnosticsGate> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return DiagnosticsScreen(
        read: widget.read,
        onClose: () => setState(() => _open = false),
      );
    }

    return Stack(
      // expand, not the default loose fit: a loose Stack hands its
      // non-positioned child a minWidth of 0, so the whole app shrink-wraps to
      // its widest element and gets pinned to the top-left corner. That is
      // invisible on a layout whose widest element happens to fill the screen,
      // and very visible on the wall display, which centres inside whatever
      // width it is given.
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          width: widget.hotZone.width,
          height: widget.hotZone.height,
          child: GestureDetector(
            // Translucent, not opaque: taps still reach whatever is underneath,
            // so the corner keeps working as part of the normal screen.
            behavior: HitTestBehavior.translucent,
            onLongPress: () => setState(() => _open = true),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
