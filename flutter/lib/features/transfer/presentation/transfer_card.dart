import 'package:flutter/material.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/core/utils/format_utils.dart';
import 'package:hyperdrop_flutter/features/transfer/domain/models/transfer_model.dart';

class TransferCard extends StatelessWidget {
  final TransferModel transfer;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  const TransferCard({
    super.key,
    required this.transfer,
    this.onCancel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  transfer.direction == TransferDirection.outgoing
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transfer.direction == TransferDirection.outgoing ? "To" : "From"}: ${transfer.peerName}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${transfer.percent}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: transfer.progress,
              backgroundColor: AppColors.background,
              color: AppColors.primary,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${FormatUtils.formatBytes(transfer.bytesTransferred)} / ${FormatUtils.formatBytes(transfer.fileSize)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (transfer.status == TransferStatus.transferring) ...[
                    Text(
                      '${transfer.speedMBs.toStringAsFixed(1)} MB/s',
                      style: const TextStyle(
                        color: AppColors.accentGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onCancel != null)
                      InkWell(
                        onTap: onCancel,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.accentRed.withOpacity(0.4)),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                  if (transfer.status == TransferStatus.completed) ...[
                    const Text('✓ Done', style: TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold, fontSize: 11)),
                    if (onRetry != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onRetry,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: const Text('Restart', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                  if (transfer.status == TransferStatus.cancelled) ...[
                    const Text('✕ Cancelled', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 11)),
                    if (onRetry != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onRetry,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: const Text('Restart', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                  if (transfer.status == TransferStatus.failed) ...[
                    const Text('✕ Failed', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold, fontSize: 11)),
                    if (onRetry != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onRetry,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: const Text('Restart', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
