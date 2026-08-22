import 'dart:io';
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
    
    String defaultName = 'Windows Laptop';
    DeviceType type = DeviceType.laptop;

    if (kIsWeb) {
      defaultName = 'Web Client';
      type = DeviceType.phone;
    } else {
      try {
        final hostname = Platform.localHostname;
        final username = Platform.environment['USERNAME'] ?? 
                         Platform.environment['USER'] ?? 
                         Platform.environment['LOGNAME'];
        if (username != null && username.isNotEmpty && username.toLowerCase() != 'user') {
          defaultName = '$username\'s PC';
        } else if (hostname.isNotEmpty) {
          defaultName = hostname;
        } else {
          defaultName = 'Windows PC';
        }
      } catch (_) {
        defaultName = 'Windows PC';
      }
      type = DeviceType.laptop;
    }

    final deviceId = 'hd_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';
    final token = 'hd_tok_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';

    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: defaultName,
      deviceType: type,
      osVersion: kIsWeb ? 'Web Engine' : Platform.operatingSystemVersion,
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
