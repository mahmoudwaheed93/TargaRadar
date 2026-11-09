import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'auth_service.dart';

/// Central helper for user-scoped directories and file paths.
///
/// Every user-owned file (Excel exports, imports, logs, converted caches)
/// is stored under `<appDocumentsDir>/users/<uid>/`.
///
/// The `uid` is read dynamically at call time from [AuthService.instance.currentUserDocId]
/// or [AuthService.instance.currentUser?.uid]. It is never cached.
class UserStorage {
  UserStorage._();

  /// Whether to delete local user data (files & SQLite rows) on logout.
  /// Set to false by default as requested.
  static const bool deleteLocalDataOnLogout = false;

  /// Retrieves the current user's UID dynamically at call time.
  /// Throws [StateError] if no user is signed in.
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

  /// Base directory for the given or current user:
  /// `<appDocumentsDir>/users/<uid>/`
  static Future<Directory> dir([String? uid]) async {
    final targetUid = uid ?? currentUid;
    final base = await getApplicationDocumentsDirectory();
    final userDirectory = Directory(p.join(base.path, 'users', targetUid));
    if (!await userDirectory.exists()) {
      await userDirectory.create(recursive: true);
    }
    return userDirectory;
  }

  /// Subdirectory inside the user's root folder (e.g. 'excel', 'converted', 'sessions').
  static Future<Directory> subDir(String subDirectoryName, [String? uid]) async {
    final userBase = await dir(uid);
    final target = Directory(p.join(userBase.path, subDirectoryName));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// User-scoped temp directory for staged imports/picks:
  /// `<getTemporaryDirectory>/users/<uid>/`
  static Future<Directory> tempDir([String? uid]) async {
    final targetUid = uid ?? currentUid;
    final base = await getTemporaryDirectory();
    final target = Directory(p.join(base.path, 'users', targetUid));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// Migrates legacy global files to the current user's folder safely.
  /// Does not delete legacy files unless migration succeeds and copy is verified.
  static Future<void> migrateLegacyFilesIfPresent(String uid) async {
    try {
      final userFolder = await dir(uid);
      final appDocs = await getApplicationDocumentsDirectory();

      // Legacy files to inspect and copy
      final candidates = [
        'CarLogix_Records.xlsx',
        'CarLogix_Verification_Log.xlsx',
      ];

      for (final fileName in candidates) {
        final legacyFile = File(p.join(appDocs.path, fileName));
        final targetFile = File(p.join(userFolder.path, fileName));

        if (await legacyFile.exists() && !await targetFile.exists()) {
          await legacyFile.copy(targetFile.path);
          debugPrint('[UserStorage] Migrated legacy file "$fileName" to user "$uid"');
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
