import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDarkMode';
  bool _isDarkMode = false;
  bool _loaded = false;

  bool get isDarkMode => _isDarkMode;
  bool get loaded => _loaded;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _loadFromPrefs();
  }

  void toggle() {
    _isDarkMode = !_isDarkMode;
    _saveToPrefs();
    notifyListeners();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key)) {
      _isDarkMode = prefs.getBool(_key)!;
    } else {
      // First launch: use platform brightness
      final brightness =
          SchedulerBinding.instance.platformDispatcher.platformBrightness;
      _isDarkMode = brightness == Brightness.dark;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDarkMode);
  }
}
