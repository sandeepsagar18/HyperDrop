class FormatUtils {
  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  static String formatSpeed(double speedBytesPerSec) {
    final mbPerSec = speedBytesPerSec / (1024 * 1024);
    final mbps = mbPerSec * 8;
    return '${mbPerSec.toStringAsFixed(1)} MB/s (${mbps.toStringAsFixed(1)} Mbps)';
  }

  static String formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '${mins}m ${remSecs}s';
  }
}
