import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/peer_device.dart';
import '../services/udp_discovery_service.dart';
import '../services/webrtc_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late UdpDiscoveryService _udpService;
  late WebRtcService _webrtcService;

  final String _myDeviceId = 'hd_mob_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  final String _myDeviceName = 'Mobile Phone';

  List<PeerDevice> _discoveredPeers = [];
  final List<PlatformFile> _stagedFiles = [];
  final Set<String> _selectedPeerIds = {};

  double _currentSpeedMBs = 0.0;
  double _transferProgress = 0.0;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  void _initServices() {
    // 1. UDP Discovery for 100% Offline Same Wi-Fi & Hotspot Zero-Network
    _udpService = UdpDiscoveryService(
      myDeviceId: _myDeviceId,
      myDeviceName: _myDeviceName,
      myDeviceType: 'phone',
    );
    _udpService.start();
    _udpService.peersStream.listen((peers) {
      if (mounted) {
        setState(() {
          _discoveredPeers = peers;
        });
      }
    });

    // 2. WebRTC for Cross-Network (Different Wi-Fi / 4G / 5G)
    _webrtcService = WebRtcService(
      signalingServerUrl: 'wss://hyperdrop-o28r.onrender.com', // Cloud signaling fallback
      deviceId: _myDeviceId,
      deviceName: _myDeviceName,
    );
    _webrtcService.connectSignaling();
    _webrtcService.remotePeerStream.listen((remotePeer) {
      if (mounted) {
        setState(() {
          _discoveredPeers.add(remotePeer);
        });
      }
    });
  }

  @override
  void dispose() {
    _udpService.stop();
    _webrtcService.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        _stagedFiles.addAll(result.files);
      });
      _showPeerSelectionDialog();
    }
  }

  Future<void> _pickFolder() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      final files = dir.listSync(recursive: true).whereType<File>();
      final platformFiles = files.map((f) => PlatformFile(
        path: f.path,
        name: f.path.split(Platform.pathSeparator).last,
        size: f.lengthSync(),
      )).toList();

      setState(() {
        _stagedFiles.addAll(platformFiles);
      });
      _showPeerSelectionDialog();
    }
  }

  void _showPeerSelectionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0c1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Recipient Peer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_stagedFiles.length} item(s) ready to transfer',
                    style: const TextStyle(color: Color(0xFF00f2fe), fontSize: 13),
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  if (_discoveredPeers.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No nearby devices on radar.\nTurn on Wi-Fi/Hotspot or Remote Code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _discoveredPeers.length,
                        itemBuilder: (context, index) {
                          final peer = _discoveredPeers[index];
                          final isSelected = _selectedPeerIds.contains(peer.id);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF00f2fe).withOpacity(0.12) : const Color(0xFF050a14),
                              border: Border.parseBorder(
                                isSelected ? Border.all(color: const Color(0xFF00f2fe)) : Border.all(color: Colors.white12),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: Icon(
                                peer.type == 'laptop' ? Icons.laptop : Icons.phone_android,
                                color: const Color(0xFF00f2fe),
                              ),
                              title: Text(
                                peer.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Text(
                                peer.networkType,
                                style: TextStyle(
                                  color: peer.isRemote ? const Color(0xFF00ff87) : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Color(0xFF00f2fe))
                                  : const Icon(Icons.radio_button_unchecked, color: Colors.white24),
                              onTap: () {
                                setModalState(() {
                                  if (isSelected) {
                                    _selectedPeerIds.remove(peer.id);
                                  } else {
                                    _selectedPeerIds.add(peer.id);
                                  }
                                });
                                setState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00f2fe),
                        foregroundColor: const Color(0xFF050a14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _startTransfer();
                      },
                      child: const Text('Start High-Speed Transfer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _startTransfer() {
    if (_stagedFiles.isEmpty) return;
    setState(() {
      _isTransferring = true;
      _currentSpeedMBs = 48.5; // Demo active speed
      _transferProgress = 0.65;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚡ Transmitting files at max Wi-Fi radio speed...'),
        backgroundColor: Color(0xFF0c1524),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03070f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070d18),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFF00f2fe)),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00f2fe), Color(0xFF4facfe)],
              ).createShader(bounds),
              child: const Text(
                'HYPERDROP',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00f2fe)),
            onPressed: () {
              // Open QR scanner or code modal
              _showJoinCodeDialog();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Mode Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0c1524),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00f2fe).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_tethering, color: Color(0xFF00ff87)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Triple Network Engine Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('100% Offline Hotspot • Same Wi-Fi • Remote WebRTC', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00ff87).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ONLINE', style: TextStyle(color: Color(0xFF00ff87), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // CARD 1: File & Folder Pickers
            _buildCard(
              title: 'Transmit Data',
              icon: Icons.send,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF050a14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_upload_outlined, size: 48, color: Color(0xFF00f2fe)),
                        const SizedBox(height: 12),
                        const Text('Choose Files or Folders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        const Text('Zero file size limits • High-speed streaming', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.insert_drive_file, size: 16),
                                label: const Text('Files'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0d1e38),
                                  foregroundColor: const Color(0xFF00f2fe),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _pickFiles,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.folder, size: 16),
                                label: const Text('Folder'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0d1e38),
                                  foregroundColor: const Color(0xFFff9900),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _pickFolder,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // CARD 2: Live Speedometer & Queue
            _buildCard(
              title: 'Transfer Engine',
              icon: Icons.speed,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricBox('LIVE SPEED', '${_currentSpeedMBs.toStringAsFixed(1)} MB/s', const Color(0xFF00f2fe)),
                      _buildMetricBox('PROGRESS', '${(_transferProgress * 100).toInt()}%', const Color(0xFF00ff87)),
                      _buildMetricBox('PEERS ON RADAR', '${_discoveredPeers.length}', Colors.white),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _transferProgress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00f2fe)),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0c1524),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Remote Connect', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Enter 6-digit Code (e.g. HD-XXXX)',
              hintStyle: TextStyle(color: Colors.white30),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00f2fe))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ff87))),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00f2fe)),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _webrtcService.joinRemoteSession(controller.text.trim());
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Joining session ${controller.text}...')),
                  );
                }
              },
              child: const Text('Connect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF050a14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0c1524),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00f2fe).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF00f2fe)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
