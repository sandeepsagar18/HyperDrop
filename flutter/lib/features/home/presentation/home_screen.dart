import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hyperdrop_flutter/core/config/app_config.dart';
import 'package:hyperdrop_flutter/core/theme/app_colors.dart';
import 'package:hyperdrop_flutter/core/theme/app_theme.dart';
import 'package:hyperdrop_flutter/core/utils/format_utils.dart';
import 'package:hyperdrop_flutter/features/discovery/domain/models/device_model.dart';
import 'package:hyperdrop_flutter/features/discovery/presentation/discovery_provider.dart';
import 'package:hyperdrop_flutter/features/discovery/presentation/qr_connection_dialog.dart';
import 'package:hyperdrop_flutter/features/discovery/presentation/radar_widget.dart';
import 'package:hyperdrop_flutter/features/identity/presentation/identity_provider.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/handshake_dialog.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/handshake_provider.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/benchmark_screen.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/transfer_manager_provider.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/speed_gauge_widget.dart';
import 'package:hyperdrop_flutter/features/transfer/presentation/received_files_panel.dart';
import 'package:hyperdrop_flutter/features/transfer/domain/models/transfer_model.dart';
import 'package:path/path.dart' as p;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedDeviceId;
  List<PlatformFile> _stagedFiles = [];
  double _liveSpeedMBs = 0;
  double _peakSpeedMBs = 0;
  double _totalMovedMB = 0;

  Timer? _vaultRefreshTimer;

  @override
  void initState() {
    super.initState();
    ref.read(lanHttpReceiverServerProvider);
    _ensureNodeServerRunning();
    _vaultRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) ref.invalidate(receivedFilesProvider);
    });
  }

  void _ensureNodeServerRunning() {
    // Ping port 3000 to ensure Node.js server is always alive
    Process.run('cmd', ['/c', 'netstat -ano | findstr :3000']).then((result) {
      if (!result.stdout.toString().contains('LISTENING')) {
        Process.start('node', ['server/index.js'], workingDirectory: r'D:\hyperdrop', mode: ProcessStartMode.detached);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _vaultRefreshTimer?.cancel();
    super.dispose();
  }

  void _showRenameDialog() {
    final id = ref.read(currentIdentityProvider);
    final ctrl = TextEditingController(text: id.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('Rename Device', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set a custom identity for this device visible to peers on the local network.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Laptop (SandeepSagar18)',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.cardBorder, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_rounded, size: 16),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                ref.read(currentIdentityProvider.notifier).renameDevice(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            label: const Text('Save Identity', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showQrDialog() async {
    final identity = ref.read(currentIdentityProvider);
    String localIp = '192.168.29.137';
    try {
      localIp = await ref.read(localIpProvider.future);
      if (localIp == '127.0.0.1') {
        localIp = '192.168.29.137';
      }
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => QrConnectionDialog(identity: identity, localIp: localIp),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) setState(() => _stagedFiles = result.files);
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) setState(() => _stagedFiles = result.files);
  }

  Future<void> _sendFiles() async {
    if (_stagedFiles.isEmpty) { await _pickFiles(); }
    final peers = ref.read(udpDiscoveryEngineProvider).discoveredPeers;
    if (peers.isEmpty) {
      _showSnack('No nearby devices found. Open HyperDrop on the other device.', AppColors.accentRed);
      return;
    }
    final target = _selectedDeviceId != null
        ? peers.firstWhere((p) => p.deviceId == _selectedDeviceId, orElse: () => peers.first)
        : peers.first;

    setState(() { _liveSpeedMBs = 0; });

    await ref.read(activeTransfersProvider.notifier).sendPickedFilesToPeer(
      files: _stagedFiles,
      targetIp: target.ipAddress,
      targetPort: target.port,
      targetDeviceName: target.deviceName,
    );
    setState(() { _stagedFiles = []; });
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _formatBytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(currentIdentityProvider);
    final peersAsync = ref.watch(discoveredPeersStreamProvider);
    final activeTransfers = ref.watch(activeTransfersProvider);
    final peers = peersAsync.valueOrNull ?? [];

    // Update live speed from active transfers
    if (activeTransfers.isNotEmpty) {
      final maxSpeed = activeTransfers
          .where((t) => t.status == TransferStatus.transferring)
          .fold(0.0, (s, t) => s + t.speedMBs);
      if (maxSpeed > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {
            _liveSpeedMBs = maxSpeed;
            if (maxSpeed > _peakSpeedMBs) _peakSpeedMBs = maxSpeed;
            _totalMovedMB = activeTransfers.fold(0.0, (s, t) => s + t.bytesTransferred / (1024 * 1024));
          });
        });
      }
    }

    ref.listen(incomingHandshakeStreamProvider, (_, next) {
      next.whenData((req) {
        // Automatically accept incoming transfers without popup interruption
        ref.read(handshakeServiceProvider).acceptTransfer(req.requestId);
      });
    });

    final activeCount = activeTransfers.where((t) => t.status == TransferStatus.transferring).length;
    final isDarkMode = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.background : const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // ── HEADER ──────────────────────────────────────────────
          _buildHeader(identity.deviceName, isDarkMode),

          // ── SCROLLABLE MAIN CONTENT (NO OVERFLOW IN HALF SCREEN) ─
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── RADAR ───────────────────────────────────────────────
                  SizedBox(
                    height: 240,
                    child: RadarWidget(peers: peers, selfName: identity.deviceName),
                  ),

                  // ── 3-COLUMN MAIN BODY (EQUAL SIZE COLUMNS ACROSS SCREEN) ─
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    height: 500,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = max(1080.0, constraints.maxWidth);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: availableWidth,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // LEFT: Transmit Data (Equal 1/3)
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? AppColors.surface : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0), width: 1),
                                    ),
                                    child: _buildTransmitPanel(peers),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // MIDDLE: Live Transfer Engine (Equal 1/3)
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? AppColors.surface : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0), width: 1),
                                    ),
                                    child: _buildTransferEngine(activeTransfers, activeCount),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // RIGHT: Data Vault (Equal 1/3)
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? AppColors.surface : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0), width: 1),
                                    ),
                                    child: _buildVaultPanel(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── FOOTER SECTION: FEATURE SHOWCASE & BRANDING ────────
                  _buildFooter(isDarkMode),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FOOTER WIDGET ───────────────────────────────────────────────
  Widget _buildFooter(bool isDarkMode) {
    final cardBg = isDarkMode ? AppColors.surface : Colors.white;
    final borderColor = isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of Footer
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withAlpha(90), width: 1),
                ),
                child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HyperDrop — High-Speed Hybrid Local & P2P Engine',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'HyperDrop Is A Peer-To-Peer File Transfer Engine Designed For Fast, Seamless Cross-Device Sharing.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 20),

          // 4 Feature Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final cardWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildFeatureTile(
                    width: cardWidth,
                    icon: Icons.wifi_rounded,
                    iconColor: AppColors.primary,
                    title: '⚡ Local Wi-Fi Transfer',
                    description: 'Transfer files directly between devices connected to the same Wi-Fi network — without uploading your files to a cloud server.',
                    isDarkMode: isDarkMode,
                  ),
                  _buildFeatureTile(
                    width: cardWidth,
                    icon: Icons.phone_android_rounded,
                    iconColor: AppColors.secondary,
                    title: '📱 Mobile Hotspot Mode',
                    description: 'No router? No problem. Connect devices through a mobile hotspot and transfer files directly.',
                    isDarkMode: isDarkMode,
                  ),
                  _buildFeatureTile(
                    width: cardWidth,
                    icon: Icons.speed_rounded,
                    iconColor: const Color(0xFF38BDF8),
                    title: '🚀 High-Speed File Transfer Engine',
                    description: 'HyperDrop is designed to utilize the available local network bandwidth for fast file transfers, including large files.',
                    isDarkMode: isDarkMode,
                  ),
                  _buildFeatureTile(
                    width: cardWidth,
                    icon: Icons.security_rounded,
                    iconColor: const Color(0xFFA855F7),
                    title: '🔒 Direct & Private',
                    description: 'Whenever possible, files are transferred directly between the connected devices rather than being routed through a central storage server.',
                    isDarkMode: isDarkMode,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 22),
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 16),

          // Bottom Signature bar with Centered Feedback & Email (Left, Center, Right aligned)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              if (isNarrow) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.hub_rounded, color: AppColors.primary, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'HyperDrop Engine — High-Speed Local Wi-Fi & Hotspot File Transfer Engine',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _openFeedbackMail,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7).withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.feedback_outlined, color: Color(0xFF38BDF8), size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Send Feedback',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('Built With ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                          Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 14),
                          Text(' By Sandeep', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  // EXTREME LEFT: Engine info
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.hub_rounded, color: AppColors.primary, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'HyperDrop Engine — High-Speed Local Wi-Fi & Hotspot File Transfer Engine',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  // SPACER TO CENTER
                  const Spacer(),

                  // EXACT CENTER: Send Feedback Button
                  InkWell(
                    onTap: _openFeedbackMail,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF0284C7).withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.feedback_outlined, color: Color(0xFF38BDF8), size: 14),
                          SizedBox(width: 6),
                          Text(
                            'Send Feedback',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // SPACER TO EXTREME RIGHT
                  const Spacer(),

                  // EXTREME RIGHT: Author branding
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('Built With ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                        Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 14),
                        Text(' By Sandeep', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTile({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isDarkMode,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.cardBg : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _openFeedbackMail() {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.feedbackEmail,
      queryParameters: {
        'subject': AppConfig.feedbackSubject,
        'body': AppConfig.feedbackBody,
      },
    );
    final mailUrl = uri.toString();
    Process.run('cmd', ['/c', 'start', '', mailUrl]);
  }

  // ── HEADER ─────────────────────────────────────────────────────
  Widget _buildHeader(String deviceName, bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 1180;
        final isUltraNarrow = width < 550;
        final hideSubtitle = width < 750;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isUltraNarrow ? 8 : (isCompact ? 12 : 24),
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.background : Colors.white,
            border: Border(bottom: BorderSide(color: isDarkMode ? AppColors.cardBorder : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              // EXTREME LEFT: HyperDrop Branding & Subtitle
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'HyperDrop',
                    style: TextStyle(
                      color: isDarkMode ? AppColors.primary : const Color(0xFF0284C7),
                      fontWeight: FontWeight.w900,
                      fontSize: isUltraNarrow ? 16 : (isCompact ? 18 : 22),
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!hideSubtitle) ...[
                    const SizedBox(width: 10),
                    const Text(
                      'High-Speed Transfer Engine',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ],
              ),

              // SPACER OR MIN GAP
              const Spacer(),

              // EXTREME RIGHT: Navigation & Action Buttons (Adaptive text / icon mode)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderBtn(
                    icon: Icons.refresh_rounded,
                    label: 'Scan Devices',
                    iconOnly: isCompact,
                    onTap: () async {
                      ref.read(udpDiscoveryEngineProvider).forceScan();
                    },
                  ),
                  SizedBox(width: isUltraNarrow ? 4 : (isCompact ? 6 : 10)),
                  _HeaderBtn(
                    icon: Icons.edit_outlined,
                    label: 'Rename Device',
                    iconOnly: isCompact,
                    onTap: _showRenameDialog,
                  ),
                  SizedBox(width: isUltraNarrow ? 4 : (isCompact ? 6 : 10)),
                  _HeaderBtn(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Connect Phone QR',
                    iconOnly: isCompact,
                    onTap: _showQrDialog,
                  ),
                  SizedBox(width: isUltraNarrow ? 4 : (isCompact ? 6 : 10)),
                  _HeaderBtn(
                    icon: Icons.speed_rounded,
                    label: 'Network Diagnostics',
                    iconOnly: isCompact,
                    onTap: () {
                      final peers = ref.read(udpDiscoveryEngineProvider).discoveredPeers;
                      final targetIp = peers.isNotEmpty ? peers.first.ipAddress : '127.0.0.1';
                      final targetPort = peers.isNotEmpty ? peers.first.port : 3000;
                      final targetName = peers.isNotEmpty ? peers.first.deviceName : 'Local Loopback Engine';

                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => BenchmarkScreen(
                          targetIp: targetIp,
                          targetPort: targetPort,
                          targetDeviceName: targetName,
                        ),
                      ));
                    },
                  ),
                  SizedBox(width: isUltraNarrow ? 4 : (isCompact ? 6 : 10)),
                  _HeaderBtn(
                    icon: Icons.feedback_outlined,
                    label: 'Feedback',
                    iconOnly: isCompact,
                    onTap: _openFeedbackMail,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── RADAR STATUS BAR ────────────────────────────────────────────
  Widget _buildRadarStatus(int peerCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8,
            decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          const Icon(Icons.wifi_tethering_rounded, color: AppColors.primary, size: 14),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Hybrid Radar: Monitoring Local Wi-Fi, Hotspots, and Remote WebRTC Peers',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── LEFT: TRANSMIT DATA ─────────────────────────────────────────
  Widget _buildTransmitPanel(List<DeviceModel> peers) {
    final totalBytes = _stagedFiles.fold(0, (s, f) => s + f.size);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Transmit Data',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder)),
                  child: Text('${_stagedFiles.length} file(s) staged',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
              ],
            ),
          const SizedBox(height: 14),

          // Drop zone
          GestureDetector(
            onTap: _pickFiles,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _stagedFiles.isNotEmpty ? AppColors.primary : AppColors.cardBorder,
                  style: BorderStyle.solid,
                  width: 1.5,
                ),
              ),
              child: _stagedFiles.isEmpty
                  ? const Column(children: [
                      Icon(Icons.upload_file_rounded, color: AppColors.textMuted, size: 36),
                      SizedBox(height: 10),
                      Text('Drag & Drop Files or Folders',
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 4),
                      Text('No size limits • Direct LAN P2P DataChannel',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ])
                  : Column(children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 32),
                      const SizedBox(height: 8),
                      Text('${_stagedFiles.length} files • ${_formatBytes(totalBytes)}',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('Tap to change', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
            ),
          ),
          // Staged Files list with remove button
          if (_stagedFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                itemCount: _stagedFiles.length,
                separatorBuilder: (_, __) => const Divider(color: AppColors.cardBorder, height: 1),
                itemBuilder: (ctx, idx) {
                  final f = _stagedFiles[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_rounded, color: AppColors.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatBytes(f.size),
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        // Remove button for each file
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _stagedFiles.removeAt(idx);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.accentRed.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.accentRed.withAlpha(60)),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: AppColors.accentRed,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _TransmitBtn(icon: Icons.insert_drive_file_rounded, label: 'Choose Files', onTap: _pickFiles)),
              const SizedBox(width: 10),
              Expanded(child: _TransmitBtn(icon: Icons.folder_rounded, label: 'Choose Folder', onTap: _pickFolder)),
            ],
          ),
          const SizedBox(height: 12),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _stagedFiles.isNotEmpty ? AppColors.primary : AppColors.cardBg,
                foregroundColor: _stagedFiles.isNotEmpty ? Colors.black : AppColors.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _sendFiles,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                peers.isEmpty ? 'Send (No peers found)' : 'Send to Device',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

            // Peer selector
            if (peers.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Target Device:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 6),
              ...peers.map((dev) => _PeerTile(
                device: dev,
                selected: _selectedDeviceId == dev.deviceId,
                onTap: () => setState(() {
                  _selectedDeviceId = _selectedDeviceId == dev.deviceId ? null : dev.deviceId;
                }),
              )),
            ],
          ],
        ),
      ),
    );
  }

  // ── MIDDLE: LIVE TRANSFER ENGINE ────────────────────────────────
  Widget _buildTransferEngine(List transfers, int activeCount) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Live Transfer Engine',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withAlpha(80)),
                ),
                child: const Text('Direct LAN Stream',
                  style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Gauge
          Center(child: SpeedGaugeWidget(speedMBs: _liveSpeedMBs)),
          const SizedBox(height: 28),

          // Stats row
          Row(
            children: [
              Expanded(child: _StatBox(label: 'PEAK SPEED', value: '${_peakSpeedMBs.toStringAsFixed(1)} MB/s')),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(label: 'ACTIVE CHANNELS', value: '$activeCount STREAMING')),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(label: 'TOTAL MOVED', value: '${_totalMovedMB.toStringAsFixed(2)} MB')),
            ],
          ),
          const SizedBox(height: 16),

          // Transfer history header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Transfer History & Active Queue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => ref.read(activeTransfersProvider.notifier).clearFinished(),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                    child: const Text('Clear Finished', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: activeCount > 0 ? AppColors.accentGreen.withAlpha(30) : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$activeCount Active',
                      style: TextStyle(
                        color: activeCount > 0 ? AppColors.accentGreen : AppColors.textMuted,
                        fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Transfer list
          Expanded(
            child: transfers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sync_rounded, color: AppColors.textMuted.withAlpha(100), size: 40),
                        const SizedBox(height: 10),
                        const Text('No active transfers', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: transfers.length,
                    itemBuilder: (_, i) => _TransferRow(transfer: transfers[i]),
                  ),
          ),
        ],
      ),
    );
  }

  // ── RIGHT: DATA VAULT ───────────────────────────────────────────
  Widget _buildVaultPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer(builder: (ctx, ref, _) {
            final filesAsync = ref.watch(receivedFilesProvider);
            final count = filesAsync.valueOrNull?.length ?? 0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Data Vault & Storage',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('$count item(s) in Vault',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            );
          }),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Offline Saved Vault',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              TextButton(
                onPressed: () => ref.invalidate(receivedFilesProvider),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                child: const Text('Refresh', style: TextStyle(color: AppColors.primary, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: Consumer(
              builder: (ctx, ref, _) {
                final filesAsync = ref.watch(receivedFilesProvider);
                return filesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.accentRed)),
                  data: (files) {
                    if (files.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_rounded, color: AppColors.textMuted.withAlpha(100), size: 40),
                            const SizedBox(height: 10),
                            const Text('No files received yet', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.cardBorder, height: 1),
                      itemBuilder: (_, i) => _VaultRow(file: files[i]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── SMALL HELPER WIDGETS ────────────────────────────────────────────

class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool iconOnly;
  const _HeaderBtn({required this.icon, required this.label, required this.onTap, this.iconOnly = false});

  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: widget.iconOnly ? 10 : 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _isPressed
                  ? AppColors.primary.withAlpha(40)
                  : _isHovered
                      ? AppColors.primary.withAlpha(25)
                      : AppColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isHovered ? AppColors.primary : AppColors.primary.withAlpha(90),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(50),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: AppColors.primary, size: 15),
                if (!widget.iconOnly) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
}

class _TransmitBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TransmitBtn({required this.icon, required this.label, required this.onTap});

  @override
  State<_TransmitBtn> createState() => _TransmitBtnState();
}

class _TransmitBtnState extends State<_TransmitBtn> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed
                ? AppColors.primary.withAlpha(35)
                : _isHovered
                    ? AppColors.primary.withAlpha(18)
                    : AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? AppColors.primary : AppColors.cardBorder,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(40),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, color: _isHovered ? AppColors.primary : AppColors.textSecondary, size: 16),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                color: _isHovered ? AppColors.primary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PeerTile extends StatefulWidget {
  final DeviceModel device;
  final bool selected;
  final VoidCallback onTap;
  const _PeerTile({required this.device, required this.selected, required this.onTap});

  @override
  State<_PeerTile> createState() => _PeerTileState();
}

class _PeerTileState extends State<_PeerTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.primary.withAlpha(25)
                : _isHovered
                    ? AppColors.cardBg.withAlpha(220)
                    : AppColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? AppColors.primary
                  : _isHovered
                      ? AppColors.primary.withAlpha(120)
                      : AppColors.cardBorder,
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(
              widget.device.deviceType == DeviceType.phone ? Icons.phone_android_rounded : Icons.laptop_mac_rounded,
              color: widget.selected ? AppColors.primary : AppColors.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.device.deviceName,
                style: TextStyle(
                  color: widget.selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              widget.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: widget.selected ? AppColors.primary : AppColors.textMuted,
              size: 16,
            ),
          ]),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _TransferRow extends ConsumerWidget {
  final dynamic transfer;
  const _TransferRow({required this.transfer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = transfer.direction == TransferDirection.outgoing;
    final isDone = transfer.status == TransferStatus.completed;
    final isFail = transfer.status == TransferStatus.failed;
    final isCancelled = transfer.status == TransferStatus.cancelled;
    final isStreaming = transfer.status == TransferStatus.transferring;

    // elapsedSeconds is frozen in the model once transfer ends — no ever-growing clock
    final elapsed = transfer.elapsedSeconds;
    final String timeStr;
    if (isStreaming && transfer.etaSeconds > 0) {
      timeStr = '${transfer.etaSeconds}s left • ${elapsed}s elapsed';
    } else if (isDone) {
      timeStr = 'Done in ${elapsed}s';
    } else if (isCancelled) {
      timeStr = 'Cancelled at ${elapsed}s';
    } else if (isFail) {
      timeStr = 'Failed at ${elapsed}s';
    } else {
      timeStr = '${elapsed}s';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDone ? AppColors.accentGreen.withAlpha(60) : AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: isOut ? AppColors.primary : AppColors.secondary, size: 14),
          const SizedBox(width: 6),
          Expanded(child: Text(transfer.fileName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
          Text('${transfer.percent}%', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (isStreaming) ...[
            GestureDetector(
              onTap: () => ref.read(activeTransfersProvider.notifier).cancelTransfer(transfer.transferId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.accentRed.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                child: const Text('Cancel', style: TextStyle(color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                ref.read(activeTransfersProvider.notifier).restartTransfer(transfer, transfer.fileName);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                child: const Text('Restart', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          if (isDone || isCancelled || isFail) ...[
            GestureDetector(
              onTap: () {
                ref.read(activeTransfersProvider.notifier).restartTransfer(transfer, transfer.fileName);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                child: const Text('Restart', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: transfer.progress,
          backgroundColor: AppColors.background,
          color: isDone ? AppColors.accentGreen : (isFail || isCancelled) ? AppColors.accentRed : AppColors.primary,
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${FormatUtils.formatBytes(transfer.bytesTransferred)} • $timeStr',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          if (isStreaming)
            Text('${transfer.speedMBs.toStringAsFixed(1)} MB/s',
              style: const TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
          if (isDone) const Text('✓ Done', style: TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
          if (isCancelled) const Text('✕ Cancelled', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          if (isFail) Text(transfer.errorMessage ?? '✕ Failed', style: const TextStyle(color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }
}

class _VaultRow extends ConsumerWidget {
  final ReceivedFileItem file;
  const _VaultRow({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        // Thumbnail / icon
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: file.isImage
              ? Image.file(File(file.path), width: 36, height: 36, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _icon(file))
              : _icon(file),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${file.sizeLabel} • ${file.timeLabel}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ),
        // View button
        _VaultBtn(
          label: 'View',
          icon: Icons.visibility_rounded,
          color: AppColors.primary,
          onTap: () => Process.run('explorer', ['/select,', file.path]),
        ),
        const SizedBox(width: 4),
        // Open button
        _VaultBtn(
          label: 'Open',
          icon: Icons.open_in_new_rounded,
          color: AppColors.accentGreen,
          onTap: () => Process.run('explorer', [file.path]),
        ),
        const SizedBox(width: 4),
        // Delete button
        _VaultBtn(
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          color: AppColors.accentRed,
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                title: const Text('Delete File?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                content: Text('Are you sure you want to delete "${file.name}" from your vault?',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              try {
                final f = File(file.path);
                if (await f.exists()) {
                  await f.delete();
                }
                ref.invalidate(receivedFilesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted "${file.name}"'),
                      backgroundColor: AppColors.surface,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.accentRed),
                  );
                }
              }
            }
          },
        ),
      ]),
    );
  }

  Widget _icon(ReceivedFileItem f) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: f.iconColor.withAlpha(30), borderRadius: BorderRadius.circular(6)),
      child: Icon(f.icon, color: f.iconColor, size: 18),
    );
  }
}

class _VaultBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _VaultBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  State<_VaultBtn> createState() => _VaultBtnState();
}

class _VaultBtnState extends State<_VaultBtn> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isPressed
                ? widget.color.withAlpha(50)
                : _isHovered
                    ? widget.color.withAlpha(35)
                    : widget.color.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered ? widget.color : widget.color.withAlpha(60),
              width: _isHovered ? 1.2 : 1.0,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, color: widget.color, size: 12),
            const SizedBox(width: 4),
            Text(widget.label, style: TextStyle(color: widget.color, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}

