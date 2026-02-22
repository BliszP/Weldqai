import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();
  static final ThemeController i = ThemeController._();

  /// The whole app listens to this.
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  bool get isDark => themeMode.value == ThemeMode.dark;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getBool('prefs.darkMode');
    themeMode.value =
        saved == null ? ThemeMode.system : (saved ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setDark(bool dark) async {
    themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('prefs.darkMode', dark);
  }

  /// Back-compat with older code
  @Deprecated('Use setDark')
  Future<void> setDarkMode(bool dark) => setDark(dark);
}
