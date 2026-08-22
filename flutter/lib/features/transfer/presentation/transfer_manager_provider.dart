import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../identity/presentation/identity_provider.dart';
import '../data/handshake_service.dart';
import '../data/lan_http_receiver_server.dart';
import '../data/lan_sender_client.dart';
import '../domain/models/transfer_model.dart';
import 'handshake_provider.dart';

final lanHttpReceiverServerProvider = Provider<LanHttpReceiverServer>((ref) {
  final identity = ref.watch(currentIdentityProvider);
  final handshakeService = ref.watch(handshakeServiceProvider);
  final server = LanHttpReceiverServer(
    identity: identity,
    handshakeService: handshakeService,
  );
  
  server.startServer();
  ref.onDispose(() => server.stop());
  return server;
});

final activeTransfersProvider = StateNotifierProvider<TransferManagerNotifier, List<TransferModel>>((ref) {
  final handshakeService = ref.watch(handshakeServiceProvider);
  return TransferManagerNotifier(handshakeService: handshakeService);
});

class TransferManagerNotifier extends StateNotifier<List<TransferModel>> {
  final HandshakeService handshakeService;

  TransferManagerNotifier({required this.handshakeService}) : super([]);

  Future<void> sendPickedFilesToPeer({
    required List<PlatformFile> files,
    required String targetIp,
    required int targetPort,
    required String targetDeviceName,
  }) async {
    for (final platformFile in files) {
      if (platformFile.path == null) continue;
      final file = File(platformFile.path!);

      await for (final update in LanSenderClient.sendFile(
        file: file,
        targetIp: targetIp,
        targetPort: targetPort,
        targetDeviceName: targetDeviceName,
      )) {
        _upsertTransfer(update);
      }
    }
  }

  void cancelTransfer(String transferId) {
    LanSenderClient.cancelTransfer(transferId);
    state = state.map((t) {
      if (t.transferId == transferId) {
        return t.copyWith(
          status: TransferStatus.cancelled,
          speedMBs: 0.0,
          speedMbps: 0.0,
          errorMessage: 'Transfer cancelled by user',
          endTime: DateTime.now(), // freeze timer here
        );
      }
      return t;
    }).toList();
  }

  Future<void> restartTransfer(TransferModel transfer, [String? fallbackPath]) async {
    cancelTransfer(transfer.transferId);
    
    final path = transfer.filePath ?? fallbackPath;
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (!await file.exists()) return;

    await for (final update in LanSenderClient.sendFile(
      file: file,
      targetIp: transfer.peerIp.isNotEmpty ? transfer.peerIp : '127.0.0.1',
      targetPort: 3000,
      targetDeviceName: transfer.peerName.isNotEmpty ? transfer.peerName : 'Nearby Device',
    )) {
      _upsertTransfer(update);
    }
  }

  void clearFinished() {
    state = state.where((t) => t.status == TransferStatus.transferring || t.status == TransferStatus.connecting).toList();
  }

  void _upsertTransfer(TransferModel transfer) {
    final index = state.indexWhere((t) => t.transferId == transfer.transferId);
    if (index >= 0) {
      final updatedList = List<TransferModel>.from(state);
      updatedList[index] = transfer;
      state = updatedList;
    } else {
      state = [transfer, ...state];
    }
  }
}
