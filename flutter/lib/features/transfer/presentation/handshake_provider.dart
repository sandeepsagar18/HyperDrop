import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../identity/presentation/identity_provider.dart';
import '../data/handshake_service.dart';
import '../domain/models/handshake_model.dart';

final handshakeServiceProvider = Provider<HandshakeService>((ref) {
  final identity = ref.watch(currentIdentityProvider);
  final service = HandshakeService(identity: identity);
  ref.onDispose(() => service.dispose());
  return service;
});

final incomingHandshakeStreamProvider = StreamProvider<HandshakeRequest>((ref) {
  final service = ref.watch(handshakeServiceProvider);
  return service.incomingRequestsStream;
});
