import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/journal_entry.dart';
import 'encryption_service.dart';

/// Secure storage service for Ghost Journal
/// All data is encrypted before storage
class StorageService {
  static StorageService? _instance;
  late Box<String> _journalBox;
  late SharedPreferences _prefs;
  bool _initialized = false;

  StorageService._();

  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  bool get isInitialized => _initialized;

  /// Initialize storage
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();
    _journalBox = await Hive.openBox<String>('ghost_journal_entries');
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // ==================== PIN Management ====================

  Future<bool> hasPin() async {
    return _prefs.containsKey('ghost_pin_hash');
  }

  Future<void> setPin(String pin) async {
    final hash = EncryptionService.hashPin(pin);
    await _prefs.setString('ghost_pin_hash', hash);
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = _prefs.getString('ghost_pin_hash');
    if (storedHash == null) return false;
    return EncryptionService.verifyPin(pin, storedHash);
  }

  // ==================== Journal Entries ====================

  Future<List<JournalEntry>> getAllJournalEntries() async {
    final encryption = EncryptionService.instance;
    if (!encryption.isInitialized) return [];

    final entries = <JournalEntry>[];
    for (final key in _journalBox.keys) {
      try {
        final encrypted = _journalBox.get(key);
        if (encrypted != null) {
          final decrypted = encryption.decrypt(encrypted);
          entries.add(JournalEntry.fromEncodedJson(decrypted));
        }
      } catch (e) {
        // Skip corrupted entries
        continue;
      }
    }

    // Sort by updated date, newest first
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  Future<JournalEntry?> getJournalEntry(String id) async {
    final encryption = EncryptionService.instance;
    if (!encryption.isInitialized) return null;

    try {
      final encrypted = _journalBox.get(id);
      if (encrypted == null) return null;
      final decrypted = encryption.decrypt(encrypted);
      return JournalEntry.fromEncodedJson(decrypted);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveJournalEntry(JournalEntry entry) async {
    final encryption = EncryptionService.instance;
    if (!encryption.isInitialized) {
      throw Exception('Encryption not initialized');
    }

    final json = entry.toEncodedJson();
    final encrypted = encryption.encrypt(json);
    await _journalBox.put(entry.id, encrypted);
  }

  Future<void> deleteJournalEntry(String id) async {
    await _journalBox.delete(id);
  }

  // ==================== Settings ====================

  Future<bool> isDarkMode() async {
    return _prefs.getBool('ghost_dark_mode') ?? true;
  }

  Future<void> setDarkMode(bool value) async {
    await _prefs.setBool('ghost_dark_mode', value);
  }
  
  Future<ThemeMode> getThemeMode() async {
    final mode = _prefs.getString('ghost_theme_mode');
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
  
  Future<void> saveThemeMode(ThemeMode mode) async {
    String modeStr;
    switch (mode) {
      case ThemeMode.light:
        modeStr = 'light';
        break;
      case ThemeMode.dark:
        modeStr = 'dark';
        break;
      case ThemeMode.system:
        modeStr = 'system';
        break;
    }
    await _prefs.setString('ghost_theme_mode', modeStr);
  }

  Future<int> getAutoLockSeconds() async {
    return _prefs.getInt('ghost_auto_lock_seconds') ?? 15;
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    await _prefs.setInt('ghost_auto_lock_seconds', seconds);
  }

  // ==================== Clear All Data ====================

  Future<void> clearAllData() async {
    await _journalBox.clear();
    await _prefs.remove('ghost_pin_hash');
  }
}
