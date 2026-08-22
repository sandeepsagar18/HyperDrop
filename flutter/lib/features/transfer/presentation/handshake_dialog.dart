import 'package:flutter/material.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/core/utils/format_utils.dart';
import 'package:hyperdrop_flutter/features/transfer/domain/models/handshake_model.dart';

class HandshakeAuthorizationDialog extends StatelessWidget {
  final HandshakeRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const HandshakeAuthorizationDialog({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Incoming Transfer',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${request.senderDeviceName}" wants to send files to your device.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                _buildInfoRow('Sender IP', request.senderIp),
                const Divider(color: AppColors.cardBorder, height: 16),
                _buildInfoRow('Total Files', '${request.totalFiles} items'),
                const Divider(color: AppColors.cardBorder, height: 16),
                _buildInfoRow('Total Size', FormatUtils.formatBytes(request.totalSizeBytes)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onReject,
          child: const Text('Decline', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onAccept,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Accept & Receive', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
