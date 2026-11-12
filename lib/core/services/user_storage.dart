import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'auth_service.dart';

/// Central helper for user-scoped directories and file paths.
///
/// Every user-owned file (Excel exports, imports, logs, converted caches)
/// is stored under `<appDocumentsDir>/users/<uid>/`.
class UserStorage {
  UserStorage._();

  /// Whether to delete local user data (files & SQLite rows) on logout.
  static const bool deleteLocalDataOnLogout = false;

  /// Retrieves the current user's UID dynamically at call time.
  static String get currentUid {
    final uid = AuthService.instance.currentUserDocId ??
        AuthService.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('UserStorage: لا يوجد مستخدم مسجل دخوله حالياً.');
    }
    return uid.trim();
  }

  /// Returns the current user's UID or null if not signed in (never throws).
  static String? get currentUidOrNull {
    try {
      return currentUid;
    } catch (_) {
      return null;
    }
  }

  /// Base directory for the given or current user: `<appDocumentsDir>/users/<uid>/`
  static Future<Directory> dir([String? uid]) async {
    final targetUid = uid ?? currentUid;
    final base = await getApplicationDocumentsDirectory();
    final userDirectory = Directory(p.join(base.path, 'users', targetUid));
    if (!await userDirectory.exists()) {
      await userDirectory.create(recursive: true);
    }
    return userDirectory;
  }

  /// Subdirectory inside the user's root folder.
  static Future<Directory> subDir(String subDirectoryName, [String? uid]) async {
    final userBase = await dir(uid);
    final target = Directory(p.join(userBase.path, subDirectoryName));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// User-scoped temp directory: `<getTemporaryDirectory>/users/<uid>/`
  static Future<Directory> tempDir([String? uid]) async {
    final targetUid = uid ?? currentUid;
    final base = await getTemporaryDirectory();
    final target = Directory(p.join(base.path, 'users', targetUid));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// Moves legacy global files into the first signing-in user's folder cleanly
  /// so subsequent users logging in on the same device do not inherit them.
  static Future<void> migrateLegacyFilesIfPresent(String uid) async {
    try {
      final userFolder = await dir(uid);
      final appDocs = await getApplicationDocumentsDirectory();

      final candidates = [
        'CarLogix_Records.xlsx',
        'CarLogix_Verification_Log.xlsx',
      ];

      for (final fileName in candidates) {
        final legacyFile = File(p.join(appDocs.path, fileName));
        final targetFile = File(p.join(userFolder.path, fileName));

        if (await legacyFile.exists()) {
          if (!await targetFile.exists()) {
            await legacyFile.copy(targetFile.path);
          }
          await legacyFile.delete();
          debugPrint('[UserStorage] Migrated and removed legacy "$fileName" for "$uid"');
        }
      }
    } catch (e) {
      debugPrint('[UserStorage] Legacy file migration warning: $e');
    }
  }

  /// Deletes all files and directories scoped to the given user.
  static Future<void> deleteUserData(String uid) async {
    try {
      final userFolder = await dir(uid);
      if (await userFolder.exists()) {
        await userFolder.delete(recursive: true);
      }
      final userTemp = await tempDir(uid);
      if (await userTemp.exists()) {
        await userTemp.delete(recursive: true);
      }
      debugPrint('[UserStorage] Deleted all files for user "$uid"');
    } catch (e) {
      debugPrint('[UserStorage] Failed to delete user files: $e');
    }
  }
}
