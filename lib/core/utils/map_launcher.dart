import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utility to open device's native or default maps application at given coordinates.
class MapLauncher {
  MapLauncher._();

  /// Formats map URLs for different platforms
  static String getGoogleMapsUrl(double latitude, double longitude, [String? label]) {
    final query = label != null && label.isNotEmpty
        ? Uri.encodeComponent('$label ($latitude,$longitude)')
        : '$latitude,$longitude';
    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }

  static String getAppleMapsUrl(double latitude, double longitude, [String? label]) {
    final q = label != null && label.isNotEmpty ? Uri.encodeComponent(label) : '';
    return 'https://maps.apple.com/?ll=$latitude,$longitude&q=$q';
  }

  static String getBingMapsUrl(double latitude, double longitude, [String? label]) {
    final q = label != null && label.isNotEmpty ? '_${Uri.encodeComponent(label)}' : '';
    return 'bingmaps:?cp=$latitude~$longitude&lvl=16&where=$latitude,$longitude$q';
  }

  /// Launch native/default maps app on current platform
  static Future<bool> openCoordinates({
    required double latitude,
    required double longitude,
    String? name,
  }) async {
    final googleUrl = getGoogleMapsUrl(latitude, longitude, name);

    try {
      if (!kIsWeb) {
        if (Platform.isWindows) {
          // Windows: start default handler for maps or browser
          final bingUrl = getBingMapsUrl(latitude, longitude, name);
          try {
            // First attempt native Windows Maps protocol
            final res = await Process.run('cmd', ['/c', 'start', '', bingUrl]);
            if (res.exitCode == 0) return true;
          } catch (_) {}

          // Fallback to browser Google Maps
          final res2 = await Process.run('cmd', ['/c', 'start', '', googleUrl]);
          return res2.exitCode == 0;
        } else if (Platform.isMacOS) {
          final appleUrl = getAppleMapsUrl(latitude, longitude, name);
          final res = await Process.run('open', [appleUrl]);
          if (res.exitCode == 0) return true;
          final res2 = await Process.run('open', [googleUrl]);
          return res2.exitCode == 0;
        } else if (Platform.isLinux) {
          final res = await Process.run('xdg-open', [googleUrl]);
          return res.exitCode == 0;
        } else if (Platform.isAndroid) {
          final label = name != null ? Uri.encodeComponent(name) : '';
          final geoUri = 'geo:$latitude,$longitude?q=$latitude,$longitude($label)';
          try {
            final res = await Process.run('am', ['start', '-a', 'android.intent.action.VIEW', '-d', geoUri]);
            if (res.exitCode == 0) return true;
          } catch (_) {}
          try {
            final res2 = await Process.run('am', ['start', '-a', 'android.intent.action.VIEW', '-d', googleUrl]);
            return res2.exitCode == 0;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[MapLauncher] Failed to launch platform map intent: $e');
    }

    // Always copy coordinates to clipboard as friendly fallback
    try {
      await Clipboard.setData(ClipboardData(text: '$latitude, $longitude'));
    } catch (_) {}

    return false;
  }
}
