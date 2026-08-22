import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/models/device_identity.dart';
import '../../discovery/domain/models/device_model.dart';

class IdentityService {
  DeviceIdentity? _identity;

  DeviceIdentity get currentIdentity {
    _identity ??= _generateIdentity();
    return _identity!;
  }

  DeviceIdentity _generateIdentity() {
    final rand = Random();
    final randomSuffix = rand.nextInt(9999).toString().padLeft(4, '0');
    
    String defaultName = 'Laptop (SandeepSagar18)';
    DeviceType type = DeviceType.phone;

    if (kIsWeb) {
      defaultName = 'Phone Web Client';
      type = DeviceType.phone;
    } else {
      defaultName = 'Laptop (SandeepSagar18)';
      type = DeviceType.laptop;
    }

    final deviceId = 'hd_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';
    final token = 'hd_tok_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';

    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: defaultName,
      deviceType: type,
      osVersion: kIsWeb ? 'Web Engine' : 'Native OS',
      token: token,
    );
  }

  void updateDeviceName(String newName) {
    if (newName.trim().isNotEmpty) {
      _identity = currentIdentity.copyWith(deviceName: newName.trim());
    }
  }

  String regenerateSessionToken() {
    final rand = Random();
    final newToken = 'hd_tok_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';
    _identity = currentIdentity.copyWith(token: newToken);
    return newToken;
  }
}
