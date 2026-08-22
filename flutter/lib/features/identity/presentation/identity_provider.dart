import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/identity_service.dart';
import '../domain/models/device_identity.dart';

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService();
});

final currentIdentityProvider = StateNotifierProvider<IdentityNotifier, DeviceIdentity>((ref) {
  final service = ref.watch(identityServiceProvider);
  return IdentityNotifier(service);
});

class IdentityNotifier extends StateNotifier<DeviceIdentity> {
  final IdentityService _service;

  IdentityNotifier(this._service) : super(_service.currentIdentity);

  void renameDevice(String newName) {
    _service.updateDeviceName(newName);
    state = _service.currentIdentity;
  }

  void refreshSessionToken() {
    _service.regenerateSessionToken();
    state = _service.currentIdentity;
  }
}
