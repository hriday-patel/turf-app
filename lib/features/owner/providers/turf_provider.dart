import 'package:flutter/material.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/supabase_service.dart';
import '../../../core/constants/enums.dart';

/// Turf Provider
/// Manages turf-related state and operations
class TurfProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  List<TurfModel> _turfs = [];
  TurfModel? _selectedTurf;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<TurfModel> get turfs => _turfs;
  List<TurfModel> get approvedTurfs => 
      _turfs.where((t) => t.isApproved).toList();
  List<TurfModel> get pendingTurfs => 
      _turfs.where((t) => t.verificationStatus == VerificationStatus.pending).toList();
  TurfModel? get selectedTurf => _selectedTurf;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalTurfs => _turfs.length;
  int get approvedCount => approvedTurfs.length;
  int get pendingCount => pendingTurfs.length;

  /// Load turfs for an owner
  void loadOwnerTurfs(String ownerId) {
    _supabaseService.streamOwnerTurfs(ownerId).listen(
      (rows) {
        _turfs = rows.map((row) => TurfModel.fromMap(row)).toList();
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load turfs: $error';
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
        'open_time': openTime,
        'close_time': closeTime,
        'slot_duration_minutes': slotDurationMinutes,
        'days_open': daysOpen,
        'pricing_rules': pricingRules.toMap(),
        'public_holidays': [],
        'images': images.map((i) => i.toMap()).toList(),
        'is_approved': false,
        'verification_status': 'PENDING',
      };

      final resultTurfId =
          await _supabaseService.createTurf(data, turfId: turfId);
      
      _isLoading = false;
      notifyListeners();
      
      return resultTurfId;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to add turf: $e';
      notifyListeners();
      return null;
    }
  }

  /// Update turf
  Future<bool> updateTurf(String turfId, Map<String, dynamic> data) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseService.updateTurf(turfId, data);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to update turf: $e';
      notifyListeners();
      return false;
    }
  }

  /// Update pricing rules
  Future<bool> updatePricingRules(String turfId, PricingRules rules) async {
    return await updateTurf(turfId, {'pricing_rules': rules.toMap()});
  }

  /// Add public holiday
  Future<bool> addPublicHoliday(String turfId, String date) async {
    final turf = _turfs.firstWhere((t) => t.turfId == turfId);
    final holidays = [...turf.publicHolidays, date];
    return await updateTurf(turfId, {'public_holidays': holidays});
  }

  /// Remove public holiday
  Future<bool> removePublicHoliday(String turfId, String date) async {
    final turf = _turfs.firstWhere((t) => t.turfId == turfId);
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
}
