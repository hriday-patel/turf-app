import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/slot_business_rules.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Slot Management Screen.
///
/// Allows the owner of a specific turf to view and manage 24-hour slots
/// for a chosen date.
///
/// Responsibilities:
///   * Render a calendar bounded to today … today+1y, with day-level selection.
///   * Per-net filtering when the turf has more than one net.
///   * Period (Morning / Afternoon / Evening / Night) toggles that bulk
///     block or unblock all available slots in the period that fall within
///     the turf’s operating hours. Past slots and manually-blocked slots are
///     never touched by bulk operations.
///   * Per-slot block/unblock via a bottom sheet.
///
/// Lifecycle / refresh:
///   * `initState` schedules a `_refreshAndLoadSlots()` call after the first
///     frame; this fetches the latest turf settings and then regenerates the
///     slot grid for the selected date.
///   * `RouteAware.didPopNext` re-runs the same refresh when returning from
///     a child route (e.g. the booking sheet).
///   * Both entry points are guarded by `_isRefreshing` to prevent stacked
///     network calls.
///
/// Security:
///   * The `widget.turfId` is validated against the signed-in owner via
///     `turf.ownerId == authProvider.currentUserId`. Mismatch renders a
///     dedicated unauthorized scaffold.
class SlotManagementScreen extends StatefulWidget {
  final String turfId;

  const SlotManagementScreen({super.key, required this.turfId});

  @override
  State<SlotManagementScreen> createState() => _SlotManagementScreenState();
}

class _SlotManagementScreenState extends State<SlotManagementScreen>
    with RouteAware {
  DateTime _selectedDate = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  int _selectedNetNumber = 1;
  bool _isRefreshing = false;
  bool _isApplyingBulk = false;

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

  DateTime _clampDateToBookingRange(DateTime value) {
    final day = _dateOnly(value);
    if (day.isBefore(_minSelectableDate)) return _minSelectableDate;
    if (day.isAfter(_maxSelectableDate)) return _maxSelectableDate;
    return day;
  }

  // Day closure toggles
  bool _isDayOpen = true;
  bool _isMorningOpen = true;
  bool _isAfternoonOpen = true;
  bool _isEveningOpen = true;
  bool _isNightOpen = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = _minSelectableDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAndLoadSlots();
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
    AppRoutes.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshAndLoadSlots();
  }

  /// Refresh turf data from database, then load/regenerate slots.
  /// SM-02/SM-14: try/catch around network call; `_isRefreshing` debounce
  /// guards against stacked invocations from initState + didPopNext.
  Future<void> _refreshAndLoadSlots() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final ownerId = authProvider.currentUserId;
      if (ownerId != null) {
        await turfProvider.refreshTurfs(ownerId);
      }
      if (!mounted) return;
      await _loadSlots(forceRegenerate: true);
    } catch (_) {
      if (mounted) {
        showAppToast(context, AppStrings.slotMgmtRefreshFailed,
            type: ToastType.error);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// SM-03: load slots with awaited error handling and toast feedback.
  Future<void> _loadSlots({bool forceRegenerate = false}) async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);
    if (turf == null) return;
    final dateStr = _selectedDate.toIso8601String().split('T')[0];
    try {
      await slotProvider.generateSlots(
        turf: turf,
        date: dateStr,
        forceRegenerate: forceRegenerate,
      );
      if (!mounted) return;
      await slotProvider.loadSlots(widget.turfId, dateStr);
      if (!mounted) return;
      _updateToggleStatesFromSlots();
    } catch (_) {
      if (mounted) {
        showAppToast(context, AppStrings.slotMgmtLoadFailed,
            type: ToastType.error);
      }
    }
  }

  /// Check if a slot's date+time has already passed
  bool _isSlotInPast(SlotModel slot) {
    final now = DateTime.now();
    final slotDate = DateTime.parse(slot.date);
    final parts = slot.startTime.split(':');
    final slotDateTime = DateTime(
      slotDate.year,
      slotDate.month,
      slotDate.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    return now.isAfter(slotDateTime);
  }

  /// Check if a slot falls within the turf's operational hours.
  /// SM-12: caller hoists the turf reference; we do not refetch via Provider.
  bool _isWithinOperationalHours(SlotModel slot, TurfModel turf) {
    final openHour = int.parse(turf.openTime.split(':')[0]);
    final openMinute = int.parse(turf.openTime.split(':')[1]);
    final closeHour = int.parse(turf.closeTime.split(':')[0]);
    final closeMinute = int.parse(turf.closeTime.split(':')[1]);

    final openMinutes = openHour * 60 + openMinute;
    final closeMinutes = SlotBusinessRules.normalizeCloseMinutes(
      openMinutes: openMinutes,
      closeMinutesRaw: closeHour * 60 + closeMinute,
    );

    final startParts = slot.startTime.split(':');
    final endParts = slot.endTime.split(':');
    final slotStartMin =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final slotEndMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final slotEndAdj = slotEndMin == 0 ? 1440 : slotEndMin;

    return SlotBusinessRules.isWithinOperatingHours(
      openMinutes: openMinutes,
      closeMinutes: closeMinutes,
      slotStartMin: slotStartMin,
      slotEndMin: slotEndAdj,
    );
  }

  /// Get slots filtered by the currently selected net number
  List<SlotModel> _getSlotsForSelectedNet(List<SlotModel> allSlots) {
    return allSlots.where((s) => s.netNumber == _selectedNetNumber).toList();
  }

  void _updateToggleStatesFromSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);
    if (turf == null) return;

    if (slotProvider.slots.isEmpty) return;

    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    if (netSlots.isEmpty) return;

    // Count period-closed slots that are WITHIN operational hours.
    // Only these affect toggle state. Auto-blocked "Closed" slots
    // (outside operating hours) and manually-blocked slots do NOT affect toggles.
    final closedCounts = <SlotPeriod, int>{
      SlotPeriod.morning: 0,
      SlotPeriod.afternoon: 0,
      SlotPeriod.evening: 0,
      SlotPeriod.night: 0,
    };

    for (final slot in netSlots) {
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      final period = SlotBusinessRules.periodForHour(hour);
      final isPeriodClosed = slot.status == SlotStatus.blocked &&
          SlotBusinessRules.isPeriodCloseReason(slot.blockReason) &&
          _isWithinOperationalHours(slot, turf);
      if (isPeriodClosed) {
        closedCounts[period] = (closedCounts[period] ?? 0) + 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _isMorningOpen = (closedCounts[SlotPeriod.morning] ?? 0) == 0;
      _isAfternoonOpen = (closedCounts[SlotPeriod.afternoon] ?? 0) == 0;
      _isEveningOpen = (closedCounts[SlotPeriod.evening] ?? 0) == 0;
      _isNightOpen = (closedCounts[SlotPeriod.night] ?? 0) == 0;
      _isDayOpen =
          _isMorningOpen || _isAfternoonOpen || _isEveningOpen || _isNightOpen;
    });
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDate = _clampDateToBookingRange(selectedDay);
      // Reset toggles when changing date
      _isDayOpen = true;
      _isMorningOpen = true;
      _isAfternoonOpen = true;
      _isEveningOpen = true;
      _isNightOpen = true;
    });
    // When changing date, force regenerate for future dates to apply latest settings
    _loadSlots(forceRegenerate: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ownerId =
        Provider.of<AuthProvider>(context, listen: false).currentUserId;
    return Selector<TurfProvider, TurfModel?>(
      selector: (_, p) => p.getTurfById(widget.turfId),
      builder: (context, turf, _) {
        if (turf == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppStrings.slotMgmtTitle,
                  style: TextStyle(color: c.textPrimary)),
              backgroundColor: c.background,
              elevation: 0,
            ),
            backgroundColor: c.background,
            body: Center(
              child: Text(AppStrings.slotMgmtTurfNotFound,
                  style: TextStyle(color: c.textPrimary)),
            ),
          );
        }

        // SM-01 ownership guard — only the turf owner may manage slots.
        if (ownerId == null || turf.ownerId != ownerId) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppStrings.slotMgmtTitle,
                  style: TextStyle(color: c.textPrimary)),
              backgroundColor: c.background,
              elevation: 0,
            ),
            backgroundColor: c.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppStrings.slotMgmtNotAuthorized,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textPrimary),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: c.background,
          body: GlassScaffoldBackground(
            child: SafeArea(
              child: Column(
                children: [
                  GlassAppBar(title: turf.turfName),
                  // Calendar
                  Expanded(
                    child: Column(
                      children: [
                        _buildCalendar(),

                        // Net Selector (only for multi-net turfs)
                        if (turf.numberOfNets > 1)
                          _buildNetSelector(turf.numberOfNets),

                        // Day Controls (On/Off toggles)
                        _buildDayControls(),

                        // Slot Status Legend
                        _buildLegend(),

                        // Slots Grid — grouped by period, filtered by net
                        Expanded(
                          child: _buildSlotsGrid(turf),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendar() {
    final c = AppColors.of(context);
    return Container(
      color: c.glassFill,
      child: TableCalendar(
        firstDay: _minSelectableDate,
        lastDay: _maxSelectableDate,
        focusedDay: _selectedDate,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
        onDaySelected: _onDaySelected,
        onFormatChanged: (format) {
          setState(() => _calendarFormat = format);
        },
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: c.primary,
            shape: BoxShape.circle,
          ),
          weekendTextStyle: TextStyle(color: c.secondary),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
        ),
      ),
    );
  }

  Widget _buildNetSelector(int numberOfNets) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: c.glassFill,
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 16, color: c.textSecondary),
          const SizedBox(width: 8),
          Text(
            AppStrings.slotMgmtNetLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          ...List.generate(numberOfNets, (i) {
            final net = i + 1;
            final isSelected = _selectedNetNumber == net;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: '${AppStrings.slotMgmtNetTooltipPrefix}$net',
                child: ChoiceChip(
                  label: Text('${AppStrings.slotMgmtNetLabel} $net'),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedNetNumber = net);
                    _updateToggleStatesFromSlots();
                  },
                  selectedColor: c.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? c.onPrimary : c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: c.glassFill,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(c.success, AppStrings.slotMgmtLegendAvailable),
          _buildLegendItem(c.warning, AppStrings.slotMgmtLegendReserved),
          _buildLegendItem(c.primary, AppStrings.slotMgmtLegendBooked),
          _buildLegendItem(c.error, AppStrings.slotMgmtLegendBlocked),
          _buildLegendItem(c.textDisabled, AppStrings.slotMgmtLegendClosed),
        ],
      ),
    );
  }

  Widget _buildDayControls() {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: c.glassFill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Day Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isDayOpen ? Icons.wb_sunny : Icons.nights_stay,
                    color: _isDayOpen ? c.warning : c.textDisabled,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.slotMgmtDayStatus,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isDayOpen
                          ? c.success.withValues(alpha: 0.1)
                          : c.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isDayOpen
                          ? AppStrings.slotMgmtOpen
                          : AppStrings.slotMgmtClosed,
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDayOpen ? c.success : c.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isDayOpen,
                    onChanged:
                        _isApplyingBulk ? null : (value) => _toggleDay(value),
                    activeColor: c.success,
                  ),
                ],
              ),
            ],
          ),

          // Time Period Toggles
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: c.textSecondary),
              const SizedBox(width: 4),
              Text(
                AppStrings.slotMgmtTimePeriods,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildPeriodToggle(
                      AppStrings.slotMgmtPeriodMorning,
                      AppStrings.slotMgmtRangeMorning,
                      _isMorningOpen,
                      (v) => _togglePeriod(SlotPeriod.morning, v))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPeriodToggle(
                      AppStrings.slotMgmtPeriodAfternoon,
                      AppStrings.slotMgmtRangeAfternoon,
                      _isAfternoonOpen,
                      (v) => _togglePeriod(SlotPeriod.afternoon, v))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: _buildPeriodToggle(
                      AppStrings.slotMgmtPeriodEvening,
                      AppStrings.slotMgmtRangeEvening,
                      _isEveningOpen,
                      (v) => _togglePeriod(SlotPeriod.evening, v))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPeriodToggle(
                      AppStrings.slotMgmtPeriodNight,
                      AppStrings.slotMgmtRangeNight,
                      _isNightOpen,
                      (v) => _togglePeriod(SlotPeriod.night, v))),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildPeriodToggle(
      String label, String timeRange, bool isOpen, Function(bool) onChanged) {
    final c = AppColors.of(context);
    return Semantics(
      label:
          '$label ${isOpen ? AppStrings.slotMgmtOpen : AppStrings.slotMgmtClosed}',
      button: true,
      toggled: isOpen,
      child: GestureDetector(
        onTap: _isApplyingBulk ? null : () => onChanged(!isOpen),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isOpen
                ? c.success.withValues(alpha: 0.1)
                : c.textSecondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOpen
                  ? c.success.withValues(alpha: 0.3)
                  : c.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isOpen ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                    Text(
                      timeRange,
                      style: TextStyle(
                        fontSize: 10,
                        color: isOpen
                            ? c.textSecondary
                            : c.textSecondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 20,
                decoration: BoxDecoration(
                  color: isOpen ? c.success : c.textSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      left: isOpen ? 18 : 2,
                      top: 2,
                      child: Container(
                        width: 16,
                        height: 16,
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
    );
  }

  // U10: Count slots in a given period that would be affected by a bulk close.
  int _countAffectedSlots(SlotPeriod? period) {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    int count = 0;
    for (final slot in netSlots) {
      if (_isSlotInPast(slot)) continue;
      if (slot.status != SlotStatus.available) continue;
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      final slotPeriod = SlotBusinessRules.periodForHour(hour);
      if (period == null || period == slotPeriod) count++;
    }
    return count;
  }

  Future<bool> _confirmBulkClose(String label, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${AppStrings.slotMgmtConfirmCloseTitlePrefix}$label${AppStrings.slotMgmtConfirmCloseTitleSuffix}',
        ),
        content: Text(slotMgmtConfirmCloseBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.slotMgmtConfirmCloseCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.slotMgmtConfirmCloseAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _toggleDay(bool isOpen) async {
    if (_isApplyingBulk) return;
    // U10: Confirm before bulk-closing the entire day.
    if (!isOpen) {
      final affected = _countAffectedSlots(null);
      final ok = await _confirmBulkClose(
          AppStrings.slotMgmtConfirmCloseDayLabel, affected);
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      _isDayOpen = isOpen;
      if (!isOpen) {
        _isMorningOpen = false;
        _isAfternoonOpen = false;
        _isEveningOpen = false;
        _isNightOpen = false;
      } else {
        _isMorningOpen = true;
        _isAfternoonOpen = true;
        _isEveningOpen = true;
        _isNightOpen = true;
      }
    });
    await _applyPeriodChanges();
  }

  void _togglePeriod(SlotPeriod period, bool isOpen) async {
    if (_isApplyingBulk) return;
    // U10: Confirm before bulk-closing a period.
    if (!isOpen) {
      final affected = _countAffectedSlots(period);
      final label =
          '${_periodDisplayName(period)}${AppStrings.slotMgmtPeriodSlotsSuffix}';
      final ok = await _confirmBulkClose(label, affected);
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      switch (period) {
        case SlotPeriod.morning:
          _isMorningOpen = isOpen;
          break;
        case SlotPeriod.afternoon:
          _isAfternoonOpen = isOpen;
          break;
        case SlotPeriod.evening:
          _isEveningOpen = isOpen;
          break;
        case SlotPeriod.night:
          _isNightOpen = isOpen;
          break;
      }
      if (!_isMorningOpen &&
          !_isAfternoonOpen &&
          !_isEveningOpen &&
          !_isNightOpen) {
        _isDayOpen = false;
      } else if (!_isDayOpen) {
        _isDayOpen = true;
      }
    });
    await _applyPeriodChanges();
  }

  String _periodDisplayName(SlotPeriod p) {
    switch (p) {
      case SlotPeriod.morning:
        return AppStrings.slotMgmtPeriodMorning;
      case SlotPeriod.afternoon:
        return AppStrings.slotMgmtPeriodAfternoon;
      case SlotPeriod.evening:
        return AppStrings.slotMgmtPeriodEvening;
      case SlotPeriod.night:
        return AppStrings.slotMgmtPeriodNight;
    }
  }

  /// SM-04/SM-05: bulk apply period state with try/catch, progress flag,
  /// and a null-safe owner id check; failures surface a single toast.
  Future<void> _applyPeriodChanges() async {
    if (_isApplyingBulk) return;
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);
    final ownerId = authProvider.currentUserId;

    if (turf == null) return;
    if (ownerId == null) {
      if (mounted) {
        showAppToast(context, AppStrings.slotMgmtSessionExpired,
            type: ToastType.error);
      }
      return;
    }

    setState(() => _isApplyingBulk = true);
    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    bool hadFailure = false;

    try {
      for (final slot in netSlots) {
        if (_isSlotInPast(slot)) continue;

        final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
        final period = SlotBusinessRules.periodForHour(hour);
        bool periodOpen;
        switch (period) {
          case SlotPeriod.morning:
            periodOpen = _isMorningOpen;
            break;
          case SlotPeriod.afternoon:
            periodOpen = _isAfternoonOpen;
            break;
          case SlotPeriod.evening:
            periodOpen = _isEveningOpen;
            break;
          case SlotPeriod.night:
            periodOpen = _isNightOpen;
            break;
        }
        final shouldBeBlocked = !periodOpen;

        try {
          if (shouldBeBlocked && slot.status == SlotStatus.available) {
            await slotProvider.blockSlot(
              slot.slotId,
              ownerId,
              BlockReason.periodClosedByOwner,
            );
          } else if (!shouldBeBlocked && slot.status == SlotStatus.blocked) {
            if (SlotBusinessRules.isPeriodCloseReason(slot.blockReason) &&
                _isWithinOperationalHours(slot, turf)) {
              await slotProvider.unblockSlot(slot.slotId);
            }
          }
        } catch (_) {
          hadFailure = true;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isApplyingBulk = false);
      } else {
        _isApplyingBulk = false;
      }
    }

    if (hadFailure && mounted) {
      showAppToast(context, AppStrings.slotMgmtBulkUpdateFailed,
          type: ToastType.error);
    }

    await _loadSlots();
  }

  Widget _buildLegendItem(Color color, String label) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSlotsGrid(TurfModel turf) {
    return Selector<SlotProvider, ({bool loading, List<SlotModel> slots})>(
      selector: (_, p) => (loading: p.isLoading, slots: p.slots),
      builder: (context, snap, _) {
        if (snap.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Filter slots by selected net
        final netSlots = _getSlotsForSelectedNet(snap.slots);

        if (netSlots.isEmpty) {
          final c = AppColors.of(context);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_busy,
                  size: 64,
                  color: c.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.slotMgmtNoSlotsForDate,
                  style: TextStyle(
                    fontSize: 16,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Group slots by period using shared helper.
        final morningSlots = <SlotModel>[];
        final afternoonSlots = <SlotModel>[];
        final eveningSlots = <SlotModel>[];
        final nightSlots = <SlotModel>[];
        for (final s in netSlots) {
          final h = int.tryParse(s.startTime.split(':')[0]) ?? 0;
          switch (SlotBusinessRules.periodForHour(h)) {
            case SlotPeriod.morning:
              morningSlots.add(s);
              break;
            case SlotPeriod.afternoon:
              afternoonSlots.add(s);
              break;
            case SlotPeriod.evening:
              eveningSlots.add(s);
              break;
            case SlotPeriod.night:
              nightSlots.add(s);
              break;
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPeriodSection(
                AppStrings.slotMgmtPeriodMorning,
                AppStrings.slotMgmtRangeMorningLong,
                Icons.wb_sunny_outlined,
                morningSlots,
                turf),
            const SizedBox(height: 16),
            _buildPeriodSection(
                AppStrings.slotMgmtPeriodAfternoon,
                AppStrings.slotMgmtRangeAfternoonLong,
                Icons.wb_cloudy_outlined,
                afternoonSlots,
                turf),
            const SizedBox(height: 16),
            _buildPeriodSection(
                AppStrings.slotMgmtPeriodEvening,
                AppStrings.slotMgmtRangeEveningLong,
                Icons.nights_stay_outlined,
                eveningSlots,
                turf),
            const SizedBox(height: 16),
            _buildPeriodSection(
                AppStrings.slotMgmtPeriodNight,
                AppStrings.slotMgmtRangeNightLong,
                Icons.dark_mode_outlined,
                nightSlots,
                turf),
          ],
        );
      },
    );
  }

  Widget _buildPeriodSection(String title, String timeRange, IconData icon,
      List<SlotModel> slots, TurfModel turf) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period header
        Row(
          children: [
            Icon(icon, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeRange,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${slots.where((s) => s.status == SlotStatus.available).length}/${slots.length}${AppStrings.slotMgmtOpenCountSuffix}',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: c.inputBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                AppStrings.slotMgmtNoSlotsInPeriod,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              return _buildSlotCard(slots[index], turf);
            },
          ),
      ],
    );
  }

  Widget _buildSlotCard(SlotModel slot, TurfModel turf) {
    final c = AppColors.of(context);
    Color statusColor;
    IconData statusIcon;

    final isPast = _isSlotInPast(slot);
    final reason = slot.blockReason;

    // Slots that are system-closed or period-closed are non-interactive and dimmed.
    final isSystemClosed = slot.status == SlotStatus.blocked &&
        (reason == BlockReason.closed ||
            SlotBusinessRules.isPeriodCloseReason(reason));

    // Manually-blocked slots are interactive (can be unblocked individually).
    final isManuallyBlocked = slot.status == SlotStatus.blocked &&
        reason == BlockReason.manuallyBlockedByOwner;

    if (isPast) {
      statusColor = c.textDisabled;
      statusIcon = Icons.history;
    } else if (isSystemClosed) {
      statusColor = c.textDisabled;
      statusIcon = Icons.block_outlined;
    } else {
      switch (slot.status) {
        case SlotStatus.available:
          statusColor = c.success;
          statusIcon = Icons.check_circle_outline;
          break;
        case SlotStatus.reserved:
          statusColor = c.warning;
          statusIcon = Icons.schedule;
          break;
        case SlotStatus.booked:
          statusColor = c.primary;
          statusIcon = Icons.event_available;
          break;
        case SlotStatus.blocked:
          statusColor = c.error;
          statusIcon = Icons.block;
          break;
      }
    }

    final isInteractive = !isPast && !isSystemClosed;
    // SM-18: fold past-state opacity into a single alpha calculation rather
    // than wrapping the card in an Opacity layer.
    final double fillAlpha = isPast ? 0.05 : (isInteractive ? 0.1 : 0.15);
    final double borderAlpha = isPast ? 0.2 : (isInteractive ? 0.5 : 0.3);
    final double textAlpha = isPast ? 0.5 : 1.0;

    return Tooltip(
      message: '${slot.displayTimeRange} — ${slot.status.displayName}',
      child: GestureDetector(
        onTap: isInteractive ? () => _showSlotActions(slot, turf) : null,
        child: Container(
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: fillAlpha),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: statusColor.withValues(alpha: borderAlpha)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon,
                  color: statusColor.withValues(alpha: textAlpha), size: 24),
              const SizedBox(height: 6),
              Text(
                slot.displayTimeRange.split(' - ')[0],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor.withValues(alpha: textAlpha),
                ),
              ),
              if (isPast)
                Text(
                  AppStrings.slotMgmtBadgePast,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (isSystemClosed)
                Text(
                  AppStrings.slotMgmtBadgeClosed,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (isManuallyBlocked)
                Text(
                  AppStrings.slotMgmtBadgeBlocked,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.error,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Text(
                  PriceCalculator.formatPrice(slot.price),
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSlotActions(SlotModel slot, TurfModel turf) {
    if (_isSlotInPast(slot)) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final ownerId = authProvider.currentUserId;
    if (ownerId == null) {
      showAppToast(context, AppStrings.slotMgmtSessionExpired,
          type: ToastType.error);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final c = AppColors.of(sheetCtx);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                slot.displayTimeRange,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppStrings.slotMgmtSheetStatusPrefix}${slot.status.displayName}',
                style: TextStyle(color: c.textSecondary),
              ),
              const SizedBox(height: 24),
              if (slot.status == SlotStatus.available) ...[
                _buildActionButton(
                  icon: Icons.block,
                  label: AppStrings.slotMgmtActionBlock,
                  color: c.warning,
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      await slotProvider.blockSlot(
                        slot.slotId,
                        ownerId,
                        BlockReason.manuallyBlockedByOwner,
                      );
                    } catch (_) {
                      if (mounted) {
                        showAppToast(
                            context, AppStrings.slotMgmtBulkUpdateFailed,
                            type: ToastType.error);
                      }
                    }
                    if (mounted) await _loadSlots();
                  },
                ),
              ],
              if (slot.status == SlotStatus.blocked) ...[
                _buildActionButton(
                  icon: Icons.check,
                  label: AppStrings.slotMgmtActionUnblock,
                  color: c.success,
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      final isOpHours = _isWithinOperationalHours(slot, turf);
                      await slotProvider.unblockSlot(
                        slot.slotId,
                        overrideMarker:
                            isOpHours ? null : BlockReason.openedByOwner,
                      );
                    } catch (_) {
                      if (mounted) {
                        showAppToast(
                            context, AppStrings.slotMgmtBulkUpdateFailed,
                            type: ToastType.error);
                      }
                    }
                    if (mounted) await _loadSlots();
                  },
                ),
              ],
              if (slot.status == SlotStatus.booked) ...[
                _buildActionButton(
                  icon: Icons.info,
                  label: AppStrings.slotMgmtActionViewBooking,
                  color: c.info,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showAppToast(
                        context, AppStrings.slotMgmtBookingDetailsComingSoon,
                        type: ToastType.info);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final c = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: c.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
