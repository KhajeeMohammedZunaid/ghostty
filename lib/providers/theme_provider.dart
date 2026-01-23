import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  bool get isDark => _themeMode == ThemeMode.dark;
  
  ThemeProvider() {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    final savedMode = await StorageService.instance.getThemeMode();
    _themeMode = savedMode;
    notifyListeners();
  }
  
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await StorageService.instance.saveThemeMode(_themeMode);
    notifyListeners();
  }
  
  Future<void> setDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    await StorageService.instance.saveThemeMode(_themeMode);
    notifyListeners();
  }
  
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await StorageService.instance.saveThemeMode(mode);
    notifyListeners();
  }
}
