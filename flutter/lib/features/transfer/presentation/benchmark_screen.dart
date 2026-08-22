import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/core/utils/format_utils.dart';
import 'package:hyperdrop_flutter/features/transfer/data/lan_sender_client.dart';

class BenchmarkResult {
  final int fileSizeBytes;
  final double durationSeconds;
  final double averageMBs;
  final double averageMbps;
  final double peakMBs;

  BenchmarkResult({
    required this.fileSizeBytes,
    required this.durationSeconds,
    required this.averageMBs,
    required this.averageMbps,
    required this.peakMBs,
  });
}

class BenchmarkScreen extends ConsumerStatefulWidget {
  final String targetIp;
  final int targetPort;
  final String targetDeviceName;

  const BenchmarkScreen({
    super.key,
    required this.targetIp,
    required this.targetPort,
    required this.targetDeviceName,
  });

  @override
  ConsumerState<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends ConsumerState<BenchmarkScreen> {
  bool _isRunning = false;
  BenchmarkResult? _lastResult;
  String _statusText = 'Ready to benchmark LAN throughput';
  double _currentSpeedMBs = 0.0;
  int _selectedSizeMB = 100;

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _lastResult = null;
      _statusText = 'Generating synthetic ${_selectedSizeMB}MB benchmark payload...';
    });

    try {
      final tempDir = await Directory.systemTemp.createTemp('hd_bench_');
      final benchFile = File('${tempDir.path}/benchmark_${_selectedSizeMB}MB.bin');

      final totalBytes = _selectedSizeMB * 1024 * 1024;
      final raf = await benchFile.open(mode: FileMode.write);
      final dummyBlock = List<int>.filled(1024 * 1024, 0xAA);

      for (int i = 0; i < _selectedSizeMB; i++) {
        await raf.writeFrom(dummyBlock);
      }
      await raf.close();

      setState(() {
        _statusText = 'Streaming ${_selectedSizeMB}MB to ${widget.targetDeviceName}...';
      });

      final startTime = DateTime.now();
      double peakMBs = 0.0;

      await for (final update in LanSenderClient.sendFile(
        file: benchFile,
        targetIp: widget.targetIp,
        targetPort: widget.targetPort,
        targetDeviceName: widget.targetDeviceName,
        enableChecksum: false,
      )) {
        if (update.speedMBs > peakMBs) peakMBs = update.speedMBs;
        setState(() {
          _currentSpeedMBs = update.speedMBs;
        });
      }

      final totalSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      final avgMBs = (_selectedSizeMB / totalSec);
      final avgMbps = avgMBs * 8;

      setState(() {
        _isRunning = false;
        _currentSpeedMBs = 0.0;
        _lastResult = BenchmarkResult(
          fileSizeBytes: totalBytes,
          durationSeconds: totalSec,
          averageMBs: avgMBs,
          averageMbps: avgMbps,
          peakMBs: peakMBs,
        );
        _statusText = 'Benchmark complete!';
      });

      await tempDir.delete(recursive: true);

    } catch (e) {
      setState(() {
        _isRunning = false;
        _statusText = 'Benchmark failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('LAN Performance Benchmark',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Target Peer Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.speed_rounded, color: AppColors.primary, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.targetDeviceName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text('Local Endpoint: ${widget.targetIp}:${widget.targetPort}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Select Benchmark Payload Size:',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [100, 500, 1000].map((mb) {
                          final isSelected = _selectedSizeMB == mb;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: InkWell(
                                onTap: _isRunning ? null : () => setState(() => _selectedSizeMB = mb),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary.withAlpha(30) : AppColors.cardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.cardBorder,
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${mb >= 1000 ? (mb ~/ 1000) : mb} ${mb >= 1000 ? "GB" : "MB"}',
                                      style: TextStyle(
                                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Button
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    onPressed: _isRunning ? null : _runBenchmark,
                    icon: Icon(_isRunning ? Icons.sync_rounded : Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      _isRunning ? 'Benchmarking Throughput...' : 'Start LAN Benchmark',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (_isRunning) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withAlpha(100)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_currentSpeedMBs.toStringAsFixed(1)} MB/s',
                          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                        const SizedBox(height: 8),
                        Text(_statusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(color: AppColors.primary, backgroundColor: AppColors.cardBg),
                      ],
                    ),
                  ),
                ],

                if (_lastResult != null && !_isRunning) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.accentGreen.withOpacity(0.6), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 22),
                            SizedBox(width: 10),
                            Text('LAN Throughput Benchmark Results',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentGreen, fontSize: 15)),
                          ],
                        ),
                        const Divider(color: AppColors.cardBorder, height: 24),
                        _buildMetricRow('Payload Size', FormatUtils.formatBytes(_lastResult!.fileSizeBytes)),
                        _buildMetricRow('Duration', '${_lastResult!.durationSeconds.toStringAsFixed(2)} seconds'),
                        _buildMetricRow('Average Speed', '${_lastResult!.averageMBs.toStringAsFixed(1)} MB/s (${_lastResult!.averageMbps.toStringAsFixed(0)} Mbps)'),
                        _buildMetricRow('Peak Speed', '${_lastResult!.peakMBs.toStringAsFixed(1)} MB/s'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
