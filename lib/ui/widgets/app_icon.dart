/// Hand-drawn icons.
///
/// Material's icon font is unavailable (ADR-0003) and pulling in an icon
/// package would reintroduce the dependency the constraint exists to avoid, so
/// the handful we need are painted from paths on a 24x24 grid.
library;

import 'package:flutter/widgets.dart';

enum AppIconData { play, pause, next, previous, volume, volumeMuted, retry, note, offline }

class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = 24, required this.color});

  final AppIconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IconPainter(icon, color)),
      );
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.color);

  final AppIconData icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (icon) {
      case AppIconData.play:
        canvas.drawPath(
          Path()
            ..moveTo(7, 4.5)
            ..lineTo(19, 12)
            ..lineTo(7, 19.5)
            ..close(),
          fill,
        );
      case AppIconData.pause:
        canvas
          ..drawRRect(
            RRect.fromLTRBR(6, 4.5, 10, 19.5, const Radius.circular(1.2)),
            fill,
          )
          ..drawRRect(
            RRect.fromLTRBR(14, 4.5, 18, 19.5, const Radius.circular(1.2)),
            fill,
          );
      case AppIconData.next:
        canvas
          ..drawPath(
            Path()
              ..moveTo(5, 5)
              ..lineTo(15, 12)
              ..lineTo(5, 19)
              ..close(),
            fill,
          )
          ..drawRRect(
            RRect.fromLTRBR(16.5, 5, 19, 19, const Radius.circular(1.2)),
            fill,
          );
      case AppIconData.previous:
        canvas
          ..drawPath(
            Path()
              ..moveTo(19, 5)
              ..lineTo(9, 12)
              ..lineTo(19, 19)
              ..close(),
            fill,
          )
          ..drawRRect(
            RRect.fromLTRBR(5, 5, 7.5, 19, const Radius.circular(1.2)),
            fill,
          );
      case AppIconData.volume:
        _speaker(canvas, fill);
        canvas
          ..drawArc(const Rect.fromLTRB(11, 7.5, 18, 16.5), -0.9, 1.8, false, stroke)
          ..drawArc(const Rect.fromLTRB(13, 4.5, 22, 19.5), -0.9, 1.8, false, stroke);
      case AppIconData.volumeMuted:
        _speaker(canvas, fill);
        canvas
          ..drawLine(const Offset(14, 9), const Offset(20, 15), stroke)
          ..drawLine(const Offset(20, 9), const Offset(14, 15), stroke);
      case AppIconData.retry:
        canvas
          ..drawArc(const Rect.fromLTRB(4, 4, 20, 20), -0.5, 4.7, false, stroke)
          ..drawPath(
            Path()
              ..moveTo(19, 3)
              ..lineTo(19.5, 9)
              ..lineTo(13.5, 8)
              ..close(),
            fill,
          );
      case AppIconData.note:
        canvas
          ..drawPath(
            Path()
              ..moveTo(10, 17)
              ..lineTo(10, 5)
              ..lineTo(19, 3)
              ..lineTo(19, 15),
            stroke,
          )
          ..drawOval(Rect.fromCircle(center: const Offset(7.5, 17), radius: 2.8), fill)
          ..drawOval(Rect.fromCircle(center: const Offset(16.5, 15), radius: 2.8), fill);
      case AppIconData.offline:
        canvas
          ..drawArc(const Rect.fromLTRB(3, 6, 21, 24), 3.34, 2.6, false, stroke)
          ..drawArc(const Rect.fromLTRB(7, 10, 17, 20), 3.34, 2.6, false, stroke)
          ..drawOval(Rect.fromCircle(center: const Offset(12, 17.5), radius: 1.4), fill)
          ..drawLine(const Offset(4, 20), const Offset(20, 4), stroke);
    }
  }

  void _speaker(Canvas canvas, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(4, 9.5)
        ..lineTo(7.5, 9.5)
        ..lineTo(11.5, 5.5)
        ..lineTo(11.5, 18.5)
        ..lineTo(7.5, 14.5)
        ..lineTo(4, 14.5)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}
