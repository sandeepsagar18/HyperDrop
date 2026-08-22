import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:path/path.dart' as p;

// Provider that scans both vault + Flutter downloads and returns sorted list
final receivedFilesProvider = FutureProvider.autoDispose<List<ReceivedFileItem>>((ref) async {
  final files = <ReceivedFileItem>[];

  final List<String> scanDirs = [];

  // 1. Node.js vault folder
  const vaultPath = r'D:\hyperdrop\.hyperdrop_vault';
  if (await Directory(vaultPath).exists()) scanDirs.add(vaultPath);

  // 2. Flutter LAN receiver Downloads/HyperDrop
  final downloadsHD = Directory(r'C:\Users\Public\Downloads\HyperDrop');
  if (await downloadsHD.exists()) scanDirs.add(downloadsHD.path);

  // 3. Any user Downloads\HyperDrop
  final userDownloads = Directory(
    p.join(Platform.environment['USERPROFILE'] ?? 'C:\\Users\\asus', 'Downloads', 'HyperDrop'));
  if (await userDownloads.exists()) scanDirs.add(userDownloads.path);

  for (final dir in scanDirs) {
    final d = Directory(dir);
    await for (final entity in d.list()) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        // Skip index/metadata files
        if (ext == '.json' || p.basename(entity.path) == 'vault_index.json') continue;
        final stat = await entity.stat();
        files.add(ReceivedFileItem(
          path: entity.path,
          name: _cleanName(p.basename(entity.path)),
          sizeBytes: stat.size,
          receivedAt: stat.modified,
          extension: ext,
        ));
      }
    }
  }

  files.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  return files;
});

String _cleanName(String raw) {
  // Strip leading timestamp prefix like "1787319245209_"
  return raw.replaceFirst(RegExp(r'^\d{13}_'), '');
}

class ReceivedFileItem {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime receivedAt;
  final String extension;

  ReceivedFileItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.receivedAt,
    required this.extension,
  });

  bool get isImage => ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif', '.avif', '.tiff', '.tif', '.raw', '.dng', '.ico', '.svg'].contains(extension);
  bool get isVideo => ['.mp4', '.mov', '.mkv', '.avi', '.webm', '.3gp', '.m4v', '.ts', '.mts', '.vob', '.wmv', '.flv'].contains(extension);
  bool get isPdf => extension == '.pdf';
  bool get isAudio => ['.mp3', '.aac', '.wav', '.flac', '.m4a', '.ogg', '.opus', '.aiff', '.alac', '.mid', '.wma'].contains(extension);

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get timeLabel {
    final diff = DateTime.now().difference(receivedAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData get icon {
    if (isImage) return Icons.image_rounded;
    if (isVideo) return Icons.videocam_rounded;
    if (isPdf) return Icons.picture_as_pdf_rounded;
    if (isAudio) return Icons.music_note_rounded;
    if (['.zip', '.rar', '.7z'].contains(extension)) return Icons.folder_zip_rounded;
    if (['.doc', '.docx'].contains(extension)) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color get iconColor {
    if (isImage) return const Color(0xFF4FACFE);
    if (isVideo) return const Color(0xFFFF9900);
    if (isPdf) return const Color(0xFFFF5252);
    if (isAudio) return const Color(0xFF7928CA);
    return AppColors.textSecondary;
  }
}

class ReceivedFilesPanel extends ConsumerWidget {
  const ReceivedFilesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(receivedFilesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Received Files',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.invalidate(receivedFilesProvider),
              icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.primary),
              label: const Text('Refresh', style: TextStyle(color: AppColors.primary, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        filesAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
          data: (files) {
            if (files.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.inbox_rounded, color: AppColors.textMuted, size: 36),
                    SizedBox(height: 8),
                    Text('No files received yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('Send a file from your phone via the web app', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              );
            }

            return Column(
              children: files.map((f) => _FileRow(file: f)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final ReceivedFileItem file;
  const _FileRow({required this.file});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Open the file with the default system application
        Process.run('explorer', ['/select,', file.path]);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            // Thumbnail or icon
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: file.isImage
                  ? Image.file(
                      File(file.path),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconBox(file),
                    )
                  : _iconBox(file),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(file.sizeLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      const SizedBox(width: 8),
                      Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(file.timeLabel, style: const TextStyle(color: AppColors.primary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted),
              onPressed: () => Process.run('explorer', ['/select,', file.path]),
              tooltip: 'Show in Explorer',
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(ReceivedFileItem f) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: f.iconColor.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(f.icon, color: f.iconColor, size: 24),
    );
  }
}
