import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/database_service.dart';
import '../../../core/constants/enums.dart';

/// Turf Provider
/// Manages turf-related state and operations
class TurfProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<TurfModel> _turfs = [];
  TurfModel? _selectedTurf;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _turfsSubscription;
  final Set<String> _pendingTurfStatusOps = {};

  // Getters
  List<TurfModel> get turfs => _turfs;
  List<TurfModel> get approvedTurfs => _turfs
      .where((t) => t.verificationStatus == VerificationStatus.approved)
      .toList();
  List<TurfModel> get pendingTurfs => _turfs
      .where((t) => t.verificationStatus == VerificationStatus.pending)
      .toList();
  TurfModel? get selectedTurf => _selectedTurf;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalTurfs => _turfs.length;
  int get approvedCount => approvedTurfs.length;
  int get pendingCount => pendingTurfs.length;
  bool isTurfStatusUpdating(String turfId) =>
      _pendingTurfStatusOps.contains(turfId);

  /// Load turfs for an owner
  void loadOwnerTurfs(String ownerId) {
    // Cancel previous subscription to prevent memory leaks
    _turfsSubscription?.cancel();
    _turfsSubscription = _dbService.streamOwnerTurfs(ownerId).listen(
      (rows) {
        _turfs = rows.map((row) => TurfModel.fromMap(row)).toList();
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = _friendlyError(
          error,
          fallback: 'Could not load turfs. Please try again.',
        );
        notifyListeners();
      },
    );
  }

  /// Get turf IDs for the current owner
  List<String> get turfIds => _turfs.map((t) => t.turfId).toList();

  /// Add a new turf
  Future<String?> addTurf({
    String? turfId,
    required String ownerId,
    required String turfName,
    required String city,
    required String address,
    required TurfType turfType,
    String? description,
    int numberOfNets = 1,
    required String openTime,
    required String closeTime,
    required int slotDurationMinutes,
    required List<String> daysOpen,
    required PricingRules pricingRules,
    required List<TurfImage> images,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final data = {
        'owner_id': ownerId,
        'turf_name': turfName,
        'city': city,
        'address': address,
        'turf_type': turfType.value,
        'description': description,
        'number_of_nets': numberOfNets,
        'status': 'OPEN',
        'open_time': openTime,
        'close_time': closeTime,
        'slot_duration_minutes': slotDurationMinutes,
        'days_open': daysOpen,
        'pricing_rules': pricingRules.toMap(),
        'renovation_net_numbers': <int>[],
        'public_holidays': [],
        'images': images.map((i) => i.toMap()).toList(),
        'is_approved': false,
        'verification_status': 'PENDING',
      };

      final resultTurfId = await _dbService.createTurf(data, turfId: turfId);

      _isLoading = false;
      notifyListeners();

      return resultTurfId;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not add turf. Please try again.',
      );
      notifyListeners();
      return null;
    }
  }

  /// Update turf status (open/closed/renovation)
  Future<bool> updateTurfStatus(
    String turfId,
    TurfStatus status, {
    List<int>? renovationNetNumbers,
  }) async {
    if (_pendingTurfStatusOps.contains(turfId)) {
      return false;
    }

    _pendingTurfStatusOps.add(turfId);
    try {
      final normalizedRenovationNets = <int>[];
      if (status == TurfStatus.renovation) {
        normalizedRenovationNets.addAll(
          (renovationNetNumbers ?? <int>[])
              .where((n) => n > 0)
              .toSet()
              .toList(),
        );
        normalizedRenovationNets.sort();
      }

      return await updateTurf(turfId, {
        'status': status.value,
        'renovation_net_numbers': normalizedRenovationNets,
      });
    } finally {
      _pendingTurfStatusOps.remove(turfId);
    }
  }

  /// Update turf
  Future<bool> updateTurf(String turfId, Map<String, dynamic> data) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Check if slot-affecting settings are being changed
      final slotAffectingKeys = [
        'slot_duration_minutes',
        'number_of_nets',
        'pricing_rules',
        'open_time',
        'close_time',
        'days_open',
      ];

      final hasSlotAffectingChanges =
          data.keys.any((key) => slotAffectingKeys.contains(key));

      await _dbService.updateTurf(turfId, data);

      // If slot-affecting settings changed, delete future available slots
      // so they get regenerated with new settings
      if (hasSlotAffectingChanges) {
        final deletedCount =
            await _dbService.deleteFutureAvailableSlots(turfId);
        debugPrint(
            'Deleted $deletedCount future available slots for regeneration');

        // If net count was reduced, also delete slots for removed nets
        if (data.containsKey('number_of_nets')) {
          final newNetCount = data['number_of_nets'] as int;
          final removedNetSlotsCount =
              await _dbService.deleteSlotsForRemovedNets(turfId, newNetCount);
          debugPrint('Deleted $removedNetSlotsCount slots for removed nets');
        }
      }

      // Update the local turf immediately for instant UI feedback
      final index = _turfs.indexWhere((t) => t.turfId == turfId);
      if (index != -1) {
        final currentTurf = _turfs[index];
        final updatedMap = currentTurf.toMap();

        // Phase 3 Iter6 CLEAN-05: collapsed a 35-line if/else ladder that
        // mapped each known key to itself — every branch was identical to
        // the default `updatedMap[key] = value` path, so it added zero
        // behavior and lots of maintenance burden.
        updatedMap.addAll(data);

        updatedMap['updated_at'] = DateTime.now().toIso8601String();

        try {
          _turfs[index] = TurfModel.fromMap(updatedMap);

          // Also update selected turf if it's the same
          if (_selectedTurf?.turfId == turfId) {
            _selectedTurf = _turfs[index];
          }
        } catch (parseError) {
          // If parsing fails, we'll rely on the next refresh
          debugPrint('Failed to parse updated turf locally: $parseError');
        }
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not update turf. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Force refresh turfs from database
  Future<void> refreshTurfs(String ownerId) async {
    try {
      final rows = await _dbService.getOwnerTurfs(ownerId);
      _turfs = rows.map((row) => TurfModel.fromMap(row)).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = _friendlyError(
        e,
        fallback: 'Could not refresh turfs. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Update pricing rules
  Future<bool> updatePricingRules(String turfId, PricingRules rules) async {
    return await updateTurf(turfId, {'pricing_rules': rules.toMap()});
  }

  /// Add public holiday
  Future<bool> addPublicHoliday(String turfId, String date) async {
    // Phase 3 Iter6 BUG-13 fix: don't crash with StateError when the turf
    // isn't in the local cache (e.g. deep link before stream loaded).
    final turf = getTurfById(turfId);
    if (turf == null) {
      _errorMessage = 'Turf not found. Please refresh and try again.';
      notifyListeners();
      return false;
    }
    // Phase 3 Iter6 BUG-14 fix: skip if already present so double-taps don't
    // create duplicate entries that bloat the list.
    if (turf.publicHolidays.contains(date)) return true;
    final holidays = [...turf.publicHolidays, date];
    return await updateTurf(turfId, {'public_holidays': holidays});
  }

  /// Remove public holiday
  Future<bool> removePublicHoliday(String turfId, String date) async {
    // Phase 3 Iter6 BUG-13 fix: safe lookup, no StateError on missing turf.
    final turf = getTurfById(turfId);
    if (turf == null) {
      _errorMessage = 'Turf not found. Please refresh and try again.';
      notifyListeners();
      return false;
    }
    final holidays = turf.publicHolidays.where((h) => h != date).toList();
    return await updateTurf(turfId, {'public_holidays': holidays});
  }

  /// Select a turf for viewing/editing
  void selectTurf(TurfModel turf) {
    _selectedTurf = turf;
    notifyListeners();
  }

  /// Clear selected turf
  void clearSelectedTurf() {
    _selectedTurf = null;
    notifyListeners();
  }

  /// Get turf by ID
  TurfModel? getTurfById(String turfId) {
    try {
      return _turfs.firstWhere((t) => t.turfId == turfId);
    } catch (e) {
      return null;
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Phase 3 Iter6 ERR-04 fix: never leak raw backend exception text to
  /// production users (OWASP A09). In debug builds we still surface the
  /// real error so developers can diagnose.
  String _friendlyError(Object error, {required String fallback}) {
    if (kDebugMode) {
      return '$fallback (debug: $error)';
    }
    return fallback;
  }

  @override
  void dispose() {
    _turfsSubscription?.cancel();
    super.dispose();
  }
}
