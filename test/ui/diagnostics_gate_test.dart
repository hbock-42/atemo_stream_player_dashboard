import 'package:atemo_stream_player_viewer/domain/diagnostics.dart';
import 'package:atemo_stream_player_viewer/ui/screens/diagnostics_gate.dart';
import 'package:atemo_stream_player_viewer/ui/theme/app_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reports the constraints it is handed, so a test can assert on them.
class _ConstraintProbe extends StatelessWidget {
  const _ConstraintProbe(this.onConstraints);
  final void Function(BoxConstraints) onConstraints;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          onConstraints(constraints);
          return const SizedBox.expand();
        },
      );
}

void main() {
  testWidgets('the gate does not loosen the app it wraps', (tester) async {
    // The gate wraps the entire app in a Stack. With the default loose fit,
    // the app is handed a minWidth of 0, shrink-wraps to its widest element
    // and is pinned to the top-left — which looked fine on the phone layout
    // and left the wall display anchored in a corner with a dead margin.
    late BoxConstraints seen;

    // The default test surface is 800x600; a tablet is the case that exposed
    // this, so use one.
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppTheme(
        child: DefaultTextStyle(
          style: AppTypography.dark.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(820, 1180)),
              child: DiagnosticsGate(
                read: () => const SourceDiagnostics(),
                child: _ConstraintProbe((c) => seen = c),
              ),
            ),
          ),
        ),
      ),
    );

    expect(seen.maxWidth, 820);
    expect(seen.minWidth, 820,
        reason: 'the app must be told to fill the screen, not merely allowed to');
    expect(seen.minHeight, 1180);
  });
}
