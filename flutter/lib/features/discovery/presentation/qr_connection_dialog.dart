import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/features/identity/domain/models/device_identity.dart';

class QrConnectionDialog extends StatelessWidget {
  final DeviceIdentity identity;
  final String localIp;

  const QrConnectionDialog({
    super.key,
    required this.identity,
    required this.localIp,
  });

  String get _qrPayload {
    // Port 8080 is the built-in standalone server inside the Flutter app
    return 'http://$localIp:8080/connect?token=${identity.token}&name=${Uri.encodeQueryComponent(identity.deviceName)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      title: const Center(
        child: Text(
          'Direct QR Connect',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 224,
              height: 224,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _qrPayload,
                version: QrVersions.auto,
                size: 200,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Scan to open the HyperDrop web app on your phone — works even when this window is closed',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'http://$localIp:3000',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '✓ Server always available on LAN',
                style: TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.only(bottom: 16),
      actions: [
        Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.close_rounded, size: 16),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            label: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}