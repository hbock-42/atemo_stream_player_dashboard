/// The "it doesn't work" screen.
///
/// Reads a [SourceDiagnostics] from the domain seam and prints it. It has no
/// idea what protocol produced those facts — the labels arrive as data, so a
/// transport id can be shown here without `lib/ui/` ever importing `lib/cast/`.
///
/// Everything on it is safe in a release build: a LAN address, a session id,
/// connection state and our own log lines. No credentials exist in this system
/// to leak (the LAN is the credential, ADR-0006).
library;

import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import '../../domain/diagnostics.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.read,
    required this.onClose,
    this.refreshInterval = const Duration(seconds: 1),
  });

  /// Pulled rather than pushed: the interesting number here is "seconds since
  /// the last message", which changes when nothing happens, so a stream of
  /// updates would not keep it honest anyway.
  final SourceDiagnostics Function() read;

  final VoidCallback onClose;
  final Duration refreshInterval;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Timer? _ticker;
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(widget.refreshInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(SourceDiagnostics diagnostics) async {
    await Clipboard.setData(ClipboardData(text: diagnostics.toReport()));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final colors = theme.colors;
    final diagnostics = widget.read();
    final silence = diagnostics.silenceFor();
    final padding = MediaQuery.paddingOf(context);

    return Container(
      color: colors.background,
      padding: EdgeInsets.only(
        top: padding.top + AppSpacing.md,
        bottom: padding.bottom + AppSpacing.md,
        left: AppSpacing.md,
        right: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: AppText('DIAGNOSTICS', style: AppTextStyleName.caption),
              ),
              AppTextButton(label: 'Close', onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Field(label: 'Source mode', value: diagnostics.mode.label),
                _Field(
                  label: 'Connection',
                  value: diagnostics.link.label,
                  emphasis: diagnostics.link == LinkState.connected
                      ? colors.accent
                      : diagnostics.link == LinkState.disconnected
                          ? colors.error
                          : null,
                ),
                _Field(label: 'Address', value: diagnostics.endpoint ?? 'not discovered'),
                _Field(label: 'Session', value: diagnostics.sessionId ?? 'none'),
                _Field(
                  label: 'Last message',
                  value: silence == null ? 'never' : '${silence.inSeconds}s ago',
                ),
                _Field(
                  label: 'Last error',
                  value: diagnostics.lastError ?? 'none',
                  emphasis: diagnostics.lastError == null ? null : colors.error,
                ),
                for (final fact in diagnostics.facts)
                  _Field(label: fact.label, value: fact.value),
                const SizedBox(height: AppSpacing.lg),
                const AppText('RECENT', style: AppTextStyleName.caption),
                const SizedBox(height: AppSpacing.sm),
                if (diagnostics.log.isEmpty)
                  AppText('nothing logged yet', color: colors.textDisabled)
                else
                  // Newest first: the last thing that happened is the thing
                  // being asked about.
                  for (final entry in diagnostics.log.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: AppText(
                        entry.format(),
                        style: AppTextStyleName.caption,
                        color: colors.textSecondary,
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppTextButton(
                label: _copied ? 'Copied' : 'Copy report',
                onPressed: () => _copy(diagnostics),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.emphasis});

  final String label;
  final String value;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: AppText(label, color: colors.textDisabled),
          ),
          Expanded(
            child: AppText(value, color: emphasis ?? colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
