import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric Authentication Service
/// Handles Face ID / Fingerprint authentication for iOS and Android
class BiometricService {
  static BiometricService? _instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  BiometricService._();
  
  static BiometricService get instance {
    _instance ??= BiometricService._();
    return _instance!;
  }

  /// Check if device supports biometric authentication
  Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false;
    
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Check if biometrics are enrolled on the device
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Check if Face ID is available
  Future<bool> hasFaceId() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }

  /// Check if Fingerprint is available
  Future<bool> hasFingerprint() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint) ||
           biometrics.contains(BiometricType.strong) ||
           biometrics.contains(BiometricType.weak);
  }

  /// Static method to check if biometrics are available
  static Future<bool> isAvailable() async {
    return await instance.isDeviceSupported() && await instance.canCheckBiometrics();
  }

  /// Get a user-friendly description of available biometric
  Future<String> getBiometricTypeName() async {
    if (await hasFaceId()) {
      return 'Face ID';
    } else if (await hasFingerprint()) {
      return 'Fingerprint';
    }
    return 'Biometric';
  }
  
  /// Static method to get biometric type name
  static Future<String> getTypeName() async {
    return await instance.getBiometricTypeName();
  }

  /// Authenticate user with biometrics
  /// Returns true if authentication successful, false otherwise
  Future<bool> authenticate({
    String reason = 'Please authenticate to access Ghostty',
  }) async {
    if (kIsWeb) return false;
    
    final isSupported = await isDeviceSupported();
    final canCheck = await canCheckBiometrics();
    
    if (!isSupported || !canCheck) {
      return false;
    }

    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: ${e.message}');
      return false;
    }
  }

  /// Authenticate with fallback to device credentials (PIN/Pattern/Password)
  Future<bool> authenticateWithFallback({
    String reason = 'Please authenticate to access Ghostty',
  }) async {
    if (kIsWeb) return false;
    
    final isSupported = await isDeviceSupported();
    if (!isSupported) return false;

    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,  // Allow PIN/Pattern fallback
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Auth error: ${e.message}');
      return false;
    }
  }
}
