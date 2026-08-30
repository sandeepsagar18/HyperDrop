import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as win_wv;
import 'package:webview_flutter/webview_flutter.dart' as mob_wv;

class HyperDropAppView extends StatefulWidget {
  const HyperDropAppView({super.key});

  @override
  State<HyperDropAppView> createState() => _HyperDropAppViewState();
}

class _HyperDropAppViewState extends State<HyperDropAppView> {
  final _winController = win_wv.WebviewController();
  mob_wv.WebViewController? _mobController;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _isServerStarting = false;
  final String _appUrl = 'http://127.0.0.1:3000';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _ensureServerRunning() async {
    if (!Platform.isWindows) return;
    if (_isServerStarting) return;
    _isServerStarting = true;

    // 1. Check if already responding
    bool isAlive = await _pingServer();
    if (isAlive) {
      _isServerStarting = false;
      return;
    }

    // 2. Locate node.exe and server/index.js dynamically
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final username = Platform.environment['USERNAME'] ?? '';

    final candidateNodePaths = [
      '$appDir\\node.exe',
      'node',
      r'C:\Program Files\nodejs\node.exe',
      r'C:\Program Files (x86)\nodejs\node.exe',
      if (username.isNotEmpty)
        'C:\\Users\\$username\\AppData\\Roaming\\nvm\\current\\node.exe',
      if (username.isNotEmpty)
        'C:\\Users\\$username\\AppData\\Local\\Programs\\node\\node.exe',
    ];

    final candidateServerPaths = [
      '$appDir\\server\\index.js',
      '$appDir\\..\\server\\index.js',
      r'D:\HyperDrop\server\index.js',
    ];

    String? foundNode;
    for (final np in candidateNodePaths) {
      if (np == 'node' || File(np).existsSync()) {
        foundNode = np;
        break;
      }
    }

    String? foundServer;
    for (final sp in candidateServerPaths) {
      if (File(sp).existsSync()) {
        foundServer = sp;
        break;
      }
    }

    if (foundNode != null && foundServer != null) {
      try {
        final serverDir = File(foundServer).parent.parent.path;
        
        // Launch Node server silently in background without creating any console window
        final vbsPath = '$serverDir\\Start-Server-Hidden.vbs';
        if (File(vbsPath).existsSync()) {
          Process.start(
            'wscript.exe',
            [vbsPath],
            workingDirectory: serverDir,
            mode: ProcessStartMode.detached,
          );
        } else {
          // Silent fallback via powershell hidden process
          Process.start(
            'powershell.exe',
            [
              '-WindowStyle',
              'Hidden',
              '-NoProfile',
              '-Command',
              'Start-Process -FilePath "$foundNode" -ArgumentList "$foundServer" -WorkingDirectory "$serverDir" -WindowStyle Hidden'
            ],
            mode: ProcessStartMode.detached,
          );
        }
      } catch (e) {
        debugPrint('[SERVER STARTUP ERROR] $e');
      }
    }

    // 3. Poll until server is ready (up to 8 seconds)
    for (int i = 0; i < 16; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _pingServer()) break;
    }
    _isServerStarting = false;
  }

  Future<bool> _pingServer() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 400);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:3000/api/status'));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initWebView() async {
    // 1. Windows Platform Engine
    if (Platform.isWindows) {
      try {
        await _ensureServerRunning();
        await _winController.initialize();
        await _winController.setBackgroundColor(const Color(0xFF030914));
        await _winController.setPopupWindowPolicy(win_wv.WebviewPopupWindowPolicy.allow);

        int loadAttempts = 0;
        _winController.onLoadError.listen((error) async {
          debugPrint('[WEBVIEW LOAD ERROR] $error');
          if (loadAttempts < 3 && mounted) {
            loadAttempts++;
            await Future.delayed(const Duration(seconds: 1));
            await _ensureServerRunning();
            await _winController.loadUrl(_appUrl);
          }
        });

        _winController.loadingState.listen((state) {
          if (state == win_wv.LoadingState.navigationCompleted && mounted) {
            setState(() => _isLoading = false);
          }
        });

        await _winController.loadUrl(_appUrl);

        if (mounted) {
          setState(() => _isInitialized = true);
        }
      } catch (e) {
        debugPrint('[HYPERDROP WINDOWS ERROR] $e');
      }
      return;
    }

    // 2. Android & Mobile Platform Engine - loads the bundled Cyberpunk Web Client
    try {
      final controller = mob_wv.WebViewController()
        ..setJavaScriptMode(mob_wv.JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF030914))
        ..setNavigationDelegate(
          mob_wv.NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
            onWebResourceError: (error) {
              debugPrint('[HYPERDROP MOBILE ERROR] ${error.description}');
            },
          ),
        );

      try {
        await controller.loadFlutterAsset('assets/web/index.html');
      } catch (_) {
        await controller.loadRequest(Uri.parse('http://127.0.0.1:3000'));
      }

      _mobController = controller;
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[HYPERDROP MOBILE INIT ERROR] $e');
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      _winController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF030914),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF00F2FE).withOpacity(0.12),
                  border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.4)),
                ),
                child: const Icon(Icons.bolt, color: Color(0xFF00F2FE), size: 36),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                color: Color(0xFF00F2FE),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Starting HyperDrop Engine...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030914),
      body: Stack(
        children: [
          if (Platform.isWindows)
            win_wv.Webview(_winController)
          else
            mob_wv.WebViewWidget(controller: _mobController!),
          if (_isLoading)
            Container(
              color: const Color(0xFF030914),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00F2FE),
                  strokeWidth: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
