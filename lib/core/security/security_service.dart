import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/models.dart';

/// Manages PIN authentication, biometric simulation, and auto-lock state
class SecurityService extends ChangeNotifier {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static const String _prefPinEnabled = 'security_pin_enabled';
  static const String _prefPinHash = 'security_pin_hash';
  static const String _prefPinSalt = 'security_pin_salt';
  static const String _prefAutoLock = 'security_auto_lock_minutes';
  static const String _prefBiometric = 'security_biometric_enabled';
  static const String _prefLastActive = 'security_last_active_time';

  bool _isLocked = false;
  SecuritySettings _settings = const SecuritySettings();

  bool get isLocked => _isLocked;
  bool get isPinConfigured => _settings.isPinEnabled && _settings.pinHash.isNotEmpty;
  SecuritySettings get settings => _settings;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isPinEnabled = prefs.getBool(_prefPinEnabled) ?? false;
    final pinHash = prefs.getString(_prefPinHash) ?? '';
    final pinSalt = prefs.getString(_prefPinSalt) ?? '';
    final autoLock = prefs.getInt(_prefAutoLock) ?? 5;
    final biometric = prefs.getBool(_prefBiometric) ?? false;

    _settings = SecuritySettings(
      isPinEnabled: isPinEnabled,
      pinHash: pinHash,
      pinSalt: pinSalt,
      autoLockMinutes: autoLock,
      isBiometricEnabled: biometric,
    );

    // If PIN is enabled, app should lock on cold startup
    if (isPinConfigured) {
      _isLocked = true;
    }
    notifyListeners();
  }

  /// Verifies entered PIN against stored salt and hash
  bool verifyPin(String pin) {
    if (!isPinConfigured) return true;
    final hash = _computeHash(pin, _settings.pinSalt);
    return hash == _settings.pinHash;
  }

  /// Attempts to unlock the application with the given PIN
  bool unlock(String pin) {
    if (!isPinConfigured) {
      _isLocked = false;
      notifyListeners();
      return true;
    }
    if (verifyPin(pin)) {
      _isLocked = false;
      updateActivity();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Unlock directly when biometric authentication succeeds
  void unlockBiometric() {
    _isLocked = false;
    updateActivity();
    notifyListeners();
  }

  /// Immediately locks the app
  void lock() {
    if (isPinConfigured) {
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Configures or changes the PIN code
  Future<void> setPin(String newPin) async {
    final salt = _generateRandomSalt();
    final hash = _computeHash(newPin, salt);

    _settings = _settings.copyWith(
      isPinEnabled: true,
      pinHash: hash,
      pinSalt: salt,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPinEnabled, true);
    await prefs.setString(_prefPinHash, hash);
    await prefs.setString(_prefPinSalt, salt);

    _isLocked = false;
    updateActivity();
    notifyListeners();
  }

  /// Disables PIN lock completely
  Future<void> disablePin() async {
    _settings = _settings.copyWith(
      isPinEnabled: false,
      pinHash: '',
      pinSalt: '',
      isBiometricEnabled: false,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPinEnabled, false);
    await prefs.remove(_prefPinHash);
    await prefs.remove(_prefPinSalt);
    await prefs.setBool(_prefBiometric, false);

    _isLocked = false;
    notifyListeners();
  }

  /// Updates auto-lock timeout in minutes (0 = immediately, -1 = never)
  Future<void> setAutoLockMinutes(int minutes) async {
    _settings = _settings.copyWith(autoLockMinutes: minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAutoLock, minutes);
    notifyListeners();
  }

  /// Toggles biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    _settings = _settings.copyWith(isBiometricEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBiometric, enabled);
    notifyListeners();
  }

  /// Tracks recent user touch / interaction
  void updateActivity() {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_prefLastActive, now);
    });
  }

  /// Checks if inactivity duration warrants locking the app
  Future<void> checkAutoLock() async {
    if (!isPinConfigured) return;
    if (_settings.autoLockMinutes < 0) return; // Never lock

    if (_settings.autoLockMinutes == 0) {
      lock();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastActive = prefs.getInt(_prefLastActive) ?? 0;
    if (lastActive == 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = now - lastActive;
    final thresholdMs = _settings.autoLockMinutes * 60 * 1000;

    if (diffMs >= thresholdMs) {
      lock();
    }
  }

  static String _generateRandomSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Encode(bytes);
  }

  static String _computeHash(String pin, String salt) {
    final bytes = utf8.encode('$pin:$salt:ozo_lock_salt');
    return sha256.convert(bytes).toString();
  }
}
