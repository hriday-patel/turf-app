import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Slot Management Screen
/// Allows owner to view and manage slots for a specific date
class SlotManagementScreen extends StatefulWidget {
  final String turfId;

  const SlotManagementScreen({super.key, required this.turfId});

  @override
  State<SlotManagementScreen> createState() => _SlotManagementScreenState();
}

class _SlotManagementScreenState extends State<SlotManagementScreen> with RouteAware {
  DateTime _selectedDate = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  int _selectedNetNumber = 1;

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
    // Always refresh turf data first, then load slots
    _refreshAndLoadSlots();
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
    debugPrint('SlotManagement: didPopNext - refreshing data');
    _refreshAndLoadSlots();
  }

  /// Refresh turf data from database, then load/generate slots
  Future<void> _refreshAndLoadSlots() async {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // First refresh turf data to get latest settings
    if (authProvider.currentUserId != null) {
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
    }
    
    if (!mounted) return;
    // Then load slots with updated turf data
    _loadSlots(forceRegenerate: true);
  }

  void _loadSlots({bool forceRegenerate = false}) {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    if (turf != null) {
      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      
      // Generate slots (force regenerate deletes + recreates for a clean 24-hour set)
      slotProvider.generateSlots(
        turf: turf, 
        date: dateStr,
        forceRegenerate: forceRegenerate,
      ).then((_) async {
        if (!mounted) return;
        await slotProvider.loadSlots(widget.turfId, dateStr);
        if (mounted) _updateToggleStatesFromSlots();
      });
    }
  }

  /// Check if a slot's date+time has already passed
  bool _isSlotInPast(SlotModel slot) {
    final now = DateTime.now();
    final slotDate = DateTime.parse(slot.date);
    final parts = slot.startTime.split(':');
    final slotDateTime = DateTime(
      slotDate.year, slotDate.month, slotDate.day,
      int.parse(parts[0]), int.parse(parts[1]),
    );
    return now.isAfter(slotDateTime);
  }

  /// Check if a slot falls within the turf's operational hours
  bool _isWithinOperationalHours(SlotModel slot) {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);
    if (turf == null) return true; // fallback: treat as operational

    final openHour = int.parse(turf.openTime.split(':')[0]);
    final openMinute = int.parse(turf.openTime.split(':')[1]);
    final closeHour = int.parse(turf.closeTime.split(':')[0]);
    final closeMinute = int.parse(turf.closeTime.split(':')[1]);

    final openMinutes = openHour * 60 + openMinute;
    final closeMinutesRaw = closeHour * 60 + closeMinute;
    int closeMinutes;
    if (closeMinutesRaw == 0) {
      closeMinutes = 1440;
    } else if (closeMinutesRaw == openMinutes) {
      closeMinutes = openMinutes;
    } else if (closeMinutesRaw < openMinutes) {
      closeMinutes = closeMinutesRaw + 1440;
    } else {
      closeMinutes = closeMinutesRaw;
    }

    final startParts = slot.startTime.split(':');
    final endParts = slot.endTime.split(':');
    final slotStartMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final slotEndMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final slotEndAdj = slotEndMin == 0 ? 1440 : slotEndMin;

    if (closeMinutes == openMinutes) return false;
    if (closeMinutes <= 1440) {
      return slotStartMin >= openMinutes && slotEndAdj <= closeMinutes;
    } else {
      final inDayPortion = slotStartMin >= openMinutes && slotEndAdj <= 1440;
      final inNightPortion = slotStartMin < (closeMinutes - 1440) && slotEndAdj <= (closeMinutes - 1440);
      return inDayPortion || inNightPortion;
    }
  }

  /// Get slots filtered by the currently selected net number
  List<SlotModel> _getSlotsForSelectedNet(List<SlotModel> allSlots) {
    return allSlots.where((s) => s.netNumber == _selectedNetNumber).toList();
  }

  void _updateToggleStatesFromSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    
    if (slotProvider.slots.isEmpty) return;
    
    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    if (netSlots.isEmpty) return;
    
    // Count period-closed slots that are WITHIN operational hours.
    // Only these affect toggle state. Auto-blocked "Closed" slots
    // (outside operating hours) and manually-blocked slots do NOT affect toggles.
    int morningPeriodClosed = 0;
    int afternoonPeriodClosed = 0;
    int eveningPeriodClosed = 0;
    int nightPeriodClosed = 0;
    
    for (final slot in netSlots) {
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      final isPeriodClosed = slot.status == SlotStatus.blocked &&
          (slot.blockReason ?? '').contains('Period closed') &&
          _isWithinOperationalHours(slot);
      
      if (hour >= 6 && hour < 12) {
        if (isPeriodClosed) morningPeriodClosed++;
      } else if (hour >= 12 && hour < 18) {
        if (isPeriodClosed) afternoonPeriodClosed++;
      } else if (hour >= 18 && hour < 24) {
        if (isPeriodClosed) eveningPeriodClosed++;
      } else {
        if (isPeriodClosed) nightPeriodClosed++;
      }
    }
    
    setState(() {
      // Period toggle is OPEN unless owner explicitly period-closed
      // operational-hour slots in it. Slots outside operating hours
      // and manually blocked slots don't affect toggles.
      _isMorningOpen = morningPeriodClosed == 0;
      _isAfternoonOpen = afternoonPeriodClosed == 0;
      _isEveningOpen = eveningPeriodClosed == 0;
      _isNightOpen = nightPeriodClosed == 0;
      
      // Day is open if any period is open
      _isDayOpen = _isMorningOpen || _isAfternoonOpen || _isEveningOpen || _isNightOpen;
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
    return Consumer<TurfProvider>(
      builder: (context, turfProvider, _) {
        final turf = turfProvider.getTurfById(widget.turfId);

        if (turf == null) {
          return Scaffold(
            appBar: AppBar(title: Text('Slot Management', style: TextStyle(color: c.textPrimary)), backgroundColor: c.background, elevation: 0),
            backgroundColor: c.background,
            body: Center(child: Text('Turf not found', style: TextStyle(color: c.textPrimary))),
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
                          child: _buildSlotsGrid(),
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
            'Net',
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
              child: ChoiceChip(
                label: Text('Net $net'),
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
          _buildLegendItem(c.success, 'Available'),
          _buildLegendItem(c.warning, 'Reserved'),
          _buildLegendItem(c.primary, 'Booked'),
          _buildLegendItem(c.error, 'Blocked'),
          _buildLegendItem(c.textDisabled, 'Closed'),
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
                    'Day Status',
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isDayOpen ? c.success.withValues(alpha: 0.1) : c.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isDayOpen ? 'OPEN' : 'CLOSED',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDayOpen ? c.success : c.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isDayOpen,
                    onChanged: (value) => _toggleDay(value),
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
                'Time Periods',
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
              Expanded(child: _buildPeriodToggle('Morning', '6AM-12PM', _isMorningOpen, (v) => _togglePeriod('morning', v))),
              const SizedBox(width: 8),
              Expanded(child: _buildPeriodToggle('Afternoon', '12PM-6PM', _isAfternoonOpen, (v) => _togglePeriod('afternoon', v))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildPeriodToggle('Evening', '6PM-12AM', _isEveningOpen, (v) => _togglePeriod('evening', v))),
              const SizedBox(width: 8),
              Expanded(child: _buildPeriodToggle('Night', '12AM-6AM', _isNightOpen, (v) => _togglePeriod('night', v))),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildPeriodToggle(String label, String timeRange, bool isOpen, Function(bool) onChanged) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!isOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isOpen ? c.success.withValues(alpha: 0.1) : c.textSecondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOpen ? c.success.withValues(alpha: 0.3) : c.textSecondary.withValues(alpha: 0.3),
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
                      color: isOpen ? c.textSecondary : c.textSecondary.withValues(alpha: 0.5),
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
    );
  }

  void _toggleDay(bool isOpen) async {
    setState(() {
      _isDayOpen = isOpen;
      if (!isOpen) {
        // Close all periods when day is closed
        _isMorningOpen = false;
        _isAfternoonOpen = false;
        _isEveningOpen = false;
        _isNightOpen = false;
      } else {
        // Open all periods when day is opened
        _isMorningOpen = true;
        _isAfternoonOpen = true;
        _isEveningOpen = true;
        _isNightOpen = true;
      }
    });
    await _applyPeriodChanges();
  }

  void _togglePeriod(String period, bool isOpen) async {
    setState(() {
      switch (period) {
        case 'morning':
          _isMorningOpen = isOpen;
          break;
        case 'afternoon':
          _isAfternoonOpen = isOpen;
          break;
        case 'evening':
          _isEveningOpen = isOpen;
          break;
        case 'night':
          _isNightOpen = isOpen;
          break;
      }
      // Check if all periods are closed, then close the day
      if (!_isMorningOpen && !_isAfternoonOpen && !_isEveningOpen && !_isNightOpen) {
        _isDayOpen = false;
      } else if (!_isDayOpen) {
        // If any period is opened, open the day
        _isDayOpen = true;
      }
    });
    await _applyPeriodChanges();
  }

  Future<void> _applyPeriodChanges() async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Only apply to slots for the selected net
    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    
    for (final slot in netSlots) {
      // Skip past slots — cannot toggle slots whose time has passed
      if (_isSlotInPast(slot)) continue;
      
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      bool shouldBeBlocked = false;
      
      // Determine which period this slot belongs to
      if (hour >= 6 && hour < 12) {
        shouldBeBlocked = !_isMorningOpen;
      } else if (hour >= 12 && hour < 18) {
        shouldBeBlocked = !_isAfternoonOpen;
      } else if (hour >= 18 && hour < 24) {
        shouldBeBlocked = !_isEveningOpen;
      } else {
        shouldBeBlocked = !_isNightOpen;
      }
      
      // Only change status for available or blocked slots (don't touch booked/reserved)
      if (shouldBeBlocked && slot.status == SlotStatus.available) {
        // Period close: block ALL available slots in the period
        await slotProvider.blockSlot(
          slot.slotId,
          authProvider.currentUserId!,
          'Period closed by owner',
        );
      } else if (!shouldBeBlocked && slot.status == SlotStatus.blocked) {
        // Period open: only unblock "Period closed" slots within operational hours.
        // Leave auto-closed ("Closed") and manually-blocked slots untouched.
        final reason = slot.blockReason ?? '';
        if (reason.contains('Period closed') && _isWithinOperationalHours(slot)) {
          await slotProvider.unblockSlot(slot.slotId);
        }
      }
    }
    
    // Reload to show updated status
    _loadSlots();
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

  Widget _buildSlotsGrid() {
    return Consumer<SlotProvider>(
      builder: (context, slotProvider, _) {
        if (slotProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Filter slots by selected net
        final netSlots = _getSlotsForSelectedNet(slotProvider.slots);

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
                  'No slots for this date',
                  style: TextStyle(
                    fontSize: 16,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Group slots by period
        final morningSlots = netSlots.where((s) {
          final h = int.tryParse(s.startTime.split(':')[0]) ?? 0;
          return h >= 6 && h < 12;
        }).toList();
        final afternoonSlots = netSlots.where((s) {
          final h = int.tryParse(s.startTime.split(':')[0]) ?? 0;
          return h >= 12 && h < 18;
        }).toList();
        final eveningSlots = netSlots.where((s) {
          final h = int.tryParse(s.startTime.split(':')[0]) ?? 0;
          return h >= 18 && h < 24;
        }).toList();
        final nightSlots = netSlots.where((s) {
          final h = int.tryParse(s.startTime.split(':')[0]) ?? 0;
          return h >= 0 && h < 6;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPeriodSection('Morning', '6 AM - 12 PM', Icons.wb_sunny_outlined, morningSlots),
            const SizedBox(height: 16),
            _buildPeriodSection('Afternoon', '12 PM - 6 PM', Icons.wb_cloudy_outlined, afternoonSlots),
            const SizedBox(height: 16),
            _buildPeriodSection('Evening', '6 PM - 12 AM', Icons.nights_stay_outlined, eveningSlots),
            const SizedBox(height: 16),
            _buildPeriodSection('Night', '12 AM - 6 AM', Icons.dark_mode_outlined, nightSlots),
          ],
        );
      },
    );
  }

  Widget _buildPeriodSection(String title, String timeRange, IconData icon, List<SlotModel> slots) {
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
              '${slots.where((s) => s.status == SlotStatus.available).length}/${slots.length} open',
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
                'No slots in this period',
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
              return _buildSlotCard(slots[index]);
            },
          ),
      ],
    );
  }

  Widget _buildSlotCard(SlotModel slot) {
    final c = AppColors.of(context);
    Color statusColor;
    IconData statusIcon;
    
    final isPast = _isSlotInPast(slot);
    final reason = slot.blockReason ?? '';

    // Slots that are system-closed or period-closed are non-interactive and dimmed.
    // Manually-blocked slots remain interactive (owner can unblock them).
    final isSystemClosed = slot.status == SlotStatus.blocked &&
        (reason == 'Closed' || reason.contains('Period closed'));

    // Manually-blocked slots are interactive (can be unblocked individually).
    final isManuallyBlocked = slot.status == SlotStatus.blocked &&
        reason == 'Manually blocked by owner';

    // Past slots are always dimmed and non-interactive
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
          // Manually blocked by owner — shown as red/interactive
          statusColor = c.error;
          statusIcon = Icons.block;
          break;
        default:
          statusColor = c.success;
          statusIcon = Icons.check_circle_outline;
      }
    }

    // Interactive: not past, not system-closed. Manually-blocked slots ARE interactive.
    final isInteractive = !isPast && !isSystemClosed;

    return GestureDetector(
      onTap: isInteractive ? () => _showSlotActions(slot) : null,
      child: Opacity(
        opacity: isPast ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: isInteractive ? 0.1 : 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withValues(alpha: isInteractive ? 0.5 : 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(height: 6),
              Text(
                slot.displayTimeRange.split(' - ')[0],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
              if (isPast)
                Text(
                  'Past',
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (isSystemClosed)
                Text(
                  'Closed',
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (isManuallyBlocked)
                Text(
                  'Blocked',
                  style: TextStyle(
                    fontSize: 10,
                    color: c.error,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Text(
                  '₹${slot.price.toInt()}',
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

  void _showSlotActions(SlotModel slot) {
    // Past slots cannot be toggled
    if (_isSlotInPast(slot)) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final c = AppColors.of(context);
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
                'Status: ${slot.status.displayName}',
                style: TextStyle(color: c.textSecondary),
              ),
              const SizedBox(height: 24),
              
              if (slot.status == SlotStatus.available) ...[
                _buildActionButton(
                  icon: Icons.block,
                  label: 'Block Slot',
                  color: c.warning,
                  onTap: () async {
                    Navigator.pop(context);
                    await slotProvider.blockSlot(
                      slot.slotId,
                      authProvider.currentUserId!,
                      'Manually blocked by owner',
                    );
                    // Individual block does not affect period/day toggles — just reload slots
                    _loadSlots();
                  },
                ),
              ],
              
              if (slot.status == SlotStatus.blocked) ...[
                _buildActionButton(
                  icon: Icons.check,
                  label: 'Unblock Slot',
                  color: c.success,
                  onTap: () async {
                    Navigator.pop(context);
                    // If slot is outside operational hours, mark as override
                    // so _syncOperatingHoursForNet won't re-block it
                    final isOpHours = _isWithinOperationalHours(slot);
                    await slotProvider.unblockSlot(
                      slot.slotId,
                      overrideMarker: isOpHours ? null : 'Opened by owner',
                    );
                    // Individual unblock does not affect period/day toggles — just reload slots
                    _loadSlots();
                  },
                ),
              ],
              
              if (slot.status == SlotStatus.booked) ...[
                _buildActionButton(
                  icon: Icons.info,
                  label: 'View Booking Details',
                  color: c.info,
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Show booking details
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
