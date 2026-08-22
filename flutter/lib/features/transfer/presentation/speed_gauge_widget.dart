import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';

class SpeedGaugePainter extends CustomPainter {
  final double speedMBs;
  final double maxMBs;

  SpeedGaugePainter({required this.speedMBs, required this.maxMBs});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.65);
    final radius = size.width * 0.42;
    const startAngle = pi * 0.75;
    const sweepTotal = pi * 1.5;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal, false,
      Paint()
        ..color = AppColors.cardBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );

    // Value arc
    final fraction = (speedMBs / maxMBs).clamp(0.0, 1.0);
    if (fraction > 0) {
      final gradient = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepTotal * fraction,
        colors: const [AppColors.primary, AppColors.accentGreen],
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepTotal * fraction, false,
        Paint()
          ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tick marks
    final tickPaint = Paint()..color = AppColors.textMuted..strokeWidth = 1;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + sweepTotal * i / 10;
      final inner = radius - 16;
      final outer = radius - 8;
      canvas.drawLine(
        Offset(center.dx + inner * cos(angle), center.dy + inner * sin(angle)),
        Offset(center.dx + outer * cos(angle), center.dy + outer * sin(angle)),
        tickPaint,
      );
    }

    // Needle tip dot
    final needleAngle = startAngle + sweepTotal * fraction;
    canvas.drawCircle(
      Offset(center.dx + radius * cos(needleAngle), center.dy + radius * sin(needleAngle)),
      6,
      Paint()..color = AppColors.primary,
    );

    // Center value text
    final valTp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: speedMBs.toStringAsFixed(1),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valTp.paint(canvas, Offset(center.dx - valTp.width / 2, center.dy - valTp.height / 2 - 8));

    final unitTp = TextPainter(
      text: const TextSpan(
        text: 'MB/s',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas, Offset(center.dx - unitTp.width / 2, center.dy + 18));
  }

  @override
  bool shouldRepaint(SpeedGaugePainter old) => old.speedMBs != speedMBs;
}

class SpeedGaugeWidget extends StatelessWidget {
  final double speedMBs;
  final double maxMBs;

  const SpeedGaugeWidget({super.key, required this.speedMBs, this.maxMBs = 500});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 110,
      child: CustomPaint(
        painter: SpeedGaugePainter(speedMBs: speedMBs, maxMBs: maxMBs),
      ),
    );
  }
}
