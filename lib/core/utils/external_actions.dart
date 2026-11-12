import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared platform I/O, external URL launching, and sharing helpers.
class ExternalActions {
  ExternalActions._();

  /// Normalizes a map or web URL (adding `https://` when omitted) and launches it.
  static Future<bool> openUrl(String rawUrl) async {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    try {
      final uri = Uri.parse(trimmed);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // Some Android 11+ OEMs still launch external browser even if query misses
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[ExternalActions] Failed to open URL "$trimmed": $e');
      return false;
    }
  }

  /// Opens Google Maps for either an explicit URL or plain coordinates/address.
  static Future<bool> openMapLocation(String rawValue) {
    final v = rawValue.trim().toLowerCase();
    final isUrl = v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.contains('maps.google.com') ||
        v.contains('google.com/maps') ||
        v.contains('maps.app.goo.gl');
    if (isUrl) return openUrl(rawValue);
    return openUrl('https://maps.google.com/?q=${Uri.encodeComponent(rawValue.trim())}');
  }

  /// Writes [bytes] safely to Downloads on desktop/permissive Android, falling
  /// back seamlessly to external app storage or app documents on Android 11-15
  /// Scoped Storage when direct `/storage/emulated/0/Download` access is denied.
  static Future<String?> saveBytesWithFallback(
    List<int> bytes,
    String fileName,
  ) async {
    final candidateDirs = <Directory>[];
    if (!kIsWeb && Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        candidateDirs.add(downloads);
      }
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) candidateDirs.add(ext);
      } catch (_) {}
    }
    try {
      candidateDirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}

    for (final dir in candidateDirs) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final filePath = p.join(dir.path, fileName);
        await File(filePath).writeAsBytes(bytes, flush: true);
        return filePath;
      } catch (e) {
        debugPrint('[ExternalActions] Write failed in "${dir.path}": $e');
      }
    }
    return null;
  }

  /// Opens the native OS share sheet for an exported file.
  static Future<void> shareFile(String filePath, {String? text}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: text,
        ),
      );
    } catch (e) {
      debugPrint('[ExternalActions] Share failed: $e');
    }
  }

  /// Surfaces an actionable Arabic voice/permission error banner with optional App Settings shortcut.
  static void showSpeechErrorSnackBar(
    BuildContext context,
    String message,
    bool canOpenSettings,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        duration: const Duration(seconds: 5),
        action: canOpenSettings
            ? SnackBarAction(
                label: 'فتح الإعدادات',
                textColor: Colors.white,
                onPressed: () {
                  Geolocator.openAppSettings().catchError((_) => false);
                },
              )
            : null,
      ),
    );
  }
}
