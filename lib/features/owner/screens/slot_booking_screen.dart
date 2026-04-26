import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../providers/booking_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/slot_business_rules.dart';
import '../../../core/constants/strings.dart';
import '../../../data/services/database_service.dart';

/// Owner-facing Booking Dashboard screen.
///
/// Lets the venue owner browse all generated slots for a selected
/// turf+net+date, toggle entire days or time-periods open/closed
/// (with manual per-slot overrides preserved across navigation),
/// and create manual phone/walk-in bookings via an in-screen
/// `_BookingDialog` followed by a `_BookingSuccessPopup` that can
/// dispatch confirmation/receipt messages over WhatsApp.
///
/// Lifecycle: subscribes to [AppRoutes.routeObserver] in
/// `didChangeDependencies` and refreshes data in `didPopNext` so
/// state stays consistent when returning from booking-detail or
/// turf-edit screens. A monotonically increasing
/// `_loadSlotsGeneration` token guards against stale async writes
/// from rapid date/turf switches.
///
/// Security: all mutating actions (block/unblock/cancel-booking)
/// require a non-null `AuthProvider.currentUserId`; if the session
/// has expired the user is shown a toast and the action is aborted
/// rather than recorded against an empty owner id. Block-reasons
/// are written through [BlockReason] constants for cross-screen
/// consistency with `slot_management_screen.dart`.
///
/// Performance: uses [Selector] over [Provider.of]/[Consumer] for
/// turf and slot streams, lazily generates section animations, and
/// delegates time-bucket logic to
/// [SlotBusinessRules.periodForHour].
class SlotBookingScreen extends StatefulWidget {
  const SlotBookingScreen({super.key});

  @override
  State<SlotBookingScreen> createState() => _SlotBookingScreenState();
}

class _SlotBookingScreenState extends State<SlotBookingScreen>
    with RouteAware, TickerProviderStateMixin {
  TurfModel? _selectedTurf;
  int _selectedNetNumber = 1;
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  bool _isSidebarVisible = false;
  int _loadSlotsGeneration = 0;

  // Toggle states stored per turf+net+date combination
  // Key format: "turfId_netNumber_date"
  final Map<String, bool> _dayOpenStates = {};
  final Map<String, bool> _morningOpenStates = {};
  final Map<String, bool> _afternoonOpenStates = {};
  final Map<String, bool> _eveningOpenStates = {};
  final Map<String, bool> _nightOpenStates = {};

  // Concurrency guards to prevent stacked refreshes / bulk-toggle races
  bool _isRefreshing = false;
  bool _isApplyingBulk = false;

  // Track manually overridden slots (open even when period is closed)
  // Key format: "turfId_netNumber_slotId"
  final Set<String> _manuallyOpenedSlots = {};

  // Section entrance animations
  late final AnimationController _sectionAnimController;
  late final List<Animation<double>> _sectionFadeAnims;
  late final List<Animation<Offset>> _sectionSlideAnims;

  // Helper to generate unique key for current turf+net+date
  String get _currentStateKey {
    if (_selectedTurf == null) return '';
    final dateStr = _selectedDate.toIso8601String().split('T')[0];
    return '${_selectedTurf!.turfId}_${_selectedNetNumber}_$dateStr';
  }

  // Helper to generate slot override key
  String _getSlotOverrideKey(String slotId) {
    if (_selectedTurf == null) return '';
    return '${_selectedTurf!.turfId}_${_selectedNetNumber}_$slotId';
  }

  // Getters for current toggle states
  bool get _isDayOpen => _dayOpenStates[_currentStateKey] ?? true;
  bool get _isMorningOpen => _morningOpenStates[_currentStateKey] ?? true;
  bool get _isAfternoonOpen => _afternoonOpenStates[_currentStateKey] ?? true;
  bool get _isEveningOpen => _eveningOpenStates[_currentStateKey] ?? true;
  bool get _isNightOpen => _nightOpenStates[_currentStateKey] ?? true;

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime get _minSelectableDate {
    return _dateOnly(DateTime.now());
  }

  DateTime get _maxSelectableDate {
    final min = _minSelectableDate;
    return DateTime(min.year + 1, min.month, min.day)
        .subtract(const Duration(days: 1));
  }

  bool _isDateWithinBookingRange(DateTime value) {
    final day = _dateOnly(value);
    return !day.isBefore(_minSelectableDate) &&
        !day.isAfter(_maxSelectableDate);
  }

  DateTime _clampDateToBookingRange(DateTime value) {
    final day = _dateOnly(value);
    if (day.isBefore(_minSelectableDate)) return _minSelectableDate;
    if (day.isAfter(_maxSelectableDate)) return _maxSelectableDate;
    return day;
  }

  @override
  void initState() {
    super.initState();
    final today = _minSelectableDate;
    _selectedDate = today;
    _focusedDate = today;
    // Section entrance staggered animation (7 sections: venue, calendar, control, night, morning, afternoon, evening)
    _sectionAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _sectionFadeAnims = List.generate(7, (i) {
      final start = i * 0.09;
      final end = (start + 0.44).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _sectionAnimController,
            curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _sectionSlideAnims = List.generate(7, (i) {
      final start = i * 0.09;
      final end = (start + 0.44).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 12), end: Offset.zero)
          .animate(
        CurvedAnimation(
            parent: _sectionAnimController,
            curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _sectionAnimController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAllData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRoutes.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _sectionAnimController.dispose();
    AppRoutes.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);

      // Clear cached toggle states so they re-derive from fresh DB data
      // (turf config may have changed, e.g. daysOpen edited)
      _dayOpenStates.clear();
      _morningOpenStates.clear();
      _afternoonOpenStates.clear();
      _eveningOpenStates.clear();
      _nightOpenStates.clear();
      // Note: _manuallyOpenedSlots is NOT cleared here — it is rebuilt
      // from DB override markers in _updateToggleStatesFromSlots()

      // Force refresh turfs first to get latest verification status
      final ownerId = authProvider.currentUserId;
      if (ownerId == null) {
        if (mounted) {
          showAppToast(context, AppStrings.slotBookingSessionExpired,
              type: ToastType.error);
        }
        return;
      }
      await turfProvider.refreshTurfs(ownerId);

      if (!mounted) return;
      // Re-initialize with only approved turfs
      _initializeData();
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${AppStrings.slotBookingRefreshFailed}: $e',
            type: ToastType.error);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void _initializeData() {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final approvedTurfs = turfProvider.turfs
        .where((t) => t.verificationStatus == VerificationStatus.approved)
        .toList();

    // Check if currently selected turf is still approved
    if (_selectedTurf != null) {
      final stillApproved =
          approvedTurfs.any((t) => t.turfId == _selectedTurf!.turfId);
      if (!stillApproved) {
        // Current turf is no longer approved, clear selection
        setState(() {
          _selectedTurf = null;
          _selectedNetNumber = 1;
        });
      } else {
        final refreshedSelectedTurf = approvedTurfs.firstWhere(
          (t) => t.turfId == _selectedTurf!.turfId,
        );
        if (refreshedSelectedTurf != _selectedTurf) {
          setState(() {
            _selectedTurf = refreshedSelectedTurf;
          });
        }
      }
    }

    // If no turf selected but we have approved turfs, select first one
    if (_selectedTurf == null && approvedTurfs.isNotEmpty) {
      final firstTurf = approvedTurfs.first;
      final selectableNets = _getSelectableNets(firstTurf);
      setState(() {
        _selectedTurf = firstTurf;
        _selectedNetNumber =
            selectableNets.isNotEmpty ? selectableNets.first : 1;
      });
    }

    _ensureSelectedNetIsAllowed();

    if (_selectedTurf != null) {
      _loadSlots();
    }
  }

  Future<void> _loadSlots() async {
    if (_selectedTurf == null) return;

    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final refreshedSelectedTurf =
        turfProvider.getTurfById(_selectedTurf!.turfId);
    if (refreshedSelectedTurf == null) return;
    _selectedTurf = refreshedSelectedTurf;

    _ensureSelectedNetIsAllowed();

    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final dateStr = _selectedDate.toIso8601String().split('T')[0];

    final turfId = _selectedTurf!.turfId;
    final generation = ++_loadSlotsGeneration;
    try {
      await slotProvider.generateSlots(turf: _selectedTurf!, date: dateStr);
      if (!mounted || generation != _loadSlotsGeneration) return;
      await slotProvider.loadSlots(turfId, dateStr);
      if (mounted && generation == _loadSlotsGeneration) {
        _updateToggleStatesFromSlots();
      }
    } catch (e) {
      if (mounted && generation == _loadSlotsGeneration) {
        showAppToast(context, '${AppStrings.slotBookingLoadFailed}: $e',
            type: ToastType.error);
      }
    }
  }

  /// Sync toggle states from loaded slot data.
  /// Derives toggle state from actual DB slot statuses so that
  /// owner's manual overrides (DAY OPEN on a closed day) persist
  /// across navigation (home → back, date switches, etc.).
  void _updateToggleStatesFromSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    if (slotProvider.slots.isEmpty || _selectedTurf == null) return;

    final netSlots = slotProvider.slots
        .where((s) => s.netNumber == _selectedNetNumber)
        .toList();
    if (netSlots.isEmpty) return;

    // Always rebuild _manuallyOpenedSlots from DB override markers for the
    // current turf+net, regardless of whether toggles were already set.
    // Only remove entries for the current turf+net to preserve other contexts.
    final overridePrefix = '${_selectedTurf!.turfId}_${_selectedNetNumber}_';
    _manuallyOpenedSlots.removeWhere((key) => key.startsWith(overridePrefix));
    for (final slot in netSlots) {
      if (slot.blockReason == 'Day opened by owner' ||
          slot.blockReason == 'Opened by owner') {
        _manuallyOpenedSlots.add(_getSlotOverrideKey(slot.slotId));
      }
    }

    final key = _currentStateKey;
    // Don't overwrite toggle states if the user already interacted for this key
    if (_dayOpenStates.containsKey(key)) return;

    // Derive toggle state from actual slot statuses in the DB.
    // For each period, check if ANY operating-hour slot is AVAILABLE.
    // This replaces the old daysOpen check, so manual overrides persist.
    bool morningHasAvailable = false;
    bool afternoonHasAvailable = false;
    bool eveningHasAvailable = false;
    bool nightHasAvailable = false;

    for (final slot in netSlots) {
      // Only consider slots within operating hours for toggle derivation
      if (!_isSlotWithinOperatingHours(slot)) continue;
      if (slot.status != SlotStatus.available) continue;

      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      if (hour >= 6 && hour < 12) {
        morningHasAvailable = true;
      } else if (hour >= 12 && hour < 18) {
        afternoonHasAvailable = true;
      } else if (hour >= 18 && hour < 24) {
        eveningHasAvailable = true;
      } else {
        nightHasAvailable = true;
      }
    }

    setState(() {
      _morningOpenStates[key] = morningHasAvailable;
      _afternoonOpenStates[key] = afternoonHasAvailable;
      _eveningOpenStates[key] = eveningHasAvailable;
      _nightOpenStates[key] = nightHasAvailable;
      _dayOpenStates[key] = morningHasAvailable ||
          afternoonHasAvailable ||
          eveningHasAvailable ||
          nightHasAvailable;
    });
  }

  void _onTurfSelected(TurfModel turf) {
    if (_selectedTurf?.turfId == turf.turfId) {
      return;
    }
    // Verify turf is still approved before selecting
    if (turf.verificationStatus != VerificationStatus.approved) {
      showAppToast(context, AppStrings.slotBookingTurfNoLongerApproved,
          type: ToastType.warning);
      _refreshAllData();
      return;
    }

    final shouldCloseSidebar =
        turf.numberOfNets <= 1 || turf.turfType == TurfType.groundCricket;
    final selectableNets = _getSelectableNets(turf);
    setState(() {
      _selectedTurf = turf;
      _selectedNetNumber = selectableNets.isNotEmpty ? selectableNets.first : 1;
      if (shouldCloseSidebar) {
        _isSidebarVisible = false;
      }
    });
    _loadSlots();
  }

  void _onNetSelected(int netNumber) {
    if (_selectedTurf == null) return;
    if (_isNetUnderRenovation(_selectedTurf!, netNumber)) return;
    if (_selectedNetNumber == netNumber) return;
    setState(() {
      _selectedNetNumber = netNumber;
    });
    _loadSlots();
  }

  bool _isNetUnderRenovation(TurfModel turf, int netNumber) {
    return turf.status == TurfStatus.renovation &&
        turf.renovationNetNumbers.contains(netNumber);
  }

  List<int> _getSelectableNets(TurfModel turf) {
    return List<int>.generate(turf.numberOfNets, (index) => index + 1)
        .where((netNumber) => !_isNetUnderRenovation(turf, netNumber))
        .toList();
  }

  void _ensureSelectedNetIsAllowed() {
    final turf = _selectedTurf;
    if (turf == null) return;
    if (turf.numberOfNets <= 1) return;
    if (!_isNetUnderRenovation(turf, _selectedNetNumber)) return;

    final selectableNets = _getSelectableNets(turf);
    if (selectableNets.isEmpty) return;

    setState(() {
      _selectedNetNumber = selectableNets.first;
    });
  }

  void _onDateSelected(DateTime date) {
    final clampedDate = _clampDateToBookingRange(date);
    setState(() {
      _selectedDate = clampedDate;
      _focusedDate = clampedDate;
      // Note: We don't reset toggles - each date has its own state per turf+net
    });
    _loadSlots();
  }

  Future<void> _toggleDay(bool isOpen) async {
    if (_isApplyingBulk) return;
    final key = _currentStateKey;
    setState(() {
      _dayOpenStates[key] = isOpen;
      if (!isOpen) {
        _morningOpenStates[key] = false;
        _afternoonOpenStates[key] = false;
        _eveningOpenStates[key] = false;
        _nightOpenStates[key] = false;
      } else {
        _morningOpenStates[key] = true;
        _afternoonOpenStates[key] = true;
        _eveningOpenStates[key] = true;
        _nightOpenStates[key] = true;
      }
    });
    await _applyPeriodChanges();
    if (mounted) setState(() {});
  }

  Future<void> _togglePeriod(SlotPeriod period, bool isOpen) async {
    if (_isApplyingBulk) return;
    final key = _currentStateKey;
    setState(() {
      switch (period) {
        case SlotPeriod.morning:
          _morningOpenStates[key] = isOpen;
          break;
        case SlotPeriod.afternoon:
          _afternoonOpenStates[key] = isOpen;
          break;
        case SlotPeriod.evening:
          _eveningOpenStates[key] = isOpen;
          break;
        case SlotPeriod.night:
          _nightOpenStates[key] = isOpen;
          break;
      }
      // Update day toggle based on period states
      final allClosed = !(_morningOpenStates[key] ?? true) &&
          !(_afternoonOpenStates[key] ?? true) &&
          !(_eveningOpenStates[key] ?? true) &&
          !(_nightOpenStates[key] ?? true);
      if (allClosed) {
        _dayOpenStates[key] = false;
      } else if (!(_dayOpenStates[key] ?? true)) {
        _dayOpenStates[key] = true;
      }
    });
    await _applyPeriodChanges();
    if (mounted) setState(() {});
  }

  Future<void> _applyPeriodChanges() async {
    if (_isApplyingBulk) return;
    _isApplyingBulk = true;
    try {
      final slotProvider = Provider.of<SlotProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Only apply changes to slots for the CURRENT net
      final currentNetSlots = slotProvider.slots
          .where((s) => s.netNumber == _selectedNetNumber)
          .toList();

      // Determine if this is a closed day (not in daysOpen)
      const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final dayOfWeek = dayNames[_selectedDate.weekday - 1];
      final isClosedDay = !_selectedTurf!.daysOpen.contains(dayOfWeek);

      for (final slot in currentNetSlots) {
        final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
        bool shouldBeBlocked = false;
        final isManuallyOpened = _isSlotManuallyOpened(slot.slotId);
        final blockReason = slot.blockReason ?? '';
        final isManualBlock = blockReason == BlockReason.manuallyBlockedByOwner;

        // Check if this slot is within operating hours
        final isWithinOperatingHours = _isSlotWithinOperatingHours(slot);

        if (hour >= 6 && hour < 12) {
          shouldBeBlocked = !_isMorningOpen;
        } else if (hour >= 12 && hour < 18) {
          shouldBeBlocked = !_isAfternoonOpen;
        } else if (hour >= 18 && hour < 24) {
          shouldBeBlocked = !_isEveningOpen;
        } else {
          shouldBeBlocked = !_isNightOpen;
        }

        // Respect manual overrides: keep slot open even if period is closed
        if (isManuallyOpened && shouldBeBlocked) {
          if (slot.status == SlotStatus.blocked) {
            await slotProvider.unblockSlot(
              slot.slotId,
              overrideMarker: BlockReason.openedByOwner,
            );
          }
          continue;
        }

        if (shouldBeBlocked && slot.status == SlotStatus.available) {
          final ownerId = authProvider.currentUserId;
          if (ownerId == null) continue;
          await slotProvider.blockSlot(
            slot.slotId,
            ownerId,
            BlockReason.periodClosedByOwner,
          );
        } else if (!shouldBeBlocked &&
            slot.status == SlotStatus.blocked &&
            !isManualBlock &&
            isWithinOperatingHours) {
          await slotProvider.unblockSlot(
            slot.slotId,
            overrideMarker: isClosedDay ? BlockReason.dayOpenedByOwner : null,
          );
        }
      }

      // Reload slot data from DB without regenerating/syncing
      if (_selectedTurf != null) {
        final dateStr = _selectedDate.toIso8601String().split('T')[0];
        await slotProvider.loadSlots(_selectedTurf!.turfId, dateStr);
      }
    } finally {
      _isApplyingBulk = false;
    }
  }

  // Cached operating hours to avoid re-parsing on every slot check
  String? _cachedOpHoursTurfId;
  String? _cachedOpHoursOpen;
  String? _cachedOpHoursClose;
  int _cachedOpenMinutes = 0;
  int _cachedCloseMinutes = 0;

  /// Check if a slot falls within the turf's operating hours.
  /// Delegates the actual rule to [SlotBusinessRules.isWithinOperatingHours]
  /// so this screen and `slot_management_screen.dart` agree.
  bool _isSlotWithinOperatingHours(SlotModel slot) {
    if (_selectedTurf == null) return false;

    // Re-parse only when turf or times change
    if (_cachedOpHoursTurfId != _selectedTurf!.turfId ||
        _cachedOpHoursOpen != _selectedTurf!.openTime ||
        _cachedOpHoursClose != _selectedTurf!.closeTime) {
      final openHour = int.parse(_selectedTurf!.openTime.split(':')[0]);
      final openMinute = int.parse(_selectedTurf!.openTime.split(':')[1]);
      final closeHour = int.parse(_selectedTurf!.closeTime.split(':')[0]);
      final closeMinute = int.parse(_selectedTurf!.closeTime.split(':')[1]);

      _cachedOpenMinutes = openHour * 60 + openMinute;
      final closeMinutesRaw = closeHour * 60 + closeMinute;
      _cachedCloseMinutes = SlotBusinessRules.normalizeCloseMinutes(
        openMinutes: _cachedOpenMinutes,
        closeMinutesRaw: closeMinutesRaw,
      );
      _cachedOpHoursTurfId = _selectedTurf!.turfId;
      _cachedOpHoursOpen = _selectedTurf!.openTime;
      _cachedOpHoursClose = _selectedTurf!.closeTime;
    }

    final startParts = slot.startTime.split(':');
    final endParts = slot.endTime.split(':');
    final slotStart = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final slotEndRaw = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final slotEnd = slotEndRaw == 0 ? 1440 : slotEndRaw;

    return SlotBusinessRules.isWithinOperatingHours(
      openMinutes: _cachedOpenMinutes,
      closeMinutes: _cachedCloseMinutes,
      slotStartMin: slotStart,
      slotEndMin: slotEnd,
    );
  }

  SlotPeriod _getSlotPeriod(SlotModel slot) {
    final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
    return SlotBusinessRules.periodForHour(hour);
  }

  bool _isPeriodClosed(SlotPeriod period) {
    switch (period) {
      case SlotPeriod.morning:
        return !_isMorningOpen;
      case SlotPeriod.afternoon:
        return !_isAfternoonOpen;
      case SlotPeriod.evening:
        return !_isEveningOpen;
      case SlotPeriod.night:
        return !_isNightOpen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final turfProvider = Provider.of<TurfProvider>(context);
    final approvedTurfs = turfProvider.turfs
        .where((t) => t.verificationStatus == VerificationStatus.approved)
        .toList();

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Single smooth gradient wash from blue to page background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: c.scaffoldGradient,
                ),
              ),
            ),
            // Actual content on top
            Column(
              children: [
                Theme(
                  data: Theme.of(context).copyWith(
                    appBarTheme: const AppBarTheme(
                        backgroundColor: Colors.transparent, elevation: 0),
                  ),
                  child: GlassAppBar(title: 'Booking Dashboard'),
                ),
                Expanded(
                  child: approvedTurfs.isEmpty
                      ? _buildEmptyState()
                      : Stack(
                          children: [
                            // Main Content (full width)
                            Column(
                              children: [
                                // Compact venue/net info bar
                                _animatedSection(
                                    index: 0,
                                    child:
                                        _buildCollapsedInfoBar(approvedTurfs)),
                                // Slots Grid (calendar + everything inside scroll)
                                Expanded(
                                  child: _buildSlotsContent(),
                                ),
                              ],
                            ),
                            // Sidebar overlay
                            if (_isSidebarVisible) ...[
                              // Scrim
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _isSidebarVisible = false),
                                child: Container(color: Colors.black54),
                              ),
                              // Sidebar panel
                              _buildSidebar(approvedTurfs),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedSection({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _sectionAnimController,
      builder: (context, _) {
        return Transform.translate(
          offset: _sectionSlideAnims[index].value,
          child: Opacity(
            opacity: _sectionFadeAnims[index].value,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildCollapsedInfoBar(List<TurfModel> turfs) {
    final c = AppColors.of(context);
    final venueName = _selectedTurf?.turfName ?? 'Select Venue';
    final netLabel = (_selectedTurf != null && _selectedTurf!.numberOfNets > 1)
        ? ' · Net $_selectedNetNumber'
        : '';
    return GestureDetector(
      onTap: () => setState(() => _isSidebarVisible = true),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.stadium, color: c.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$venueName$netLabel',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: c.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tooltip(
              message: AppStrings.slotBookingTooltipChangeVenue,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz, size: 16, color: c.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.stadium_outlined,
              size: 64, color: c.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            // SBA-1: extracted to AppStrings (was 'No Approved Turfs')
            AppStrings.slotBookingNoApprovedTurfs,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.slotBookingNoApprovedTurfsBody,
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.addTurf),
            icon: const Icon(Icons.add),
            label: const Text(AppStrings.slotBookingAddTurf),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<TurfModel> turfs) {
    final c = AppColors.of(context);
    final selectedTurf = _selectedTurf;
    final allNetsUnderRenovation = selectedTurf != null &&
        selectedTurf.numberOfNets > 0 &&
        selectedTurf.status == TurfStatus.renovation &&
        _getSelectableNets(selectedTurf).isEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 260,
        color: c.surface,
        child: SafeArea(
          child: Column(
            children: [
              // Header with close button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: c.primary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(Icons.stadium, color: c.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select Venue',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: c.textPrimary),
                      ),
                    ),
                    Tooltip(
                      message: AppStrings.slotBookingTooltipCloseSidebar,
                      child: GestureDetector(
                        onTap: () => setState(() => _isSidebarVisible = false),
                        child: Semantics(
                          button: true,
                          label: AppStrings.slotBookingTooltipCloseSidebar,
                          child: Icon(Icons.close,
                              color: c.textSecondary, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Turf List
              Expanded(
                child: ListView.builder(
                  itemCount: turfs.length,
                  itemBuilder: (context, index) {
                    final turf = turfs[index];
                    final isSelected = _selectedTurf?.turfId == turf.turfId;

                    return InkWell(
                      onTap: () => _onTurfSelected(turf),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? c.primary.withValues(alpha: 0.15)
                              : null,
                          border: Border(
                            left: BorderSide(
                              color:
                                  isSelected ? c.primary : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              turf.turfName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected ? c.primary : c.textPrimary,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${turf.numberOfNets} net${turf.numberOfNets > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Net Selector (if selected turf has multiple nets)
              if (_selectedTurf != null && _selectedTurf!.numberOfNets > 1)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.05),
                    border: Border(top: BorderSide(color: c.divider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sports_cricket,
                              size: 16, color: c.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Select Net for ${_selectedTurf!.turfName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: c.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (allNetsUnderRenovation) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.warning.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: c.warning.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: c.warning),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'All nets are under renovation',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: c.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          _selectedTurf!.numberOfNets,
                          (index) {
                            final netNumber = index + 1;
                            final isDisabled = _isNetUnderRenovation(
                                _selectedTurf!, netNumber);
                            final isSelected = _selectedNetNumber == netNumber;
                            return GestureDetector(
                              onTap: isDisabled
                                  ? null
                                  : () => _onNetSelected(netNumber),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDisabled
                                      ? c.textSecondary.withValues(alpha: 0.10)
                                      : isSelected
                                          ? c.primary.withValues(alpha: 0.12)
                                          : c.glassFill,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDisabled
                                        ? c.textSecondary
                                            .withValues(alpha: 0.30)
                                        : c.primary.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'Net $netNumber',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? c.textSecondary
                                        : c.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    final c = AppColors.of(context);
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    bool canNavigateMonth(int direction) {
      final targetMonth =
          DateTime(_focusedDate.year, _focusedDate.month + direction, 1);
      final minMonth =
          DateTime(_minSelectableDate.year, _minSelectableDate.month, 1);
      final maxMonth =
          DateTime(_maxSelectableDate.year, _maxSelectableDate.month, 1);
      return !targetMonth.isBefore(minMonth) && !targetMonth.isAfter(maxMonth);
    }

    DateTime buildMonthDay(DateTime monthBase, int preferredDay) {
      final lastDayOfMonth =
          DateTime(monthBase.year, monthBase.month + 1, 0).day;
      final safeDay =
          preferredDay > lastDayOfMonth ? lastDayOfMonth : preferredDay;
      return _clampDateToBookingRange(
          DateTime(monthBase.year, monthBase.month, safeDay));
    }

    Future<void> openMonthYearPicker() async {
      final pickedDate = await showDialog<DateTime>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          DateTime tempSelectedDate = _selectedDate;
          DateTime tempDisplayedMonth =
              DateTime(_focusedDate.year, _focusedDate.month, 1);

          List<int> availableMonthsForYear(int year) {
            final startMonth =
                year == _minSelectableDate.year ? _minSelectableDate.month : 1;
            final endMonth =
                year == _maxSelectableDate.year ? _maxSelectableDate.month : 12;
            return List<int>.generate(
                endMonth - startMonth + 1, (index) => startMonth + index);
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final years = List<int>.generate(
                _maxSelectableDate.year - _minSelectableDate.year + 1,
                (index) => _minSelectableDate.year + index,
              );
              final allowedMonths =
                  availableMonthsForYear(tempDisplayedMonth.year);
              if (!allowedMonths.contains(tempDisplayedMonth.month)) {
                tempDisplayedMonth = DateTime(
                  tempDisplayedMonth.year,
                  allowedMonths.first,
                  1,
                );
                tempSelectedDate = _clampDateToBookingRange(DateTime(
                  tempDisplayedMonth.year,
                  tempDisplayedMonth.month,
                  tempSelectedDate.day,
                ));
              }

              return Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Date',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: tempDisplayedMonth.month,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: c.glassFill,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: allowedMonths
                                  .map(
                                    (month) => DropdownMenuItem<int>(
                                      value: month,
                                      child: Text(monthNames[month - 1]),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (month) {
                                if (month == null) return;
                                setDialogState(() {
                                  tempDisplayedMonth = DateTime(
                                      tempDisplayedMonth.year, month, 1);
                                  tempSelectedDate = _clampDateToBookingRange(
                                    DateTime(
                                      tempDisplayedMonth.year,
                                      tempDisplayedMonth.month,
                                      tempSelectedDate.day,
                                    ),
                                  );
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<int>(
                              value: tempDisplayedMonth.year,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: c.glassFill,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: years
                                  .map(
                                    (year) => DropdownMenuItem<int>(
                                      value: year,
                                      child: Text('$year'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (year) {
                                if (year == null) return;
                                setDialogState(() {
                                  final months = availableMonthsForYear(year);
                                  final month =
                                      months.contains(tempDisplayedMonth.month)
                                          ? tempDisplayedMonth.month
                                          : months.first;
                                  tempDisplayedMonth = DateTime(year, month, 1);
                                  tempSelectedDate = _clampDateToBookingRange(
                                    DateTime(
                                      tempDisplayedMonth.year,
                                      tempDisplayedMonth.month,
                                      tempSelectedDate.day,
                                    ),
                                  );
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CalendarDatePicker(
                        key: ValueKey(
                            '${tempDisplayedMonth.year}-${tempDisplayedMonth.month}'),
                        initialDate: tempSelectedDate,
                        firstDate: _minSelectableDate,
                        lastDate: _maxSelectableDate,
                        currentDate: _dateOnly(DateTime.now()),
                        onDateChanged: (date) {
                          setDialogState(() {
                            tempSelectedDate = _dateOnly(date);
                            tempDisplayedMonth =
                                DateTime(date.year, date.month, 1);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.primary,
                            foregroundColor: c.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () =>
                              Navigator.pop(dialogContext, tempSelectedDate),
                          child: const Text(
                            'Confirm',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (pickedDate != null && mounted) {
        _onDateSelected(pickedDate);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: AppStrings.slotBookingTooltipPrevMonth,
                onPressed: canNavigateMonth(-1)
                    ? () {
                        final targetMonth = DateTime(
                            _focusedDate.year, _focusedDate.month - 1, 1);
                        final targetDate =
                            buildMonthDay(targetMonth, _selectedDate.day);
                        _onDateSelected(targetDate);
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
                color: c.textSecondary,
              ),
              Expanded(
                child: InkWell(
                  onTap: openMonthYearPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${monthNames[_focusedDate.month - 1]} ${_focusedDate.year}',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: c.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.slotBookingTooltipNextMonth,
                onPressed: canNavigateMonth(1)
                    ? () {
                        final targetMonth = DateTime(
                            _focusedDate.year, _focusedDate.month + 1, 1);
                        final targetDate =
                            buildMonthDay(targetMonth, _selectedDate.day);
                        _onDateSelected(targetDate);
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
                color: c.textSecondary,
              ),
            ],
          ),
          TableCalendar(
            firstDay: _minSelectableDate,
            lastDay: _maxSelectableDate,
            focusedDay: _focusedDate,
            calendarFormat: CalendarFormat.week,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
            enabledDayPredicate: _isDateWithinBookingRange,
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDate = _dateOnly(focusedDay);
              });
            },
            onDaySelected: (selected, focused) {
              if (!_isDateWithinBookingRange(selected)) return;
              _onDateSelected(selected);
            },
            headerVisible: false,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              headerPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            calendarStyle: CalendarStyle(
              // Hide default decorations — custom builders handle selected/today
              selectedDecoration:
                  const BoxDecoration(color: Colors.transparent),
              selectedTextStyle: const TextStyle(color: Colors.transparent),
              todayDecoration: const BoxDecoration(color: Colors.transparent),
              todayTextStyle: const TextStyle(color: Colors.transparent),
              defaultTextStyle: TextStyle(color: c.textSecondary),
              weekendTextStyle: TextStyle(color: c.textSecondary),
              cellPadding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            ),
            daysOfWeekVisible: false,
            calendarBuilders: CalendarBuilders(
              selectedBuilder: (context, day, focusedDay) {
                final dayLabel = const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun'
                ][day.weekday - 1];
                return Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayLabel,
                          style: TextStyle(
                            color: c.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: c.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              todayBuilder: (context, day, focusedDay) {
                final isSelected = isSameDay(day, _selectedDate);
                final dayLabel = const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun'
                ][day.weekday - 1];
                return Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? c.primary
                          : c.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayLabel,
                          style: TextStyle(
                            color: isSelected ? c.onPrimary : c.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isSelected ? c.onPrimary : c.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              defaultBuilder: (context, day, focusedDay) {
                final isEnabled = _isDateWithinBookingRange(day);
                final dayLabel = const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun'
                ][day.weekday - 1];
                return Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayLabel,
                          style: TextStyle(
                            color: isEnabled
                                ? c.textHint
                                : c.textHint.withValues(alpha: 0.35),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isEnabled
                                ? c.textSecondary
                                : c.textSecondary.withValues(alpha: 0.35),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Inline toggle widget for period headers
  Widget _buildInlinePeriodToggle(String period, bool isOpen) {
    final c = AppColors.of(context);
    final periodEnum = _periodFromLabel(period);
    return Tooltip(
      message:
          '${AppStrings.slotBookingTooltipTogglePeriodPrefix}$period${AppStrings.slotBookingTooltipTogglePeriodSuffix}',
      child: Semantics(
        button: true,
        toggled: isOpen,
        label: '$period ${isOpen ? 'open' : 'closed'}',
        child: GestureDetector(
          onTap: () => _togglePeriod(periodEnum, !isOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOpen
                  ? c.success.withValues(alpha: 0.15)
                  : c.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOpen ? c.success : c.error,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOpen ? Icons.lock_open : Icons.lock,
                  size: 12,
                  color: isOpen ? c.success : c.error,
                ),
                const SizedBox(width: 4),
                Text(
                  isOpen ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isOpen ? c.success : c.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Day toggle widget for net header
  Widget _buildDayToggle() {
    final c = AppColors.of(context);
    return Tooltip(
      message: AppStrings.slotBookingTooltipToggleDay,
      child: Semantics(
        button: true,
        toggled: _isDayOpen,
        label: _isDayOpen ? 'Day open' : 'Day closed',
        child: GestureDetector(
          onTap: () => _toggleDay(!_isDayOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isDayOpen
                  ? c.success.withValues(alpha: 0.15)
                  : c.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isDayOpen ? c.success : c.error,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isDayOpen ? Icons.wb_sunny : Icons.nights_stay,
                  size: 16,
                  color: _isDayOpen ? c.warning : c.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _isDayOpen ? 'DAY OPEN' : 'DAY CLOSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isDayOpen ? c.success : c.error,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 32,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _isDayOpen
                        ? c.success
                        : c.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 150),
                        left: _isDayOpen ? 16 : 2,
                        top: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Check if a slot is manually opened
  bool _isSlotManuallyOpened(String slotId) {
    final key = _getSlotOverrideKey(slotId);
    return _manuallyOpenedSlots.contains(key);
  }

  // Toggle manual override for a slot
  void _toggleSlotManualOverride(String slotId) {
    final key = _getSlotOverrideKey(slotId);
    setState(() {
      if (_manuallyOpenedSlots.contains(key)) {
        _manuallyOpenedSlots.remove(key);
      } else {
        _manuallyOpenedSlots.add(key);
      }
    });
  }

  Widget _buildSlotsContent() {
    // SBA-2: Selector with record (loading + slots) so the slot grid only
    // rebuilds when those two fields actually change, not on every
    // SlotProvider notify (e.g. internal generation/maintenance ticks).
    return Selector<SlotProvider, ({bool loading, List<SlotModel> slots})>(
      selector: (_, p) => (loading: p.isLoading, slots: p.slots),
      builder: (context, snapshot, _) {
        final c = AppColors.of(context);
        if (snapshot.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        var slots = snapshot.slots;
        if (slots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 48, color: c.textHint),
                const SizedBox(height: 16),
                Text(AppStrings.slotBookingNoSlotsForDate,
                    style: TextStyle(color: c.textSecondary)),
              ],
            ),
          );
        }

        // Filter slots by selected net number
        slots = slots.where((s) => s.netNumber == _selectedNetNumber).toList();

        if (slots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 48, color: c.textHint),
                const SizedBox(height: 16),
                Text(
                    '${AppStrings.slotBookingNoSlotsForNetPrefix}$_selectedNetNumber',
                    style: TextStyle(color: c.textSecondary)),
              ],
            ),
          );
        }

        // Group slots by time period
        final night = slots
            .where((s) =>
                _getTimePeriod(s.startTime) ==
                AppStrings.slotBookingPeriodNight)
            .toList();
        final morning = slots
            .where((s) =>
                _getTimePeriod(s.startTime) ==
                AppStrings.slotBookingPeriodMorning)
            .toList();
        final afternoon = slots
            .where((s) =>
                _getTimePeriod(s.startTime) ==
                AppStrings.slotBookingPeriodAfternoon)
            .toList();
        final evening = slots
            .where((s) =>
                _getTimePeriod(s.startTime) ==
                AppStrings.slotBookingPeriodEvening)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date picker inside scroll
              _animatedSection(index: 1, child: _buildDatePicker()),
              const SizedBox(height: 8),

              // Slot control panel card
              _animatedSection(
                index: 2,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Net indicator with Day toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_selectedTurf != null &&
                                        _selectedTurf!.numberOfNets > 1)
                                    ? Icons.sports_cricket
                                    : Icons.calendar_today,
                                size: 18,
                                color: c.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                (_selectedTurf != null &&
                                        _selectedTurf!.numberOfNets > 1)
                                    ? 'Net $_selectedNetNumber Slots'
                                    : 'Today\'s Slots',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          _buildDayToggle(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Legend
                      _buildLegend(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Time Period Sections
              _animatedSection(
                index: 3,
                child: _buildTimePeriodSection('Night', '12 AM - 6 AM', night,
                    Icons.bedtime, 'night', _isNightOpen,
                    iconColor: const Color(0xFF6366F1),
                    iconBgColor: const Color(0xFFEEF2FF)),
              ),
              _animatedSection(
                index: 4,
                child: _buildTimePeriodSection('Morning', '6 AM - 12 PM',
                    morning, Icons.wb_sunny, 'morning', _isMorningOpen,
                    iconColor: c.warning, iconBgColor: c.warningLight),
              ),
              _animatedSection(
                index: 5,
                child: _buildTimePeriodSection('Afternoon', '12 PM - 6 PM',
                    afternoon, Icons.wb_cloudy, 'afternoon', _isAfternoonOpen,
                    iconColor: c.warning, iconBgColor: c.warningLight),
              ),
              _animatedSection(
                index: 6,
                child: _buildTimePeriodSection('Evening', '6 PM - 12 AM',
                    evening, Icons.nightlight_round, 'evening', _isEveningOpen,
                    iconColor: const Color(0xFF8B5CF6),
                    iconBgColor: const Color(0xFFF5F3FF)),
              ),
            ],
          ),
        );
      },
    );
  }

  SlotPeriod _periodFromLabel(String label) {
    switch (label.toLowerCase()) {
      case 'morning':
        return SlotPeriod.morning;
      case 'afternoon':
        return SlotPeriod.afternoon;
      case 'evening':
        return SlotPeriod.evening;
      default:
        return SlotPeriod.night;
    }
  }

  String _getTimePeriod(String startTime) {
    final hour = int.tryParse(startTime.split(':')[0]) ?? 0;
    switch (SlotBusinessRules.periodForHour(hour)) {
      case SlotPeriod.morning:
        return AppStrings.slotBookingPeriodMorning;
      case SlotPeriod.afternoon:
        return AppStrings.slotBookingPeriodAfternoon;
      case SlotPeriod.evening:
        return AppStrings.slotBookingPeriodEvening;
      case SlotPeriod.night:
        return AppStrings.slotBookingPeriodNight;
    }
  }

  Widget _buildLegend() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildLegendItem('Available', c.success)),
              Expanded(child: _buildLegendItem('Pending', c.warning)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildLegendItem('Booked', c.error)),
              Expanded(child: _buildLegendItem('Closed', Colors.grey.shade400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: c.textSecondary)),
      ],
    );
  }

  Widget _buildTimePeriodSection(
    String title,
    String timeRange,
    List<SlotModel> slots,
    IconData icon,
    String periodKey,
    bool isOpen, {
    required Color iconColor,
    required Color iconBgColor,
  }) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with icon badge, title, time range, and toggle
          Row(
            children: [
              // Icon with colored background
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              ),
              const SizedBox(width: 12),
              // Title + time range
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isOpen ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeRange,
                      style: TextStyle(
                        fontSize: 12,
                        color: isOpen
                            ? c.textSecondary
                            : c.textSecondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              _buildInlinePeriodToggle(periodKey, isOpen),
            ],
          ),
          const SizedBox(height: 14),
          // Slots grid
          if (slots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'No slots in this period',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemCount: slots.length,
              itemBuilder: (context, index) => _buildSlotCard(slots[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(SlotModel slot) {
    final c = AppColors.of(context);
    final isPast = _isSlotPast(slot);
    final isBooked = slot.status == SlotStatus.booked;
    final isReserved = slot.status == SlotStatus.reserved; // Pending payment
    final isBlocked = slot.status == SlotStatus.blocked; // Shows as "Closed"

    // Check if slot's period is closed by toggle
    final period = _getSlotPeriod(slot);
    final isPeriodClosed = _isPeriodClosed(period);

    // Check if this slot is manually opened (overriding closure)
    final isManuallyOpened = _isSlotManuallyOpened(slot.slotId);

    // Slot is effectively closed if: blocked OR period closed (unless manually opened)
    final effectivelyClosed =
        (isBlocked || isPeriodClosed) && !isManuallyOpened;

    Color bgColor;
    Color textColor;
    Color borderColor;
    String statusLabel;

    // Determine slot display based on status
    if (isPast) {
      bgColor = c.surface;
      borderColor = c.border;
      textColor = c.textHint;
      statusLabel = 'Past';
    } else if (isBooked) {
      bgColor = c.errorLight;
      borderColor = c.error;
      textColor = c.error;
      statusLabel = 'Booked';
    } else if (isReserved) {
      bgColor = c.warningLight;
      borderColor = c.warning;
      textColor = c.warning;
      statusLabel = 'Pending';
    } else if (effectivelyClosed) {
      // Slot is closed (blocked or period closed) but can be manually opened
      bgColor = c.surface;
      borderColor = c.border;
      textColor = c.textSecondary;
      statusLabel = 'Closed';
    } else {
      bgColor = c.successLight;
      borderColor = c.success;
      textColor = c.success;
      statusLabel = 'Available';
    }

    // Determine if slot is tappable (all non-past slots are tappable)
    final isTappable = !isPast;

    return _SlotTapWrapper(
      enabled: isTappable,
      onTap: isTappable
          ? () => _showSlotActions(slot,
              isPeriodClosed: isPeriodClosed,
              isManuallyOpened: isManuallyOpened)
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              slot.displayTimeRange.split(' - ')[0],
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: textColor,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            if (effectivelyClosed)
              Icon(Icons.lock, size: 14, color: textColor)
            else
              Text(
                '₹${slot.price.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor.withValues(alpha: 0.85),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSlotPast(SlotModel slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slotDate = DateTime.parse(slot.date);

    if (slotDate.isBefore(today)) return true;

    if (slotDate.isAtSameMomentAs(today)) {
      final timeParts = slot.startTime.split(':');
      final slotHour = int.parse(timeParts[0]);
      final slotMinute = int.parse(timeParts[1]);
      final slotTime =
          DateTime(now.year, now.month, now.day, slotHour, slotMinute);
      return now.isAfter(slotTime);
    }

    return false;
  }

  void _showSlotActions(SlotModel slot,
      {bool isPeriodClosed = false, bool isManuallyOpened = false}) {
    final c = AppColors.of(context);
    final isAvailable = slot.status == SlotStatus.available;
    final isBooked = slot.status == SlotStatus.booked;
    final isReserved = slot.status == SlotStatus.reserved; // Pending payment
    final isBlocked = slot.status == SlotStatus.blocked; // Shows as "Closed"

    // Slot is effectively closed if blocked or period closed
    final effectivelyClosed =
        (isBlocked || isPeriodClosed) && !isManuallyOpened;

    // Slot is effectively available only when status is AVAILABLE.
    // Manual override can open a period/day-closed slot, but booking state wins.
    final effectivelyAvailable =
        isAvailable && (!isPeriodClosed || isManuallyOpened);

    // Show open option only for truly unbooked closed slots.
    final showManualOpenOption = effectivelyClosed && !isBooked && !isReserved;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.background,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              slot.displayTimeRange,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  PriceCalculator.formatPrice(slot.price),
                  style: TextStyle(fontSize: 16, color: c.textSecondary),
                ),
                if (isReserved) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Pending Payment',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (effectivelyClosed) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 12, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          'Closed',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // Show manual open option when period is closed
            if (showManualOpenOption) ...[
              _buildActionButton(
                'Open This Slot',
                Icons.lock_open,
                c.success,
                bgColor: c.successLight,
                borderColor: c.success,
                textColor: c.success,
                () async {
                  Navigator.pop(context);
                  _toggleSlotManualOverride(slot.slotId);
                  // Unblock the slot in database — always set override marker
                  // so _syncOperatingHoursForNet preserves it across refreshes
                  if (isBlocked) {
                    final slotProvider =
                        Provider.of<SlotProvider>(context, listen: false);
                    await slotProvider.unblockSlot(
                      slot.slotId,
                      overrideMarker: 'Opened by owner',
                    );
                  }
                  _loadSlots();
                  showAppToast(context, AppStrings.slotBookingSlotOpenedToBook,
                      type: ToastType.success);
                },
              ),
              const SizedBox(height: 12),
            ],

            if (effectivelyAvailable) ...[
              _buildActionButton(
                'Create Booking',
                Icons.add_circle,
                c.primary,
                () {
                  Navigator.pop(context);
                  _showBookingDialog(slot);
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'Close Slot',
                Icons.lock,
                Colors.grey,
                bgColor: c.surface,
                borderColor: c.textHint,
                textColor: c.textSecondary,
                () {
                  Navigator.pop(context);
                  _blockSlot(slot);
                },
              ),
            ],

            if (isReserved) ...[
              _buildActionButton(
                'Mark Payment Received',
                Icons.check_circle,
                c.success,
                bgColor: c.successLight,
                borderColor: c.success,
                textColor: c.success,
                () async {
                  Navigator.pop(context);
                  await _markPaymentAndUpdateSlot(slot);
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'Cancel Booking',
                Icons.cancel,
                c.error,
                bgColor: c.errorLight,
                borderColor: c.error,
                textColor: c.error,
                () async {
                  Navigator.pop(context);
                  await _cancelBookingForSlot(slot);
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'View Payment Details',
                Icons.payments,
                c.primary,
                () async {
                  Navigator.pop(context);
                  await _showPaymentDetails(slot);
                },
              ),
            ],

            if (isBooked) ...[
              _buildActionButton(
                'Cancel Booking',
                Icons.cancel,
                c.error,
                bgColor: c.errorLight,
                borderColor: c.error,
                textColor: c.error,
                () async {
                  Navigator.pop(context);
                  await _cancelBookingForSlot(slot);
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'View Payment Details',
                Icons.payments,
                c.primary,
                () async {
                  Navigator.pop(context);
                  await _showPaymentDetails(slot);
                },
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDetails(SlotModel slot) async {
    final c = AppColors.of(context);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);
    final booking = await bookingProvider.getBookingBySlotId(slot.slotId);

    if (booking == null || !mounted) {
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingPaymentDetailsNotFound,
            type: ToastType.warning);
      }
      return;
    }

    final isPaid = booking.paymentStatus == PaymentStatus.paid;
    final remaining =
        (booking.amount - booking.advanceAmount).clamp(0, booking.amount);

    showModalBottomSheet(
      context: context,
      backgroundColor: c.background,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Payment Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildPaymentRow('Status', isPaid ? 'Paid' : 'Pending',
                isPaid ? c.success : Colors.orange),
            const SizedBox(height: 8),
            _buildPaymentRow('Total Amount',
                PriceCalculator.formatPrice(booking.amount), c.textPrimary),
            const SizedBox(height: 8),
            _buildPaymentRow(
                'Advance Paid',
                PriceCalculator.formatPrice(booking.advanceAmount),
                c.textPrimary),
            const SizedBox(height: 8),
            _buildPaymentRow(
                'Balance Due',
                PriceCalculator.formatPrice(remaining.toDouble()),
                remaining > 0 ? Colors.orange : c.success),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String label, String value, Color valueColor) {
    final c = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary)),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
        ),
      ],
    );
  }

  Future<void> _cancelBookingForSlot(SlotModel slot) async {
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerId = authProvider.currentUserId;
    if (ownerId == null) {
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingSessionExpired,
            type: ToastType.error);
      }
      return;
    }
    final booking = await bookingProvider.getBookingBySlotId(slot.slotId);

    if (booking == null) {
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingBookingNotFound,
            type: ToastType.warning);
      }
      return;
    }

    final success = await bookingProvider.cancelBooking(
      booking.bookingId,
      slot.slotId,
      ownerId,
      AppStrings.slotBookingCancelReason,
    );

    if (!mounted) return;
    if (success) {
      showAppToast(context, AppStrings.slotBookingBookingCancelled,
          type: ToastType.success);
      _loadSlots();
    } else {
      showAppToast(context, AppStrings.slotBookingCancelFailed,
          type: ToastType.error);
    }
  }

  Future<void> _markPaymentAndUpdateSlot(SlotModel slot) async {
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);

    final booking = await bookingProvider.getBookingBySlotId(slot.slotId);
    if (booking == null) {
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingBookingNotFound,
            type: ToastType.warning);
      }
      return;
    }
    try {
      await bookingProvider.markPaymentReceived(booking.bookingId);
      await slotProvider.markSlotAsBooked(slot.slotId);
      _loadSlots();
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingPaymentMarkedReceived,
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${AppStrings.slotBookingPaymentMarkFailed}: $e',
            type: ToastType.error);
      }
    }
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, VoidCallback onTap,
      {Color? bgColor, Color? borderColor, Color? textColor}) {
    final c = AppColors.of(context);
    final bg = bgColor ?? c.primaryLight;
    final bdr = borderColor ?? c.primary;
    final txt = textColor ?? c.primaryDark;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          splashColor: bdr.withValues(alpha: 0.15),
          highlightColor: bdr.withValues(alpha: 0.10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: bdr, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: txt, size: 20),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        color: txt, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBookingDialog(SlotModel slot) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BookingDialog(
        turf: _selectedTurf!,
        slot: slot,
        selectedDate: _selectedDate,
        selectedNetNumber: _selectedNetNumber,
        onBookingCreated: () {
          _loadSlots();
        },
      ),
    );
  }

  Future<void> _blockSlot(SlotModel slot) async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerId = authProvider.currentUserId;
    if (ownerId == null) {
      if (mounted) {
        showAppToast(context, AppStrings.slotBookingSessionExpired,
            type: ToastType.error);
      }
      return;
    }
    // Clear manual override so the slot renders as closed
    final key = _getSlotOverrideKey(slot.slotId);
    _manuallyOpenedSlots.remove(key);
    await slotProvider.blockSlot(
        slot.slotId, ownerId, BlockReason.manuallyBlockedByOwner);
    _loadSlots();
  }
}

/// Booking Dialog Widget
class _BookingDialog extends StatefulWidget {
  final TurfModel turf;
  final SlotModel slot;
  final DateTime selectedDate;
  final VoidCallback onBookingCreated;
  final int selectedNetNumber;

  const _BookingDialog({
    required this.turf,
    required this.slot,
    required this.selectedDate,
    required this.onBookingCreated,
    this.selectedNetNumber = 1,
  });

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _advanceController = TextEditingController();
  final _bookingAmountController = TextEditingController();

  bool _isLoading = false;
  BookingSource _bookingSource = BookingSource.phone;

  @override
  void initState() {
    super.initState();
    // Initialize booking amount with slot price
    _bookingAmountController.text = widget.slot.price.toInt().toString();
    // Initialize advance amount to 0
    _advanceController.text = '0';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _advanceController.dispose();
    _bookingAmountController.dispose();
    super.dispose();
  }

  double get _bookingAmount {
    if (_bookingAmountController.text.isEmpty) return widget.slot.price;
    return double.tryParse(_bookingAmountController.text) ?? widget.slot.price;
  }

  double get _advanceAmount {
    if (_advanceController.text.isEmpty) return 0;
    return double.tryParse(_advanceController.text) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    // Month names for ticket-style date
    const months = [
      '',
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    final ticketDate =
        '${widget.selectedDate.day.toString().padLeft(2, '0')}. ${months[widget.selectedDate.month]} ${widget.selectedDate.year}';
    final netLabel =
        widget.turf.numberOfNets > 1 ? 'Net ${widget.selectedNetNumber}' : null;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ═══════════════════════════════════════════════════
                  // TOP SECTION — Ticket info grid (like airline ticket)
                  // ═══════════════════════════════════════════════════
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                    ),
                    child: Stack(
                      children: [
                        // Diagonal stripe accents on left edge
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: CustomPaint(
                            size: const Size(6, double.infinity),
                            painter: _TicketEdgePainter(),
                          ),
                        ),
                        // Diagonal stripe accents on right edge
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: CustomPaint(
                            size: const Size(6, double.infinity),
                            painter: _TicketEdgePainter(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title row + close
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      AppStrings.bookingDialogTitle,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.close_rounded,
                                          color: c.onPrimary, size: 16),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              // Venue name (large)
                              Text(
                                widget.turf.turfName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 20),
                              // 2-column grid: Row 1 — Net | Date
                              Row(
                                children: [
                                  Expanded(
                                    child: _ticketField(
                                        AppStrings.bookingDialogTicketNet,
                                        netLabel ?? 'Net 1'),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _ticketField(
                                        AppStrings.bookingDialogTicketDate,
                                        ticketDate),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              // 2-column grid: Row 2 — Time | Amount
                              Row(
                                children: [
                                  Expanded(
                                    child: _ticketField(
                                        AppStrings.bookingDialogTicketTime,
                                        widget.slot.displayTimeRange),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            AppStrings
                                                .bookingDialogTicketAmount,
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white
                                                    .withValues(alpha: 0.78))),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            IntrinsicWidth(
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 50,
                                                        maxWidth: 120),
                                                child: TextFormField(
                                                  controller:
                                                      _bookingAmountController,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly
                                                  ],
                                                  textAlign: TextAlign.left,
                                                  cursorColor: Colors.white,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                    prefixText: '₹',
                                                    prefixStyle: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    filled: false,
                                                  ),
                                                  validator: (v) {
                                                    if (v?.isEmpty == true) {
                                                      return AppStrings
                                                          .bookingDialogRequired;
                                                    }
                                                    final amount =
                                                        double.tryParse(v!) ??
                                                            0;
                                                    if (amount <= 0) {
                                                      return AppStrings
                                                          .bookingDialogInvalid;
                                                    }
                                                    return null;
                                                  },
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                ),
                                              ),
                                            ),
                                            if (_isPeakRate()) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.20),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                    AppStrings
                                                        .bookingDialogPeak,
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ═══════════════════════════════════════════════════
                  // TICKET TEAR — cutouts + dashed line
                  // ═══════════════════════════════════════════════════
                  SizedBox(
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Fill
                        Positioned.fill(child: Container(color: c.surface)),
                        // Dashed line
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: CustomPaint(
                              size: const Size(double.infinity, 1),
                              painter: _TicketDashedLinePainter(),
                            ),
                          ),
                        ),
                        // Left notch
                        Positioned(
                          left: -14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                        // Right notch
                        Positioned(
                          right: -14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ═══════════════════════════════════════════════════
                  // BOTTOM SECTION — Form with stumps watermark
                  // ═══════════════════════════════════════════════════
                  Container(
                    width: double.infinity,
                    color: c.surface,
                    child: Stack(
                      children: [
                        // Stumps watermark
                        Positioned(
                          right: 10,
                          bottom: 60,
                          child: CustomPaint(
                            size: const Size(90, 110),
                            painter: _StumpsPainter(
                                color: c.primary.withValues(alpha: 0.04)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Customer ──
                              Text(AppStrings.bookingDialogCustomer,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: c.textSecondary)),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  hintText: AppStrings.bookingDialogFullName,
                                  hintStyle: TextStyle(
                                      fontSize: 14, color: c.textHint),
                                  prefixIcon: Icon(Icons.person_outline_rounded,
                                      color: c.textSecondary, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: c.primary, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: c.inputBackground,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 13),
                                ),
                                validator: (v) => v?.isEmpty == true
                                    ? AppStrings.bookingDialogEnterName
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: InputDecoration(
                                  hintText: AppStrings.bookingDialogPhoneNumber,
                                  hintStyle: TextStyle(
                                      fontSize: 14, color: c.textHint),
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: c.textSecondary, size: 20),
                                  counterText: '',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: c.primary, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: c.inputBackground,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 13),
                                ),
                                validator: (v) {
                                  if (v?.isEmpty == true) {
                                    return AppStrings.bookingDialogEnterPhone;
                                  }
                                  if (v!.length != 10) {
                                    return AppStrings
                                        .bookingDialogPhoneTenDigits;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),

                              // ── Advance ──
                              Row(
                                children: [
                                  Text(AppStrings.bookingDialogAdvance,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: c.textSecondary)),
                                  const SizedBox(width: 6),
                                  Text(AppStrings.bookingDialogAdvanceHint,
                                      style: TextStyle(
                                          fontSize: 10, color: c.textDisabled)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _advanceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                      fontSize: 14, color: c.textHint),
                                  prefixIcon: Icon(Icons.currency_rupee_rounded,
                                      color: c.textSecondary, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: c.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: c.primary, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: c.inputBackground,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 13),
                                ),
                                validator: (v) {
                                  if (v?.isEmpty == true) {
                                    return AppStrings.bookingDialogEnterAdvance;
                                  }
                                  final advance = double.tryParse(v!) ?? 0;
                                  if (advance < 0) {
                                    return AppStrings
                                        .bookingDialogCannotBeNegative;
                                  }
                                  if (advance > _bookingAmount) {
                                    return AppStrings
                                        .bookingDialogCannotExceedBooking;
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),

                              // Payment info
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: c.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 14, color: c.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _advanceAmount >= _bookingAmount
                                            ? bookingDialogFullPaymentMsg(
                                                _advanceAmount.toInt())
                                            : _advanceAmount > 0
                                                ? bookingDialogAdvanceRemainingMsg(
                                                    _advanceAmount.toInt(),
                                                    (_bookingAmount -
                                                            _advanceAmount)
                                                        .toInt())
                                                : bookingDialogPayAtTurfMsg(
                                                    _bookingAmount.toInt()),
                                        style: TextStyle(
                                          color: c.primary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // ── Source ──
                              Text(AppStrings.bookingDialogBookingSource,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: c.textSecondary)),
                              const SizedBox(height: 10),
                              _buildSegmentedSource(),
                              const SizedBox(height: 22),

                              // ── Confirm button ──
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _createBooking,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: c.primary,
                                    foregroundColor: c.onPrimary,
                                    elevation: 0,
                                    shadowColor:
                                        c.primary.withValues(alpha: 0.18),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                  ).copyWith(
                                    elevation: WidgetStateProperty.all(4),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Text(
                                          AppStrings
                                              .bookingDialogConfirmBooking,
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ticketField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.78))),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  bool _isPeakRate() {
    final hour = int.tryParse(widget.slot.startTime.split(':')[0]) ?? 0;
    return hour >= 18 || hour < 6; // Evening and night are peak
  }

  Widget _buildSegmentedSource() {
    final c = AppColors.of(context);
    final isPhone = _bookingSource == BookingSource.phone;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: c.inputBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final halfWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              // Sliding thumb
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: isPhone ? 0 : halfWidth,
                top: 0,
                bottom: 0,
                width: halfWidth,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Tap targets
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _bookingSource = BookingSource.phone),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Icon(Icons.phone,
                                  key: ValueKey(isPhone),
                                  size: 15,
                                  color:
                                      isPhone ? c.onPrimary : c.textSecondary),
                            ),
                            const SizedBox(width: 5),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isPhone ? c.onPrimary : c.textSecondary,
                              ),
                              child: const Text(
                                  AppStrings.bookingDialogSourcePhone),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _bookingSource = BookingSource.walkIn),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Icon(Icons.directions_walk,
                                  key: ValueKey(!isPhone),
                                  size: 15,
                                  color:
                                      !isPhone ? c.onPrimary : c.textSecondary),
                            ),
                            const SizedBox(width: 5),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !isPhone ? c.onPrimary : c.textSecondary,
                              ),
                              child: const Text(
                                  AppStrings.bookingDialogSourceWalkIn),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createBooking() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    try {
      final bookingId = await bookingProvider.createManualBooking(
        turfId: widget.turf.turfId,
        slotId: widget.slot.slotId,
        bookingDate: widget.selectedDate.toIso8601String().split('T')[0],
        startTime: widget.slot.startTime,
        endTime: widget.slot.endTime,
        turfName: widget.turf.turfName,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        bookingSource: _bookingSource,
        amount: _bookingAmount, // Use editable booking amount
        advanceAmount: _advanceAmount,
        netNumber: widget.selectedNetNumber,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (bookingId != null) {
        // Update slot price if owner changed the booking amount
        if (_bookingAmount != widget.slot.price) {
          try {
            await DatabaseService()
                .updateSlotPrice(widget.slot.slotId, _bookingAmount);
          } catch (_) {
            // Non-fatal: booking succeeded; price sync failure is silent.
          }
        }

        if (!mounted) return;
        Navigator.pop(context);
        widget.onBookingCreated();

        // Show payment confirmation dialog
        _showPaymentConfirmation(bookingId);
      } else {
        showAppToast(context, AppStrings.bookingDialogCreateFailed,
            type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppToast(context, '${AppStrings.bookingDialogCreateFailed}: $e',
          type: ToastType.error);
    }
  }

  void _showPaymentConfirmation(String bookingId) {
    final dateStr =
        '${widget.selectedDate.day}/${widget.selectedDate.month}/${widget.selectedDate.year}';
    final customerName = _nameController.text.trim();
    final customerPhone = _phoneController.text.trim();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BookingSuccessPopup(
        bookingId: bookingId,
        turf: widget.turf,
        slot: widget.slot,
        selectedDate: widget.selectedDate,
        selectedNetNumber: widget.selectedNetNumber,
        customerName: customerName,
        customerPhone: customerPhone,
        bookingAmount: _bookingAmount,
        advanceAmount: _advanceAmount,
        dateStr: dateStr,
      ),
    );
  }
}

/// Booking Success Popup - Complete Redesign
/// Features: Auto-send messages via WhatsApp Cloud API, Receipt generation, Share options
class _BookingSuccessPopup extends StatefulWidget {
  final String bookingId;
  final TurfModel turf;
  final SlotModel slot;
  final DateTime selectedDate;
  final int selectedNetNumber;
  final String customerName;
  final String customerPhone;
  final double bookingAmount;
  final double advanceAmount;
  final String dateStr;

  const _BookingSuccessPopup({
    required this.bookingId,
    required this.turf,
    required this.slot,
    required this.selectedDate,
    required this.selectedNetNumber,
    required this.customerName,
    required this.customerPhone,
    required this.bookingAmount,
    required this.advanceAmount,
    required this.dateStr,
  });

  @override
  State<_BookingSuccessPopup> createState() => _BookingSuccessPopupState();
}

class _BookingSuccessPopupState extends State<_BookingSuccessPopup>
    with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late AnimationController _slideController;
  late Animation<double> _bounceAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isSendingConfirmation = false;
  bool _confirmationSent = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _bounceController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  double get _remainingAmount => widget.bookingAmount - widget.advanceAmount;
  bool get _isFullPayment => widget.advanceAmount >= widget.bookingAmount;
  bool get _hasAdvance => widget.advanceAmount > 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Dialog(
      backgroundColor: c.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.2),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Header
                  _buildSuccessHeader(),

                  // Ticket Tear — cutouts + dashed line
                  SizedBox(
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: Container(color: c.surface)),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: CustomPaint(
                              size: const Size(double.infinity, 1),
                              painter: _TicketDashedLinePainter(),
                            ),
                          ),
                        ),
                        Positioned(
                          left: -14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Receipt Card
                        _buildReceiptCard(),
                        const SizedBox(height: 20),

                        // Action Buttons
                        _buildActionButtons(),
                        const SizedBox(height: 16),

                        // Done Button
                        _buildDoneButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessHeader() {
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.primary,
            c.primary.withBlue(200),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Animated Success Icon
          ScaleTransition(
            scale: _bounceAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.sports_cricket,
                    color: c.primary,
                    size: 36,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: c.success,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: c.onPrimary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            AppStrings.bookingSuccessTitle,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '#${widget.bookingId.substring(0, 8).toUpperCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptCard() {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Venue & Net
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.stadium, color: c.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.turf.turfName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (widget.turf.numberOfNets > 1)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${AppStrings.bookingDialogTicketNet} ${widget.selectedNetNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Details Grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildReceiptRow(Icons.person, AppStrings.bookingDialogCustomer,
                    widget.customerName),
                _buildReceiptRow(Icons.calendar_today,
                    AppStrings.bookingDialogTicketDate, widget.dateStr),
                _buildReceiptRow(
                    Icons.schedule,
                    AppStrings.bookingDialogTicketTime,
                    widget.slot.displayTimeRange),
                const Divider(height: 24),

                // Payment Section
                _buildPaymentSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(IconData icon, String label, String value) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textSecondary),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    final c = AppColors.of(context);
    return Column(
      children: [
        // Total Amount
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              AppStrings.bookingSuccessTotalAmount,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            Text(
              PriceCalculator.formatPrice(widget.bookingAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: c.primary,
              ),
            ),
          ],
        ),

        if (_hasAdvance) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isFullPayment
                  ? c.success.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isFullPayment
                              ? Icons.check_circle
                              : Icons.hourglass_bottom,
                          size: 16,
                          color: _isFullPayment ? c.success : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isFullPayment
                              ? AppStrings.bookingSuccessPaid
                              : AppStrings.bookingSuccessAdvanceLabel,
                          style: TextStyle(
                            color: _isFullPayment ? c.success : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      PriceCalculator.formatPrice(widget.advanceAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isFullPayment ? c.success : Colors.orange,
                      ),
                    ),
                  ],
                ),
                if (!_isFullPayment) ...[
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        AppStrings.bookingSuccessBalanceDue,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        PriceCalculator.formatPrice(_remainingAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  AppStrings.bookingSuccessPaymentAtVenue,
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    final c = AppColors.of(context);
    return Column(
      children: [
        // Send Confirmation via Admin WhatsApp
        _buildMainActionButton(
          icon: _confirmationSent ? Icons.check_circle : Icons.send,
          label: _confirmationSent
              ? AppStrings.bookingSuccessConfirmationSent
              : AppStrings.bookingSuccessSendConfirmation,
          sublabel:
              _confirmationSent ? null : AppStrings.bookingSuccessViaFieldPass,
          color: _confirmationSent ? c.success : const Color(0xFF25D366),
          isLoading: _isSendingConfirmation,
          onTap: _confirmationSent ? null : _sendBookingConfirmation,
        ),

        const SizedBox(height: 12),

        // Additional Actions Row
        Row(
          children: [
            // Send Receipt (for paid bookings)
            if (_hasAdvance)
              Expanded(
                child: _buildSmallActionButton(
                  icon: Icons.receipt_long,
                  label: AppStrings.bookingSuccessSendReceipt,
                  color: c.primary,
                  onTap: _sendPaymentReceipt,
                ),
              ),

            if (_hasAdvance) const SizedBox(width: 10),

            // Copy Details
            Expanded(
              child: _buildSmallActionButton(
                icon: Icons.copy,
                label: AppStrings.bookingSuccessCopyDetails,
                color: Colors.grey.shade700,
                onTap: _copyBookingDetails,
              ),
            ),

            const SizedBox(width: 10),

            // Share
            Expanded(
              child: _buildSmallActionButton(
                icon: Icons.share,
                label: AppStrings.bookingSuccessShare,
                color: Colors.blue.shade600,
                onTap: _shareBookingDetails,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainActionButton({
    required IconData icon,
    required String label,
    String? sublabel,
    required Color color,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    isLoading ? AppStrings.bookingSuccessSending : label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    final c = AppColors.of(context);
    return TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      ),
      child: Text(
        AppStrings.bookingSuccessDone,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ========== Action Methods ==========

  /// Build booking confirmation message (without phone number)
  String _buildConfirmationMessage() {
    final netInfo = widget.turf.numberOfNets > 1
        ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}'
        : '';
    final advanceInfo = _hasAdvance
        ? '\n💵 *Advance Paid:* ₹${widget.advanceAmount.toInt()}${!_isFullPayment ? '\n💳 *Balance Due:* ₹${_remainingAmount.toInt()}' : ''}'
        : '\n💳 *Payment:* At venue';

    return '''🎉 *Booking Confirmed!*

Hi ${widget.customerName},

Your booking at *TurfBook* is confirmed!

📍 *Venue:* ${widget.turf.turfName}$netInfo
📅 *Date:* ${widget.dateStr}
⏰ *Time:* ${widget.slot.displayTimeRange}
💰 *Amount:* ₹${widget.bookingAmount.toInt()}$advanceInfo

🎫 *Booking ID:* #${widget.bookingId.substring(0, 8).toUpperCase()}

Please arrive 10 mins early. See you there! 🏏

📞 For customer support, call +91 9929615076

— *TurfBook*''';
  }

  /// Build payment receipt message (without phone number)
  String _buildReceiptMessage() {
    final netInfo = widget.turf.numberOfNets > 1
        ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}'
        : '';

    return '''✅ *Payment Receipt*

Hi ${widget.customerName},

Thank you for your payment!

📍 *Venue:* ${widget.turf.turfName}$netInfo
📅 *Date:* ${widget.dateStr}
⏰ *Time:* ${widget.slot.displayTimeRange}

💰 *Amount Paid:* ₹${widget.advanceAmount.toInt()}
${!_isFullPayment ? '💳 *Balance Due:* ₹${_remainingAmount.toInt()}' : ''}
🎫 *Booking ID:* #${widget.bookingId.substring(0, 8).toUpperCase()}

See you at the turf! 🏏

📞 For customer support, call +91 9929615076

— *TurfBook*''';
  }

  /// Send booking confirmation via WhatsApp Cloud API
  Future<void> _sendBookingConfirmation() async {
    setState(() => _isSendingConfirmation = true);

    try {
      final message = _buildConfirmationMessage();
      final sent = await WhatsAppService.sendTextMessage(
        toPhone: widget.customerPhone,
        message: message,
      );

      if (mounted) {
        setState(() {
          _isSendingConfirmation = false;
          _confirmationSent = sent;
        });

        if (!sent) {
          showAppToast(
            context,
            AppStrings.bookingSuccessSendFailed,
            type: ToastType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingConfirmation = false);
        showAppToast(context, '${AppStrings.bookingSuccessSendFailed}: $e',
            type: ToastType.error);
      }
    }
  }

  /// Send payment receipt via WhatsApp Cloud API
  Future<void> _sendPaymentReceipt() async {
    try {
      final message = _buildReceiptMessage();
      final sent = await WhatsAppService.sendTextMessage(
        toPhone: widget.customerPhone,
        message: message,
      );

      if (!mounted) return;

      showAppToast(
        context,
        sent
            ? AppStrings.bookingSuccessReceiptSent
            : AppStrings.bookingSuccessReceiptFailed,
        type: sent ? ToastType.success : ToastType.error,
      );
      if (sent) {
        setState(() {
          _confirmationSent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${AppStrings.bookingSuccessReceiptFailed}: $e',
            type: ToastType.error);
      }
    }
  }

  /// Copy booking details to clipboard
  void _copyBookingDetails() {
    final netInfo = widget.turf.numberOfNets > 1
        ? ' (Net ${widget.selectedNetNumber})'
        : '';
    final details = '''
BOOKING CONFIRMATION
====================
Booking ID: #${widget.bookingId.substring(0, 8).toUpperCase()}

Venue: ${widget.turf.turfName}$netInfo
Date: ${widget.dateStr}
Time: ${widget.slot.displayTimeRange}

Customer: ${widget.customerName}

Amount: ₹${widget.bookingAmount.toInt()}
${_hasAdvance ? 'Advance: ₹${widget.advanceAmount.toInt()}' : ''}
${!_isFullPayment && _hasAdvance ? 'Balance: ₹${_remainingAmount.toInt()}' : ''}

— TurfBook
    '''
        .trim();

    Clipboard.setData(ClipboardData(text: details));
    showAppToast(context, AppStrings.bookingSuccessCopied,
        type: ToastType.success);
  }

  /// Share booking details
  Future<void> _shareBookingDetails() async {
    final netInfo = widget.turf.numberOfNets > 1
        ? ' (Net ${widget.selectedNetNumber})'
        : '';
    final shareText = '''
🏏 Booking at ${widget.turf.turfName}$netInfo

📅 ${widget.dateStr}
⏰ ${widget.slot.displayTimeRange}
💰 ₹${widget.bookingAmount.toInt()}

#${widget.bookingId.substring(0, 8).toUpperCase()}
— TurfBook
    '''
        .trim();

    // Use clipboard as fallback for sharing
    Clipboard.setData(ClipboardData(text: shareText));
    showAppToast(context, AppStrings.bookingSuccessCopiedShare,
        type: ToastType.success);
  }
}

/// Lightweight scale-on-press wrapper for slot tiles
class _SlotTapWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onTap;

  const _SlotTapWrapper({
    required this.child,
    required this.enabled,
    this.onTap,
  });

  @override
  State<_SlotTapWrapper> createState() => _SlotTapWrapperState();
}

class _SlotTapWrapperState extends State<_SlotTapWrapper> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

/// Custom painter that draws a dashed line for the ticket tear divider
class _TicketDashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double x = 0;
    final y = size.height / 2;

    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter that draws abstract cricket stumps as a faded watermark
class _StumpsPainter extends CustomPainter {
  final Color color;
  _StumpsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Three stumps — evenly spaced
    final stumpSpacing = w * 0.28;
    final stumpStartX = w * 0.22;
    final stumpTop = h * 0.08;
    final stumpBottom = h * 0.82;

    for (int i = 0; i < 3; i++) {
      final x = stumpStartX + (i * stumpSpacing);
      canvas.drawLine(Offset(x, stumpTop), Offset(x, stumpBottom), paint);
    }

    // Two bails — resting on top of stumps
    final bailPaint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Bail 1: between stump 1 and 2
    final bail1Left = stumpStartX;
    final bail1Right = stumpStartX + stumpSpacing;
    final bail1Y = stumpTop - 1;
    canvas.drawLine(Offset(bail1Left - 3, bail1Y),
        Offset(bail1Right + 3, bail1Y), bailPaint);

    // Bail 2: between stump 2 and 3
    final bail2Left = stumpStartX + stumpSpacing;
    final bail2Right = stumpStartX + 2 * stumpSpacing;
    final bail2Y = stumpTop - 1;
    canvas.drawLine(Offset(bail2Left - 3, bail2Y),
        Offset(bail2Right + 3, bail2Y), bailPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for diagonal stripe accents on ticket edges
class _TicketEdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt;

    const gap = 8.0;
    double y = 0;
    while (y < size.height + size.width) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - size.width), paint);
      y += gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
