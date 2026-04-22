import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDarkMode';
  bool _isDarkMode = false;
  bool _loaded = false;
  // Phase 3 Iter7 EDGE-08: when the user has never made an explicit choice,
  // we follow the OS theme live instead of freezing on whatever brightness
  // happened to be set the first time the app opened.
  bool _followSystem = false;
  VoidCallback? _platformBrightnessListener;

  bool get isDarkMode => _isDarkMode;
  bool get loaded => _loaded;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _loadFromPrefs();
  }

  // Phase 3 Iter7 BUG-15 fix: was fire-and-forget. Now we notify the UI
  // immediately for instant feedback, then await the persistence write so
  // a quick app-kill or a rapid double-toggle can't desync the stored
  // value from the live state.
  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    _followSystem = false;
    _detachPlatformBrightnessListener();
    notifyListeners();
    await _saveToPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key)) {
      _isDarkMode = prefs.getBool(_key)!;
      _followSystem = false;
    } else {
      // Phase 3 Iter7 EDGE-08 fix: first launch — track system brightness
      // live (not just sample once) until the user picks a side via toggle().
      _followSystem = true;
      _isDarkMode = _currentPlatformIsDark();
      _attachPlatformBrightnessListener();
    }
    _loaded = true;
    notifyListeners();
  }

  bool _currentPlatformIsDark() {
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  void _attachPlatformBrightnessListener() {
    if (_platformBrightnessListener != null) return;
    _platformBrightnessListener = () {
      if (!_followSystem) return;
      final next = _currentPlatformIsDark();
      if (next != _isDarkMode) {
        _isDarkMode = next;
        notifyListeners();
      }
    };
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _platformBrightnessListener;
  }

  void _detachPlatformBrightnessListener() {
    if (_platformBrightnessListener == null) return;
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        null;
    _platformBrightnessListener = null;
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDarkMode);
  }

  @override
  void dispose() {
    _detachPlatformBrightnessListener();
    super.dispose();
  }
}
