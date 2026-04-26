import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/enums.dart';
import '../../core/utils/url_utils.dart';

/// Database Service
///
/// Single chokepoint for every Supabase Postgres read / write / RPC. Mixes
/// SECURITY DEFINER RPCs (mutating paths that need to bypass RLS — owner
/// signup, atomic booking, slot lifecycle) with direct PostgREST queries
/// (read paths constrained by RLS).
///
/// Hardening layers in this file:
///   * `_assert*Writable` — mass-assignment defense for free-form update Maps.
///   * `_public*Columns`  — read-side allowlists so future PII / audit columns
///                         do not auto-leak to the client. (Phase 4 Iter 8 DB-03)
///   * `_runWithRetry`    — single shared transient-network retry policy so
///                         every retried mutation behaves identically.
///                         (Phase 4 Iter 8 DB-04)
///   * `_utcDateString`   — UTC-anchored date math so slot deletions never
///                         skew by a day across the IST/UTC midnight boundary.
///                         (Phase 4 Iter 8 DB-05)
class DatabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  static const _uuid = Uuid();

  // ---------------------------------------------------------------------
  // Iteration 4 — column allowlists for mass-assignment defense.
  // Any update method that takes a free-form Map MUST run the input through
  // the relevant guard before sending it to Supabase. The guards throw a
  // StateError synchronously so a forbidden caller fails loudly in dev.
  // ---------------------------------------------------------------------

  /// Columns the app is allowed to write on `owners`. Phone changes MUST
  /// go through `syncOwnerAfterOtp` (OTP-verified path) and are blocked
  /// here on purpose.
  static const _ownerWritableColumns = <String>{
    'name',
    'email',
    'has_password',
    'auth_methods',
    'updated_at',
  };

  /// Columns the app is allowed to write on `players`. Same reasoning as
  /// `_ownerWritableColumns` — phone changes are blocked here.
  static const _playerWritableColumns = <String>{
    'name',
    'email',
    'has_password',
    'auth_methods',
    'updated_at',
  };

  /// Columns the app must NEVER let a caller set on `turfs`. Most
  /// importantly, owners cannot self-approve their own turf — the admin
  /// review pipeline owns `is_approved` and `verification_status` (with
  /// the narrow exception of resetting to PENDING/REJECTED on edit).
  static const _turfBlockedColumns = <String>{
    'id',
    'owner_id',
    'created_at',
  };

  /// Columns the app is allowed to write on `bookings` via the generic
  /// updater. Money/identity columns (`amount`, `payment_status`, `slot_id`,
  /// `customer_*`, etc.) require dedicated methods — most are also
  /// enforced server-side by the immutable-columns trigger.
  static const _bookingWritableColumns = <String>{
    'cancel_reason',
    'notes',
    'cancelled_by',
    'cancelled_at',
    'updated_at',
  };

  /// Explicit safe column list for player-facing turf reads. Future
  /// owner-only/admin-only columns added to `turfs` will NOT be auto-leaked
  /// to the player browse path.
  static const _publicTurfColumns =
      'id, owner_id, turf_name, turf_type, number_of_nets, city, address, '
      'location, description, open_time, close_time, slot_duration_minutes, '
      'days_open, pricing_rules, public_holidays, images, is_approved, '
      'verification_status, status, renovation_net_numbers, created_at, updated_at';

  // Phase 4 Iter 8 DB-03: explicit read column allowlists for owners /
  // players / bookings. Replaces the previous `select('*')` calls so any
  // future audit / PII column added to these tables does not auto-leak.
  static const _publicOwnerColumns =
      'id, name, email, phone, role, is_verified, auth_methods, '
      'profile_image, has_password, status, created_at, updated_at';
  static const _publicPlayerColumns =
      'id, name, email, phone, role, auth_methods, has_password, '
      'profile_image, favorite_turfs, status, created_at, updated_at';
  static const _publicBookingColumns =
      'id, owner_id, turf_id, slot_id, booking_date, start_time, end_time, '
      'turf_name, net_number, user_id, customer_name, customer_phone, '
      'booking_source, payment_mode, payment_status, amount, advance_amount, '
      'transaction_id, booking_status, cancelled_at, cancelled_by, '
      'cancellation_reason, created_by, updated_by, created_at, updated_at';

  // Phase 4 Iter 8 DB-04: shared retryable-error markers. Previously the
  // four hand-rolled retry loops drifted apart — blockSlot/unblockSlot
  // missed `socketexception` / `clientexception`. One source of truth now.
  static const _retryableNetworkMarkers = <String>[
    'failed to fetch',
    'socketexception',
    'clientexception',
    'timeout',
    'connection',
    'network',
  ];

  bool _isRetryableNetworkError(Object error) {
    final s = error.toString().toLowerCase();
    return _retryableNetworkMarkers.any(s.contains);
  }

  // Phase 4 Iter 8 DB-05: UTC-anchored date string. Local-time `tomorrow`
  // skewed slot-deletion queries by a day in IST near UTC midnight.
  static String _utcDateString(DateTime dt) =>
      dt.toUtc().toIso8601String().split('T')[0];

  void _assertOwnerWritable(Map<String, dynamic> data) {
    final bad = data.keys.where((k) => !_ownerWritableColumns.contains(k));
    if (bad.isNotEmpty) {
      throw StateError(
          'updateOwner: forbidden column(s) ${bad.toList()}. Phone changes must use syncOwnerAfterOtp.');
    }
  }

  void _assertPlayerWritable(Map<String, dynamic> data) {
    final bad = data.keys.where((k) => !_playerWritableColumns.contains(k));
    if (bad.isNotEmpty) {
      throw StateError('updatePlayer: forbidden column(s) ${bad.toList()}.');
    }
  }

  void _assertTurfWritable(Map<String, dynamic> data) {
    final blocked =
        data.keys.where((k) => _turfBlockedColumns.contains(k)).toList();
    if (blocked.isNotEmpty) {
      throw StateError(
          'updateTurf: blocked column(s) $blocked cannot be modified by app code.');
    }
    if (data.containsKey('is_approved') && data['is_approved'] == true) {
      throw StateError(
          'updateTurf: cannot set is_approved=true. Approval is admin-only.');
    }
    if (data.containsKey('verification_status')) {
      final v = data['verification_status']?.toString();
      const allowed = {'PENDING', 'REJECTED'};
      if (v == null || !allowed.contains(v)) {
        throw StateError(
            'updateTurf: verification_status can only be set to PENDING or REJECTED by app code (got $v).');
      }
    }
  }

  void _assertBookingWritable(Map<String, dynamic> data) {
    final bad = data.keys.where((k) => !_bookingWritableColumns.contains(k));
    if (bad.isNotEmpty) {
      throw StateError(
          'updateBooking: forbidden column(s) ${bad.toList()}. Use a dedicated method (e.g. markBookingPaymentReceived) for payment/identity changes.');
    }
  }

  // =====================================================
  // OWNER OPERATIONS
  // =====================================================

  /// Check if owner exists by email or phone (using RPC)
  Future<bool> ownerExists({String? email, String? phone}) async {
    try {
      final result = await _client.rpc('check_owner_exists', params: {
        'check_email': email?.trim().toLowerCase(),
        'check_phone': phone?.trim(),
      });
      return result == true;
    } catch (e) {
      // Phase 4 Iter 8 DB-11: gate string interpolation behind kDebugMode.
      if (kDebugMode) {
        debugPrint('check_owner_exists RPC failed: $e');
      }
      rethrow;
    }
  }

  /// Create owner profile (using RPC - bypasses RLS)
  Future<void> createOwnerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
    bool hasPassword = false,
    List<String> authMethods = const ['email'],
  }) async {
    try {
      await _client.rpc('create_owner_profile', params: {
        'user_id': id,
        'user_name': name.trim(),
        'user_email': email.trim().toLowerCase(),
        'user_phone': phone.trim(),
        'user_has_password': hasPassword,
        'user_auth_methods': authMethods,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('unique') || e.message.contains('duplicate')) {
        throw AuthException('Email or phone already registered.');
      }
      throw AuthException('Failed to create profile: ${e.message}');
    }
  }

  /// Get owner by ID. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<Map<String, dynamic>?> getOwner(String ownerId) async {
    return await _client
        .from('owners')
        .select(_publicOwnerColumns)
        .eq('id', ownerId)
        .maybeSingle();
  }

  /// Update owner. Caller may only set columns in `_ownerWritableColumns`.
  /// Phone changes go through `syncOwnerAfterOtp` and are rejected here.
  Future<void> updateOwner(String ownerId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    _assertOwnerWritable(data);
    await _client.from('owners').update(data).eq('id', ownerId);
  }

  /// Atomically sync verified phone and auth method after OTP verification.
  Future<void> syncOwnerAfterOtp({
    required String ownerId,
    required String verifiedPhone,
    String addMethod = 'otp',
  }) async {
    await _client.rpc('sync_owner_after_otp', params: {
      'p_owner_id': ownerId,
      'p_verified_phone': verifiedPhone.trim(),
      'p_add_method': addMethod,
    });
  }

  /// Get owner by phone. Phase 4 Iter 8 DB-03 + DB-07: column allowlist +
  /// trim phone (create-side already trims; lookup must match).
  Future<Map<String, dynamic>?> getOwnerByPhone(String phone) async {
    return await _client
        .from('owners')
        .select(_publicOwnerColumns)
        .eq('phone', phone.trim())
        .maybeSingle();
  }

  /// Check if phone is already registered to another owner.
  /// F6 (account-enumeration hardening): we deliberately return only a
  /// boolean. Returning the conflicting account's email here would let
  /// any caller probe whether a given phone is in use AND get back the
  /// owning email.
  /// Phase 4 Iter 8 DB-07: trim phone (matches create-side normalization).
  Future<bool> checkPhoneAlreadyRegistered(String phone) async {
    final result = await _client
        .from('owners')
        .select('id')
        .eq('phone', phone.trim())
        .maybeSingle();
    return result != null;
  }

  /// Get owner by email. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<Map<String, dynamic>?> getOwnerByEmail(String email) async {
    return await _client
        .from('owners')
        .select(_publicOwnerColumns)
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
  }

  // =====================================================
  // PLAYER OPERATIONS
  // =====================================================

  /// Create player profile (using RPC - bypasses RLS)
  Future<void> createPlayerProfile({
    required String id,
    required String name,
    required String email,
    required String phone,
    bool hasPassword = false,
    List<String> authMethods = const ['email'],
  }) async {
    try {
      await _client.rpc('create_player_profile', params: {
        'user_id': id,
        'user_name': name.trim(),
        'user_email': email.trim().toLowerCase(),
        'user_phone': phone.trim(),
        'user_has_password': hasPassword,
        'user_auth_methods': authMethods,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('unique') || e.message.contains('duplicate')) {
        throw AuthException('Email or phone already registered.');
      }
      throw AuthException('Failed to create profile: ${e.message}');
    }
  }

  /// Update player profile metadata. Allowlisted to non-sensitive columns.
  Future<void> updatePlayer(String playerId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    _assertPlayerWritable(data);
    await _client.from('players').update(data).eq('id', playerId);
  }

  /// Get player by ID. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<Map<String, dynamic>?> getPlayer(String playerId) async {
    return await _client
        .from('players')
        .select(_publicPlayerColumns)
        .eq('id', playerId)
        .maybeSingle();
  }

  /// Get player by email. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<Map<String, dynamic>?> getPlayerByEmail(String email) async {
    return await _client
        .from('players')
        .select(_publicPlayerColumns)
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
  }

  /// Phase 8 Iter 4 AUTH-08: lookup player by phone for OTP-login gating.
  Future<Map<String, dynamic>?> getPlayerByPhone(String phone) async {
    return await _client
        .from('players')
        .select(_publicPlayerColumns)
        .eq('phone', phone.trim())
        .maybeSingle();
  }

  /// Global phone availability check across owners, players and pending signups.
  Future<Map<String, dynamic>> checkPhoneAvailabilityGlobal({
    required String phone,
    String? excludeUserId,
  }) async {
    final result = await _client.rpc('check_phone_availability', params: {
      'p_phone': phone.trim(),
      'p_exclude_user_id': excludeUserId,
    });

    final rows = (result is List) ? result : <dynamic>[];
    if (rows.isEmpty) {
      return {
        'is_available': true,
        'conflict_source': null,
        'conflict_user_id': null,
      };
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    return {
      'is_available': row['is_available'] == true,
      'conflict_source': row['conflict_source']?.toString(),
      'conflict_user_id': row['conflict_user_id']?.toString(),
    };
  }

  /// Save or update pending signup state.
  Future<void> upsertPendingSignup({
    required String userId,
    required UserRole role,
    required String name,
    required String email,
    required String phone,
    required String authMethod,
    required bool hasPassword,
  }) async {
    await _client.rpc('upsert_pending_signup', params: {
      'p_user_id': userId,
      'p_role': role == UserRole.owner ? 'OWNER' : 'PLAYER',
      'p_name': name.trim(),
      'p_email': email.trim().toLowerCase(),
      'p_phone': phone.trim(),
      'p_auth_method': authMethod.trim().toLowerCase(),
      'p_has_password': hasPassword,
    });
  }

  /// Get pending signup for a user if any.
  Future<Map<String, dynamic>?> getPendingSignup(String userId) async {
    final result = await _client.rpc('get_pending_signup', params: {
      'p_user_id': userId,
    });

    final rows = (result is List) ? result : <dynamic>[];
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  /// Delete the caller's own pending signup row (best-effort).
  /// Used when the user cancels deferred signup so we don't leave behind
  /// orphaned PII (name/email/phone) in pending_auth_signups.
  /// Relies on the `pending_auth_signups_delete_own` RLS policy.
  Future<void> deletePendingSignup(String userId) async {
    await _client.from('pending_auth_signups').delete().eq('user_id', userId);
  }

  /// Finalize pending signup atomically after OTP verification.
  Future<Map<String, dynamic>> finalizePendingSignup({
    required String userId,
    required String verifiedPhone,
  }) async {
    final result = await _client.rpc('finalize_pending_signup', params: {
      'p_user_id': userId,
      'p_verified_phone': verifiedPhone.trim(),
    });

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    return {
      'role': null,
      'phone': verifiedPhone.trim(),
    };
  }

  // =====================================================
  // TURF OPERATIONS
  // =====================================================

  /// Stream owner's turfs.
  /// Phase 4 Iter 8 DB-02: filter on the realtime stream itself with
  /// `.eq('owner_id', ...)` instead of fetching every row in `turfs` and
  /// filtering client-side. Cuts realtime traffic to just this owner's
  /// rows and removes the row-leak vector if RLS ever regresses.
  Stream<List<Map<String, dynamic>>> streamOwnerTurfs(String ownerId) {
    return _client
        .from('turfs')
        .stream(primaryKey: ['id'])
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);
  }

  /// Get owner's turfs (one-time fetch). Owner-side: full row OK (this
  /// path is only used by the owner's own dashboard).
  Future<List<Map<String, dynamic>>> getOwnerTurfs(String ownerId) async {
    return await _client
        .from('turfs')
        .select('*')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);
  }

  /// Get approved turfs (for players). F8: explicit column list so any
  /// future sensitive column added to `turfs` does not auto-leak.
  Future<List<Map<String, dynamic>>> getApprovedTurfs({String? city}) async {
    var query = _client
        .from('turfs')
        .select(_publicTurfColumns)
        .eq('is_approved', true);
    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }
    return await query.order('created_at', ascending: false);
  }

  /// Get turf by ID. F8: explicit column list (player-facing path).
  Future<Map<String, dynamic>?> getTurf(String turfId) async {
    return await _client
        .from('turfs')
        .select(_publicTurfColumns)
        .eq('id', turfId)
        .maybeSingle();
  }

  /// Create turf with retry logic for network issues.
  /// F4 (idempotency): we always pre-generate a UUID before the first
  /// attempt. If a retry runs after the server actually accepted the
  /// insert (network died on the response), the duplicate-PK error is
  /// caught and treated as success — no double-create.
  Future<String> createTurf(Map<String, dynamic> data,
      {String? turfId, int retryCount = 5}) async {
    data['created_at'] = DateTime.now().toIso8601String();
    data['is_approved'] = false;
    data['verification_status'] = 'PENDING';

    // Sanitize data to prevent issues
    data = _sanitizeTurfData(data);

    // F4: always have a stable id so retries are idempotent.
    final stableId = turfId ?? _uuid.v4();

    Exception? lastError;

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        final insertData = Map<String, dynamic>.from(data)..['id'] = stableId;
        await _client.from('turfs').insert(insertData);
        return stableId;
      } catch (e) {
        // F4: if duplicate PK, the previous attempt actually succeeded.
        final lower = e.toString().toLowerCase();
        if (lower.contains('duplicate key') ||
            lower.contains('already exists') ||
            lower.contains('23505')) {
          return stableId;
        }
        if (_isMissingRenovationColumnError(e)) {
          final fallbackData = Map<String, dynamic>.from(data)
            ..remove('renovation_net_numbers')
            ..['id'] = stableId;

          if (data.containsKey('renovation_net_numbers')) {
            final pricingRules = Map<String, dynamic>.from(
              (fallbackData['pricing_rules'] as Map?)
                      ?.cast<String, dynamic>() ??
                  <String, dynamic>{},
            );
            pricingRules['renovation_net_numbers'] =
                (data['renovation_net_numbers'] as List?) ?? <int>[];
            fallbackData['pricing_rules'] = pricingRules;
          }

          await _client.from('turfs').insert(fallbackData);
          return stableId;
        }

        lastError = e is Exception ? e : Exception(e.toString());

        // F5 / Phase 4 Iter 8 DB-04: only retry on TRUE network markers.
        // Postgres/URI errors are real bugs and must surface immediately.
        final isRetryableError = _isRetryableNetworkError(e);

        if (isRetryableError && attempt < retryCount) {
          // Wait before retrying (exponential backoff with jitter)
          final delay =
              Duration(milliseconds: (500 * attempt) + (attempt * 100));
          await Future.delayed(delay);
          continue;
        }

        // For non-retryable errors or max retries reached
        if (!isRetryableError) {
          rethrow;
        }
      }
    }

    throw lastError ??
        Exception('Failed to create turf after $retryCount attempts');
  }

  /// Sanitize turf data to prevent database/URI errors.
  /// Phase 4 Iter 8 DB-09: log dropped items in debug mode so silent data
  /// loss is at least visible during development.
  Map<String, dynamic> _sanitizeTurfData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);

    // Ensure images have valid URLs
    if (sanitized.containsKey('images') && sanitized['images'] is List) {
      final images = sanitized['images'] as List;
      final kept = images.where((img) {
        if (img is Map) {
          final url = img['url']?.toString() ?? '';
          return url.isNotEmpty && UrlUtils.isValidUrl(url);
        }
        return false;
      }).toList();
      if (kDebugMode && kept.length != images.length) {
        debugPrint(
            '_sanitizeTurfData: dropped ${images.length - kept.length} invalid image entries');
      }
      sanitized['images'] = kept;
    }

    if (sanitized.containsKey('renovation_net_numbers') &&
        sanitized['renovation_net_numbers'] is List) {
      final nets = sanitized['renovation_net_numbers'] as List;
      final cleaned = nets
          .map<int>((e) => int.tryParse(e.toString()) ?? 0)
          .where((n) => n > 0)
          .toSet()
          .toList()
        ..sort();
      if (kDebugMode && cleaned.length != nets.length) {
        debugPrint(
            '_sanitizeTurfData: dropped ${nets.length - cleaned.length} invalid renovation_net_numbers entries');
      }
      sanitized['renovation_net_numbers'] = cleaned;
    }

    return sanitized;
  }

  /// Validate URL format. Phase 7 Iter 3 CLEAN-01: delegated to
  /// [UrlUtils.isValidUrl] so storage_service and database_service share a
  /// single source of truth.
  static bool _isValidUrl(String url) => UrlUtils.isValidUrl(url);

  bool _isMissingRenovationColumnError(Object error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('renovation_net_numbers') &&
        (errorStr.contains('could not find') ||
            errorStr.contains('column') ||
            errorStr.contains('pgrst204') ||
            errorStr.contains('42703'));
  }

  /// Update turf with retry logic for network issues.
  /// F1 (mass-assignment defense): owner cannot self-approve their own
  /// turf, cannot reassign ownership, cannot rewrite immutable id /
  /// created_at. See `_assertTurfWritable`.
  Future<void> updateTurf(String turfId, Map<String, dynamic> data,
      {int retryCount = 5}) async {
    data['updated_at'] = DateTime.now().toIso8601String();

    // Sanitize data to prevent issues
    data = _sanitizeTurfData(data);

    // F1: enforce blocked-column policy.
    _assertTurfWritable(data);

    Exception? lastError;

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _client.from('turfs').update(data).eq('id', turfId);
        return; // Success
      } catch (e) {
        if (_isMissingRenovationColumnError(e)) {
          final fallbackData = Map<String, dynamic>.from(data)
            ..remove('renovation_net_numbers');

          if (data.containsKey('renovation_net_numbers')) {
            final existing = await getTurf(turfId);
            final existingPricingRulesRaw = existing?['pricing_rules'];
            final pricingRules = Map<String, dynamic>.from(
              (existingPricingRulesRaw is Map
                  ? existingPricingRulesRaw.cast<String, dynamic>()
                  : <String, dynamic>{}),
            );
            pricingRules['renovation_net_numbers'] =
                (data['renovation_net_numbers'] as List?) ?? <int>[];
            fallbackData['pricing_rules'] = pricingRules;
          }

          await _client.from('turfs').update(fallbackData).eq('id', turfId);
          return;
        }

        lastError = e is Exception ? e : Exception(e.toString());

        // F5 / Phase 4 Iter 8 DB-04: only retry on TRUE network markers.
        final isRetryableError = _isRetryableNetworkError(e);

        if (isRetryableError && attempt < retryCount) {
          // Wait before retrying (exponential backoff with jitter)
          final delay =
              Duration(milliseconds: (500 * attempt) + (attempt * 100));
          await Future.delayed(delay);
          continue;
        }

        // For non-retryable errors or max retries reached
        if (!isRetryableError) {
          rethrow;
        }
      }
    }

    throw lastError ??
        Exception('Failed to update turf after $retryCount attempts');
  }

  // =====================================================
  // SLOT OPERATIONS
  // =====================================================

  /// Stream turf slots for a date using the single-filter stream with client-side date filter.
  /// Also provides a direct query method to avoid stream row limit issues.
  Stream<List<Map<String, dynamic>>> streamTurfSlots(
      String turfId, String date) {
    return _client
        .from('slots')
        .stream(primaryKey: ['id'])
        .eq('turf_id', turfId)
        .order('start_time', ascending: true)
        .map((rows) => rows.where((row) => row['date'] == date).toList());
  }

  /// Fetch all slots for a specific turf and date (no row limit issues).
  /// Use this instead of streamTurfSlots for reliable full 24-hour slot loading.
  Future<List<Map<String, dynamic>>> fetchTurfSlotsForDate(
      String turfId, String date) async {
    return await _client
        .from('slots')
        .select()
        .eq('turf_id', turfId)
        .eq('date', date)
        .order('start_time', ascending: true);
  }

  /// Check if slots exist for a date
  Future<bool> slotsExistForDate(String turfId, String date) async {
    final result = await _client
        .from('slots')
        .select('id')
        .eq('turf_id', turfId)
        .eq('date', date)
        .limit(1);
    return result.isNotEmpty;
  }

  /// Check if slots exist for a date and specific net
  Future<bool> slotsExistForDateAndNet(
      String turfId, String date, int netNumber) async {
    final result = await _client
        .from('slots')
        .select('id')
        .eq('turf_id', turfId)
        .eq('date', date)
        .eq('net_number', netNumber)
        .limit(1);
    return result.isNotEmpty;
  }

  /// Delete future available slots (for regeneration when settings change)
  /// Only deletes AVAILABLE slots from tomorrow onwards.
  /// Phase 4 Iter 8 DB-05: anchor `tomorrow` in UTC so the cutoff matches
  /// the `slots.date` column (Postgres `date` is UTC-naive).
  Future<int> deleteFutureAvailableSlots(String turfId) async {
    final tomorrowStr =
        _utcDateString(DateTime.now().toUtc().add(const Duration(days: 1)));

    // Delete all AVAILABLE slots from tomorrow onwards
    final result = await _client
        .from('slots')
        .delete()
        .eq('turf_id', turfId)
        .eq('status', 'AVAILABLE')
        .gte('date', tomorrowStr)
        .select('id');

    return result.length;
  }

  /// Delete available slots for a specific date (for regeneration)
  Future<int> deleteAvailableSlotsForDate(String turfId, String date) async {
    final result = await _client
        .from('slots')
        .delete()
        .eq('turf_id', turfId)
        .eq('status', 'AVAILABLE')
        .eq('date', date)
        .select('id');

    return result.length;
  }

  /// Delete all available slots for nets that exceed the current net count.
  /// Used when owner reduces the number of nets.
  /// Phase 4 Iter 8 DB-05: anchor `tomorrow` in UTC.
  Future<int> deleteSlotsForRemovedNets(
      String turfId, int currentNetCount) async {
    final tomorrowStr =
        _utcDateString(DateTime.now().toUtc().add(const Duration(days: 1)));

    // Delete all AVAILABLE slots for nets > currentNetCount from tomorrow onwards
    final result = await _client
        .from('slots')
        .delete()
        .eq('turf_id', turfId)
        .eq('status', 'AVAILABLE')
        .gt('net_number', currentNetCount)
        .gte('date', tomorrowStr)
        .select('id');

    return result.length;
  }

  /// Delete regeneratable slots for a date and net.
  /// Deletes AVAILABLE + ALL BLOCKED slots for a clean 24-hour regeneration.
  /// Only preserves BOOKED and RESERVED slots.
  Future<int> deleteAvailableSlotsForDateAndNet(
      String turfId, String date, int netNumber) async {
    // Delete AVAILABLE slots
    final result1 = await _client
        .from('slots')
        .delete()
        .eq('turf_id', turfId)
        .eq('date', date)
        .eq('net_number', netNumber)
        .eq('status', 'AVAILABLE')
        .select('id');

    // Delete ALL BLOCKED slots (auto-closed, period-closed, manually blocked)
    // This ensures a clean 24-hour set based on current operating hours
    final result2 = await _client
        .from('slots')
        .delete()
        .eq('turf_id', turfId)
        .eq('date', date)
        .eq('net_number', netNumber)
        .eq('status', 'BLOCKED')
        .select('id');

    return result1.length + result2.length;
  }

  /// Get existing slot start times for a date and net (to avoid duplicates)
  Future<Set<String>> getExistingSlotTimes(
      String turfId, String date, int netNumber) async {
    final result = await _client
        .from('slots')
        .select('start_time')
        .eq('turf_id', turfId)
        .eq('date', date)
        .eq('net_number', netNumber);

    return result.map<String>((row) => row['start_time'] as String).toSet();
  }

  /// Get slots for a date and net (for price sync)
  Future<List<Map<String, dynamic>>> getSlotsForDateAndNet(
    String turfId,
    String date,
    int netNumber,
  ) async {
    return await _client
        .from('slots')
        .select(
            'id, start_time, end_time, status, price, price_type, block_reason')
        .eq('turf_id', turfId)
        .eq('date', date)
        .eq('net_number', netNumber)
        .order('start_time', ascending: true);
  }

  /// Update slot pricing (price and price_type)
  Future<void> updateSlotPricing(
    String slotId,
    double price,
    String priceType,
  ) async {
    await _client.from('slots').update({
      'price': price,
      'price_type': priceType,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  /// Update only the slot price (e.g., after a booking with custom amount)
  Future<void> updateSlotPrice(String slotId, double price) async {
    await _client.from('slots').update({
      'price': price,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', slotId);
  }

  /// Batch create slots (upsert with ignore duplicates for robustness)
  Future<void> batchCreateSlots(List<Map<String, dynamic>> slotsData) async {
    await _client.from('slots').upsert(
          slotsData,
          onConflict: 'turf_id,date,start_time,net_number',
          ignoreDuplicates: true,
        );
  }

  /// Block slot with retry logic.
  /// Phase 4 Iter 8 DB-04: shared `_isRetryableNetworkError` so this path
  /// retries on the same markers as createTurf/updateTurf (previously
  /// missed `socketexception` and `clientexception`).
  Future<void> blockSlot(String slotId, String ownerId, String? reason,
      {int retryCount = 3}) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _client.from('slots').update({
          'status': 'BLOCKED',
          'blocked_by': ownerId,
          'block_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', slotId);
        return; // Success
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final isRetryableError = _isRetryableNetworkError(e);

        if (isRetryableError && attempt < retryCount) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else if (!isRetryableError) {
          rethrow;
        }
      }
    }

    throw lastError ??
        Exception('Failed to block slot after $retryCount attempts');
  }

  /// Unblock slot with retry logic.
  /// [overrideMarker] — if provided, stores a marker in block_reason on the
  /// now-AVAILABLE slot so that sync can distinguish manual overrides from
  /// normal available slots (e.g. 'Day opened by owner').
  /// Phase 4 Iter 8 DB-04: shared `_isRetryableNetworkError`.
  Future<void> unblockSlot(String slotId,
      {int retryCount = 3, String? overrideMarker}) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _client.from('slots').update({
          'status': 'AVAILABLE',
          'blocked_by': null,
          'block_reason': overrideMarker,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', slotId);
        return; // Success
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final isRetryableError = _isRetryableNetworkError(e);

        if (isRetryableError && attempt < retryCount) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else if (!isRetryableError) {
          rethrow;
        }
      }
    }

    throw lastError ??
        Exception('Failed to unblock slot after $retryCount attempts');
  }

  /// Reserve slot (using RPC).
  /// Phase 7 Iter 3 EDGE-03: wrap in shared retry loop so a 1-second
  /// network blip does not leave the customer thinking the slot is
  /// unavailable. RPC is server-side conditional (only succeeds if the
  /// slot is currently AVAILABLE), so a retry that races with a real
  /// reservation simply returns false on the second attempt.
  Future<bool> reserveSlot({
    required String slotId,
    required String userId,
    required int reservationMinutes,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final result = await _client.rpc('reserve_slot', params: {
          'p_slot_id': slotId,
          'p_reserved_by': userId,
          'p_reservation_minutes': reservationMinutes,
        });
        return result == true;
      } catch (e) {
        lastError = e;
        if (attempt < 3 && _isRetryableNetworkError(e)) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('reserveSlot failed after 3 attempts');
  }

  /// Release slot (using RPC). Phase 4 Iter 8 DB-08: surface the RPC's
  /// boolean result so callers can distinguish success from no-op (slot
  /// already AVAILABLE / not held by this user).
  /// Phase 7 Iter 3 EDGE-03: retry wrap. Release is idempotent server-side
  /// (a second release of an already-AVAILABLE slot just returns false).
  Future<bool> releaseSlot(String slotId) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final result = await _client.rpc('release_slot', params: {
          'p_slot_id': slotId,
        });
        return result == true;
      } catch (e) {
        lastError = e;
        if (attempt < 3 && _isRetryableNetworkError(e)) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('releaseSlot failed after 3 attempts');
  }

  /// Book slot (using RPC). Phase 4 Iter 8 DB-08: surface the RPC result.
  /// Phase 7 Iter 3 EDGE-03: retry wrap. Server-side guard ensures only
  /// a slot in RESERVED-by-this-user state flips to BOOKED, so a retry
  /// after a successful first attempt simply returns false.
  Future<bool> bookSlot(String slotId) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final result = await _client.rpc('book_slot', params: {
          'p_slot_id': slotId,
        });
        return result == true;
      } catch (e) {
        lastError = e;
        if (attempt < 3 && _isRetryableNetworkError(e)) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('bookSlot failed after 3 attempts');
  }

  // =====================================================
  // BOOKING OPERATIONS
  // =====================================================

  /// Create booking atomically (using RPC).
  /// Phase 4 Iter 8 DB-01: explicit null + type guard + error wrapping.
  /// Previously `result as String` would throw an opaque `_TypeError` if
  /// the RPC returned null (constraint failure path) or threw a
  /// PostgrestException — callers had no way to surface a real reason.
  ///
  /// Phase 4 Iter 8 DB-10 (deferred): true idempotency (retry-safe booking
  /// across mid-RPC network failure) requires `create_booking_atomic` to
  /// accept an idempotency key server-side. Tracked separately — this code
  /// path currently relies on the unique partial index on
  /// `bookings(slot_id) WHERE booking_status='CONFIRMED'` to prevent
  /// double-confirms; a network-level retry between request and response
  /// could still surface a 23505 to the caller as an error rather than
  /// silent success.
  ///
  /// Phase 7 Iter 3 EDGE-01 (KNOWN LIMITATION, NOT FIXED CLIENT-SIDE):
  /// If the network fails AFTER the server commits the booking but
  /// BEFORE the success response reaches the client, the user will see
  /// an error and may retry — the retry will hit the unique partial
  /// index and fail with 23505, leaving a phantom successful booking on
  /// the server. We deliberately do NOT add a client-side
  /// catch-and-lookup workaround here because:
  ///   1. Looking up by slot_id after a 23505 to recover the booking row
  ///      is racy (another user could have just booked it post-cancel).
  ///   2. The proper fix is server-side — `create_booking_atomic` needs
  ///      to accept an idempotency key (e.g. client-generated UUID) and
  ///      return the existing booking row on duplicate key.
  /// When that DB function ships, this method should be updated to send
  /// the key and convert 23505 into a successful return path.
  Future<String> createBookingAtomic({
    required String slotId,
    required Map<String, dynamic> bookingData,
  }) async {
    try {
      final result = await _client.rpc('create_booking_atomic', params: {
        'p_slot_id': slotId,
        'p_booking_data': bookingData,
      });
      if (result is String && result.isNotEmpty) return result;
      throw StateError(
          'create_booking_atomic returned unexpected result: $result');
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint('create_booking_atomic failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }

  /// Cancel booking (using RPC)
  Future<bool> cancelBooking({
    required String bookingId,
    required String slotId,
    required String cancelledBy,
    String? reason,
  }) async {
    final result = await _client.rpc('cancel_booking', params: {
      'p_booking_id': bookingId,
      'p_slot_id': slotId,
      'p_cancelled_by': cancelledBy,
      'p_cancel_reason': reason,
    });
    return result == true;
  }

  /// Stream owner bookings.
  /// Phase 4 Iter 8 DB-02: `.eq('owner_id', ...)` on the realtime stream
  /// itself instead of fetching every row in `bookings` and filtering
  /// client-side. Cuts traffic and removes the row-leak vector.
  Stream<List<Map<String, dynamic>>> streamOwnerBookings(String ownerId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('owner_id', ownerId)
        .order('booking_date', ascending: false);
  }

  /// Get booking by ID. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<Map<String, dynamic>?> getBooking(String bookingId) async {
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .eq('id', bookingId)
        .maybeSingle();
  }

  /// Get bookings for a date. Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<List<Map<String, dynamic>>> getBookingsForDate(
    String ownerId,
    String date,
  ) async {
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .eq('owner_id', ownerId)
        .eq('booking_date', date)
        .order('start_time', ascending: true);
  }

  /// Get bookings created by a player account.
  /// Phase 4 Iter 8 DB-03: explicit column allowlist.
  Future<List<Map<String, dynamic>>> getPlayerBookings(String userId) async {
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .eq('user_id', userId)
        .order('booking_date', ascending: false)
        .order('start_time', ascending: true);
  }

  /// Stream bookings for owner's turfs.
  /// Note (Phase 4 Iter 8 DB-02): supabase_flutter realtime streams
  /// support a single equality filter only — `inFilter` cannot be applied
  /// at the stream level. We keep the client-side `where(...)` here and
  /// rely on RLS for hard isolation; consider switching to a per-turf
  /// stream fan-out if owner turf counts ever exceed ~20.
  ///
  /// Phase 7 Iter 3 EDGE-02 (TODO): once any single owner crosses ~20
  /// turfs, this client-side filter becomes a real scaling problem —
  /// every booking event from every owner on the platform is sent to
  /// every device just to be discarded. Switch to per-turf stream
  /// fan-out (one channel per turf, merged) at that point. For now we
  /// emit a `kDebugMode` warning so the threshold is visible during dev.
  Stream<List<Map<String, dynamic>>> streamBookingsByTurfs(
      List<String> turfIds) {
    if (turfIds.isEmpty) {
      return Stream.value([]);
    }
    if (kDebugMode && turfIds.length > 20) {
      debugPrint(
        'streamBookingsByTurfs: owner has ${turfIds.length} turfs (> 20). '
        'Consider switching to per-turf realtime channel fan-out — current '
        'implementation receives all bookings platform-wide and filters '
        'client-side.',
      );
    }
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .order('booking_date', ascending: false)
        .map((rows) =>
            rows.where((row) => turfIds.contains(row['turf_id'])).toList());
  }

  /// Get today's bookings. Phase 4 Iter 8 DB-03: column allowlist.
  Future<List<Map<String, dynamic>>> getTodaysBookings(
    List<String> turfIds,
    String date,
  ) async {
    if (turfIds.isEmpty) return [];
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .inFilter('turf_id', turfIds)
        .eq('booking_date', date)
        .eq('booking_status', 'CONFIRMED')
        .order('start_time', ascending: true);
  }

  /// Get pending payments (includes both PENDING and PAY_AT_TURF statuses).
  /// Phase 4 Iter 8 DB-03: column allowlist.
  Future<List<Map<String, dynamic>>> getPendingPayments(
      List<String> turfIds) async {
    if (turfIds.isEmpty) return [];
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .inFilter('turf_id', turfIds)
        .inFilter('payment_status', ['PAY_AT_TURF', 'PENDING'])
        .eq('booking_status', 'CONFIRMED')
        .order('booking_date', ascending: false);
  }

  /// Get recent bookings across all turfs (one-time fetch, limited).
  /// Phase 4 Iter 8 DB-03: column allowlist.
  Future<List<Map<String, dynamic>>> getRecentBookings(
    List<String> turfIds, {
    int limit = 5,
  }) async {
    if (turfIds.isEmpty) return [];
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .inFilter('turf_id', turfIds)
        .eq('booking_status', 'CONFIRMED')
        .order('created_at', ascending: false)
        .limit(limit);
  }

  /// Update booking. F3 (mass-assignment defense): only soft fields
  /// (`cancel_reason`, `notes`, `cancelled_*`, `updated_at`) are allowed.
  /// Money/identity columns must use a dedicated method like
  /// [markBookingPaymentReceived]. The DB-side immutable-columns trigger
  /// (Iteration 1) is the second line of defense.
  Future<void> updateBooking(
      String bookingId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    _assertBookingWritable(data);
    await _client.from('bookings').update(data).eq('id', bookingId);
  }

  /// F3: dedicated method for marking an offline booking as paid. This is
  /// the ONLY app code path allowed to flip `payment_status` to 'PAID'.
  /// Phase 4 Iter 8 DB-06: returns true only if exactly one row was
  /// updated. Previously the call resolved silently when the bookingId
  /// was wrong / RLS denied / the row was already cancelled — the owner
  /// believed payment was recorded when in reality nothing changed.
  Future<bool> markBookingPaymentReceived(String bookingId) async {
    final updated = await _client
        .from('bookings')
        .update({
          'payment_status': 'PAID',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', bookingId)
        .select('id');
    return updated.length == 1;
  }

  /// Get booking by slot ID. Phase 4 Iter 8 DB-03: column allowlist.
  Future<Map<String, dynamic>?> getBookingBySlotId(String slotId) async {
    return await _client
        .from('bookings')
        .select(_publicBookingColumns)
        .eq('slot_id', slotId)
        .eq('booking_status', 'CONFIRMED')
        .maybeSingle();
  }
}
