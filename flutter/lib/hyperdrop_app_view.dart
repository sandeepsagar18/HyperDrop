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
  final String _appUrl = 'http://127.0.0.1:3000';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _ensureServerRunning() async {
    if (!Platform.isWindows) return;
    try {
      // Check if server is already responding
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 600);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:3000/api/status'));
      final res = await req.close();
      if (res.statusCode == 200) {
        return; // Server is already alive!
      }
    } catch (_) {
      // Server not responding, spawn it automatically
      try {
        const repoPath = r'D:\HyperDrop';
        if (Directory(repoPath).existsSync()) {
          Process.start('npm.cmd', ['start'],
              workingDirectory: repoPath,
              mode: ProcessStartMode.detached);
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        debugPrint('[SERVER AUTOSTART ERROR] $e');
      }
    }
  }

  Future<void> _initWebView() async {
    // 1. Windows Platform Engine
    if (Platform.isWindows) {
      try {
        await _ensureServerRunning();
        await _winController.initialize();
        await _winController.setBackgroundColor(const Color(0xFF030914));
        await _winController.setPopupWindowPolicy(win_wv.WebviewPopupWindowPolicy.deny);
        await _winController.loadUrl(_appUrl);

        _winController.loadingState.listen((state) {
          if (state == win_wv.LoadingState.navigationCompleted && mounted) {
            setState(() => _isLoading = false);
          }
        });

        if (mounted) {
          setState(() => _isInitialized = true);
        }
      } catch (e) {
        debugPrint('[HYPERDROP WINDOWS ERROR] $e');
      }
      return;
    }

    // 2. Android & Mobile Platform Engine - loads the full bundled Cyberpunk Web Client
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

      // Load bundled Cyberpunk Web Client from local assets (works offline on all phones!)
      try {
        await controller.loadFlutterAsset('assets/web/index.html');
      } catch (_) {
        await controller.loadRequest(Uri.parse('http://192.168.29.137:3000'));
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
