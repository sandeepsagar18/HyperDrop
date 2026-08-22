import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/features/discovery/domain/models/device_model.dart';

class RadarPainter extends CustomPainter {
  final double sweepAngle;
  final List<DeviceModel> peers;
  final String selfName;

  RadarPainter({
    required this.sweepAngle,
    required this.peers,
    required this.selfName,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2 - 8;

    // Background rings - very subtle
    final ringPaint = Paint()
      ..color = AppColors.primary.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * i / 4, ringPaint);
    }

    // Cross hairs - very faint
    final crossPaint = Paint()
      ..color = AppColors.primary.withAlpha(15)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius),
        Offset(center.dx, center.dy + maxRadius), crossPaint);
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy),
        Offset(center.dx + maxRadius, center.dy), crossPaint);

    // Outer boundary circle
    canvas.drawCircle(center, maxRadius,
      Paint()
        ..color = AppColors.primary.withAlpha(40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);

    // Sweep fill - very light, just a thin wedge
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    canvas.drawArc(
      sweepRect,
      sweepAngle - 0.6,
      0.6,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle - 0.6,
          endAngle: sweepAngle,
          colors: [
            Colors.transparent,
            AppColors.primary.withAlpha(30),
          ],
        ).createShader(sweepRect)
        ..style = PaintingStyle.fill,
    );

    // Sweep line - thin, clean
    final sweepEnd = Offset(
      center.dx + maxRadius * cos(sweepAngle),
      center.dy + maxRadius * sin(sweepAngle),
    );
    canvas.drawLine(
      center,
      sweepEnd,
      Paint()
        ..color = AppColors.primary.withAlpha(180)
        ..strokeWidth = 1.2,
    );

    // Peer dots
    for (int i = 0; i < peers.length; i++) {
      final angle = (2 * pi / max(peers.length, 1)) * i - pi / 2;
      final r = maxRadius * 0.6;
      final pos = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );

      // Soft glow
      canvas.drawCircle(pos, 12,
        Paint()..color = AppColors.accentGreen.withAlpha(25));
      // Dot
      canvas.drawCircle(pos, 5,
        Paint()..color = AppColors.accentGreen);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: peers[i].deviceName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: ' [${peers[i].deviceType.name.toUpperCase()}]',
              style: TextStyle(
                  color: AppColors.primary.withAlpha(180), fontSize: 8),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 8));
    }

    // Self dot — center
    canvas.drawCircle(center, 16,
      Paint()..color = AppColors.primary.withAlpha(20));
    canvas.drawCircle(center, 7,
      Paint()..color = AppColors.primary);

    // Self label
    final selfTp = TextPainter(
      text: TextSpan(
        text: 'You ($selfName)',
        style: const TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    selfTp.paint(
        canvas, Offset(center.dx - selfTp.width / 2, center.dy + 10));
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.sweepAngle != sweepAngle || old.peers.length != peers.length;
}

class RadarWidget extends StatefulWidget {
  final List<DeviceModel> peers;
  final String selfName;

  const RadarWidget({super.key, required this.peers, required this.selfName});

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: RadarPainter(
          sweepAngle: _ctrl.value * 2 * pi,
          peers: widget.peers,
          selfName: widget.selfName,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
