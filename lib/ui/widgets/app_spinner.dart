import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key, this.size = 26});

  final double size;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _SpinnerPainter(
            turns: _controller.value,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.turns, required this.color});

  final double turns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Offset.zero & size,
      turns * 2 * math.pi,
      math.pi * 1.4,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.turns != turns;
}
