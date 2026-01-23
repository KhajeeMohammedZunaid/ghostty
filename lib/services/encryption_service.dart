import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// A secure encryption service for Ghost Journal
/// Uses AES-256-CBC encryption with PBKDF2 key derivation
class EncryptionService {
  static EncryptionService? _instance;
  late Uint8List _aesKey;
  bool _initialized = false;

  EncryptionService._();

  static EncryptionService get instance {
    _instance ??= EncryptionService._();
    return _instance!;
  }

  bool get isInitialized => _initialized;

  /// Get key as base64 for isolate encryption
  String get keyBase64 {
    if (!_initialized) throw Exception('EncryptionService not initialized');
    return base64Encode(_aesKey);
  }

  /// Initialize with a PIN-derived key using PBKDF2
  void initialize(String pin) {
    _aesKey = _deriveKey(pin);
    _initialized = true;
  }

  /// Derive a 256-bit AES key from PIN using PBKDF2-like derivation
  Uint8List _deriveKey(String pin) {
    const salt = 'GhostJournal_AES256_Salt_2024_Secure';
    const iterations = 100000;

    List<int> key = utf8.encode(pin + salt);
    for (var i = 0; i < iterations; i++) {
      key = sha256.convert(key).bytes;
    }
    return Uint8List.fromList(key.sublist(0, 32));
  }

  /// Encrypt string data using AES-256-CBC
  String encrypt(String plaintext) {
    if (!_initialized) throw Exception('EncryptionService not initialized');

    final key = enc.Key(_aesKey);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final randomIv = enc.IV.fromSecureRandom(16);
    final encrypted = encrypter.encrypt(plaintext, iv: randomIv);

    return '${randomIv.base64}:${encrypted.base64}';
  }

  /// Decrypt string data using AES-256-CBC
  String decrypt(String ciphertext) {
    if (!_initialized) throw Exception('EncryptionService not initialized');

    try {
      final parts = ciphertext.split(':');
      if (parts.length != 2) return _legacyDecrypt(ciphertext);

      final iv = enc.IV.fromBase64(parts[0]);
      final encryptedData = enc.Encrypted.fromBase64(parts[1]);
      final key = enc.Key(_aesKey);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      return encrypter.decrypt(encryptedData, iv: iv);
    } catch (e) {
      return _legacyDecrypt(ciphertext);
    }
  }

  /// Legacy XOR decryption for backward compatibility
  String _legacyDecrypt(String ciphertext) {
    try {
      final encryptedBytes = base64Decode(ciphertext);
      final decrypted = Uint8List(encryptedBytes.length);
      for (var i = 0; i < encryptedBytes.length; i++) {
        decrypted[i] = encryptedBytes[i] ^ _aesKey[i % _aesKey.length];
      }
      return utf8.decode(decrypted);
    } catch (e) {
      throw Exception('Decryption failed');
    }
  }

  /// Encrypt binary data using AES-256-CBC
  Uint8List encryptBytes(Uint8List data) {
    if (!_initialized) throw Exception('EncryptionService not initialized');

    final key = enc.Key(_aesKey);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final randomIv = enc.IV.fromSecureRandom(16);
    final paddedData = _padData(data);
    final encrypted = encrypter.encryptBytes(paddedData, iv: randomIv);

    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, randomIv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  /// Decrypt binary data using AES-256-CBC
  Uint8List decryptBytes(Uint8List data) {
    if (!_initialized) throw Exception('EncryptionService not initialized');

    try {
      if (data.length < 17) return _legacyDecryptBytes(data);

      final iv = enc.IV(Uint8List.fromList(data.sublist(0, 16)));
      final encryptedData = enc.Encrypted(Uint8List.fromList(data.sublist(16)));
      final key = enc.Key(_aesKey);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final decrypted = encrypter.decryptBytes(encryptedData, iv: iv);
      return _unpadData(Uint8List.fromList(decrypted));
    } catch (e) {
      return _legacyDecryptBytes(data);
    }
  }

  Uint8List _legacyDecryptBytes(Uint8List data) {
    final decrypted = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      decrypted[i] = data[i] ^ _aesKey[i % _aesKey.length];
    }
    return decrypted;
  }

  Uint8List _padData(Uint8List data) {
    const blockSize = 16;
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Uint8List _unpadData(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data.last;
    if (padLength > 16 || padLength > data.length) return data;
    return Uint8List.fromList(data.sublist(0, data.length - padLength));
  }

  static String generateSecureId() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPin(String pin) {
    const salt = 'GhostJournal_PIN_Salt_2024_Secure';
    List<int> hash = utf8.encode(pin + salt);
    for (var i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }
    return base64Encode(hash);
  }

  static bool verifyPin(String pin, String storedHash) {
    return hashPin(pin) == storedHash;
  }

  void dispose() {
    if (_initialized) {
      for (var i = 0; i < _aesKey.length; i++) {
        _aesKey[i] = 0;
      }
      _initialized = false;
    }
  }
}
