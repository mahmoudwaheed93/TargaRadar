import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/subscription_duration.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';

/// Chip filter options for the user list (الكل / نشط / غير نشط).
enum UserFilter { all, active, inactive }

/// Presentation state for the Admin Control Panel → User Management screen.
///
/// Acts as the StateNotifier for the real-time Firestore `users` roster: it
/// owns the stream subscription (started/stopped with the screen lifecycle so
/// the listener only lives while an admin has the panel open), derives the
/// visible list from the current search query + filter chip, and encapsulates
/// the create-user business rules (duration resolution + validation).
class UserManagementProvider extends ChangeNotifier {
  UserManagementProvider({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;

  StreamSubscription<List<UserModel>>? _usersSub;
  List<UserModel> _users = const [];
  bool _isLoadingUsers = false;
  String? _usersError;

  String _searchQuery = '';
  UserFilter _filter = UserFilter.all;
  bool _isCreating = false;
  String? _createError;
  bool _isRenewing = false;
  String? _renewError;

  // ---- Getters ----
  List<UserModel> get users => _users;
  bool get isLoadingUsers => _isLoadingUsers;
  String? get usersError => _usersError;
  int get totalCount => _users.length;
  String get searchQuery => _searchQuery;
  UserFilter get filter => _filter;
  bool get isCreating => _isCreating;
  String? get createError => _createError;
  bool get isRenewing => _isRenewing;
  String? get renewError => _renewError;

  /// The roster after applying the active search query and status filter.
  List<UserModel> get visibleUsers =>
      _users.where((u) => _matchesFilter(u) && _matchesSearch(u)).toList();

  // ---- Real-time stream lifecycle ----

  /// Begins listening to the `users` collection. Idempotent.
  ///
  /// Called from the screen's `initState`. Mutates the loading flag *without*
  /// notifying (the caller is mid-build and will read the fresh state on its
  /// first frame); subsequent stream events notify normally.
  void startUsersStream() {
    if (_usersSub != null) return;
    _isLoadingUsers = true;
    _usersError = null;
    _usersSub = _userRepository.watchUsers().listen(
      (users) {
        _users = users;
        _isLoadingUsers = false;
        _usersError = null;
        notifyListeners();
      },
      onError: (Object error) {
        _usersError = '$error';
        _isLoadingUsers = false;
        notifyListeners();
      },
    );
  }

  /// Cancels the Firestore listener. Called from the screen's `dispose`.
  /// Does not notify: the observing widget is being torn down.
  void stopUsersStream() {
    _usersSub?.cancel();
    _usersSub = null;
    _isLoadingUsers = false;
    _users = const [];
    _usersError = null;
  }

  // ---- Search & filter ----

  void setSearchQuery(String value) {
    if (_searchQuery == value) return;
    _searchQuery = value;
    notifyListeners();
  }

  void setFilter(UserFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void clearCreateError() {
    if (_createError == null) return;
    _createError = null;
    notifyListeners();
  }

  /// 'نشط' means the subscription is currently valid (active flag AND not
  /// expired), mirroring the gate used across the app.
  bool _isActive(UserModel user) => user.isSubscriptionValid;

  bool _matchesSearch(UserModel user) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return user.username.toLowerCase().contains(q);
  }

  bool _matchesFilter(UserModel user) {
    switch (_filter) {
      case UserFilter.all:
        return true;
      case UserFilter.active:
        return _isActive(user);
      case UserFilter.inactive:
        return !_isActive(user);
    }
  }

  // ---- Create user ----

  /// Validates the creation form, resolves the [SubscriptionDuration], and
  /// persists a new user. Returns `true` on success; on failure sets
  /// [createError] and returns `false`.
  Future<bool> createUser({
    required String username,
    required String password,
    required bool isActive,
    required DurationMode mode,
    int days = 30,
    DateTime? specificDate,
    String role = 'user',
  }) async {
    _isCreating = true;
    _createError = null;
    notifyListeners();

    try {
      final SubscriptionDuration duration;
      if (mode == DurationMode.days) {
        if (days <= 0) {
          _createError = 'عدد الأيام يجب أن يكون أكبر من صفر';
          return false;
        }
        duration = SubscriptionDuration.days(days);
      } else {
        if (specificDate == null) {
          _createError = 'يرجى اختيار تاريخ الانتهاء';
          return false;
        }
        final endOfDay = DateTime(
          specificDate.year,
          specificDate.month,
          specificDate.day,
          23,
          59,
          59,
        );
        if (endOfDay.isBefore(DateTime.now())) {
          _createError = 'تاريخ الانتهاء يجب أن يكون في المستقبل';
          return false;
        }
        duration = SubscriptionDuration.untilDate(specificDate);
      }

      await _userRepository.createUser(
        username: username,
        password: password,
        isActive: isActive,
        duration: duration,
        role: role,
      );
      return true;
    } on UserRepositoryException catch (e) {
      _createError = e.message;
      return false;
    } catch (e) {
      _createError = 'حدث خطأ غير متوقع، حاول مجدداً ($e)';
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  void clearRenewError() {
    if (_renewError == null) return;
    _renewError = null;
    notifyListeners();
  }

  /// Renews the subscription for [user]. Returns true on success.
  Future<bool> renewSubscription({
    required UserModel user,
    required DurationMode mode,
    int days = 30,
    DateTime? specificDate,
  }) async {
    _isRenewing = true;
    _renewError = null;
    notifyListeners();

    try {
      final SubscriptionDuration duration;
      if (mode == DurationMode.days) {
        if (days <= 0) {
          _renewError = 'عدد الأيام يجب أن يكون أكبر من صفر';
          return false;
        }
        duration = SubscriptionDuration.days(days);
      } else {
        if (specificDate == null) {
          _renewError = 'يرجى اختيار تاريخ الانتهاء';
          return false;
        }
        final endOfDay = DateTime(
          specificDate.year,
          specificDate.month,
          specificDate.day,
          23, 59, 59,
        );
        if (endOfDay.isBefore(DateTime.now())) {
          _renewError = 'تاريخ الانتهاء يجب أن يكون في المستقبل';
          return false;
        }
        duration = SubscriptionDuration.untilDate(specificDate);
      }

      await _userRepository.renewSubscription(uid: user.uid, duration: duration);
      return true;
    } on UserRepositoryException catch (e) {
      _renewError = e.message;
      return false;
    } catch (e) {
      _renewError = 'حدث خطأ غير متوقع، حاول مجدداً ($e)';
      return false;
    } finally {
      _isRenewing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    super.dispose();
  }
}
