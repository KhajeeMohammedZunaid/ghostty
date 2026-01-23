import 'package:shared_preferences/shared_preferences.dart';

/// Service to track if animations have been shown
/// Animations should only play once per session/install
class AnimationPrefs {
  static const String _keyJournalListAnimated = 'animated_journal_list';
  static const String _keyVaultAnimated = 'animated_vault';
  static const String _keyHomeAnimated = 'animated_home';
  static const String _keyAuthAnimated = 'animated_auth';
  
  static SharedPreferences? _prefs;
  
  // In-memory cache for current session
  static final Set<String> _sessionAnimated = {};
  
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Check if animation should play (only once per session)
  static bool shouldAnimate(String key) {
    if (_sessionAnimated.contains(key)) {
      return false;
    }
    _sessionAnimated.add(key);
    return true;
  }
  
  /// Mark animation as shown for this session
  static void markAnimated(String key) {
    _sessionAnimated.add(key);
  }
  
  /// Clear session animations (for testing or on logout)
  static void clearSession() {
    _sessionAnimated.clear();
  }
  
  // Specific animation checks
  static bool shouldAnimateJournalList() => shouldAnimate(_keyJournalListAnimated);
  static bool shouldAnimateVault() => shouldAnimate(_keyVaultAnimated);
  static bool shouldAnimateHome() => shouldAnimate(_keyHomeAnimated);
  static bool shouldAnimateAuth() => shouldAnimate(_keyAuthAnimated);
}
