import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../core/constants/enums.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/models/slot_model.dart';
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
  
  // Day closure toggles
  bool _isDayOpen = true;
  bool _isMorningOpen = true;
  bool _isAfternoonOpen = true;
  bool _isEveningOpen = true;
  bool _isNightOpen = true;

  @override
  void initState() {
    super.initState();
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

  /// Get slots filtered by the currently selected net number
  List<SlotModel> _getSlotsForSelectedNet(List<SlotModel> allSlots) {
    return allSlots.where((s) => s.netNumber == _selectedNetNumber).toList();
  }

  void _updateToggleStatesFromSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    
    if (slotProvider.slots.isEmpty) return;
    
    final netSlots = _getSlotsForSelectedNet(slotProvider.slots);
    if (netSlots.isEmpty) return;
    
    // Count period-closed slots (explicitly closed by owner toggle)
    // Auto-blocked "Closed" slots (outside operating hours) should NOT
    // affect toggle state — those are naturally closed by schedule.
    int morningPeriodClosed = 0;
    int afternoonPeriodClosed = 0;
    int eveningPeriodClosed = 0;
    int nightPeriodClosed = 0;
    
    for (final slot in netSlots) {
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      final isPeriodClosed = slot.status == SlotStatus.blocked &&
          (slot.blockReason ?? '').contains('Period closed');
      
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
      // Period toggle is OPEN unless owner explicitly period-closed slots in it.
      // Slots outside operating hours (block_reason="Closed") don't affect toggles.
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
      _selectedDate = selectedDay;
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
    return Consumer<TurfProvider>(
      builder: (context, turfProvider, _) {
        final turf = turfProvider.getTurfById(widget.turfId);

        if (turf == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Slot Management')),
            body: const Center(child: Text('Turf not found')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(turf.turfName),
            backgroundColor: AppColors.primary,
          ),
          body: Column(
            children: [
              // Calendar
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
        );
      },
    );
  }

  Widget _buildCalendar() {
    return Container(
      color: Colors.white,
      child: TableCalendar(
        firstDay: DateTime.now().subtract(const Duration(days: 7)),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _selectedDate,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
        onDaySelected: _onDaySelected,
        onFormatChanged: (format) {
          setState(() => _calendarFormat = format);
        },
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          weekendTextStyle: const TextStyle(color: AppColors.secondary),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
        ),
      ),
    );
  }

  Widget _buildNetSelector(int numberOfNets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.grid_view, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Text(
            'Net',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
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
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(AppColors.slotAvailable, 'Available'),
          _buildLegendItem(AppColors.slotReserved, 'Reserved'),
          _buildLegendItem(AppColors.slotBooked, 'Booked'),
          _buildLegendItem(AppColors.slotBlocked, 'Blocked'),
          _buildLegendItem(Colors.grey.shade400, 'Closed'),
        ],
      ),
    );
  }

  Widget _buildDayControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
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
                    color: _isDayOpen ? Colors.orange : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Day Status',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isDayOpen ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isDayOpen ? 'OPEN' : 'CLOSED',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDayOpen ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isDayOpen,
                    onChanged: (value) => _toggleDay(value),
                    activeColor: AppColors.success,
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
              const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Text(
                'Time Periods',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
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
    return GestureDetector(
      onTap: () => onChanged(!isOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isOpen ? AppColors.success.withOpacity(0.1) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOpen ? AppColors.success.withOpacity(0.3) : Colors.grey.shade300,
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
                      color: isOpen ? AppColors.textPrimary : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    timeRange,
                    style: TextStyle(
                      fontSize: 10,
                      color: isOpen ? AppColors.textSecondary : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                color: isOpen ? AppColors.success : Colors.grey.shade400,
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
                      decoration: const BoxDecoration(
                        color: Colors.white,
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
        await slotProvider.blockSlot(
          slot.slotId,
          authProvider.currentUserId!,
          'Period closed by owner',
        );
      } else if (!shouldBeBlocked && slot.status == SlotStatus.blocked) {
        // Only unblock period-closed slots, not auto-closed (operating hours) or manually blocked
        final reason = slot.blockReason ?? '';
        if (reason.contains('Period closed')) {
          await slotProvider.unblockSlot(slot.slotId);
        }
      }
    }
    
    // Reload to show updated status
    _loadSlots();
  }

  String _getSlotPeriod(SlotModel slot) {
    final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 18) return 'afternoon';
    if (hour >= 18 && hour < 24) return 'evening';
    return 'night';
  }

  bool _isPeriodClosed(String period) {
    switch (period) {
      case 'morning': return !_isMorningOpen;
      case 'afternoon': return !_isAfternoonOpen;
      case 'evening': return !_isEveningOpen;
      case 'night': return !_isNightOpen;
      default: return false;
    }
  }

  Widget _buildLegendItem(Color color, String label) {
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
            color: AppColors.textSecondary,
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_busy,
                  size: 64,
                  color: AppColors.textSecondary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No slots for this date',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period header
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeRange,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${slots.where((s) => s.status == SlotStatus.available).length}/${slots.length} open',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'No slots in this period',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    
    final period = _getSlotPeriod(slot);
    final isPeriodClosed = _isPeriodClosed(period);
    final isPast = _isSlotInPast(slot);

    // Check if slot is auto-blocked (outside operating hours)
    final isAutoBlocked = slot.status == SlotStatus.blocked &&
        (slot.blockReason == 'Closed' || (slot.blockReason ?? '').contains('Period closed'));

    // Past slots are always dimmed and non-interactive
    if (isPast) {
      statusColor = Colors.grey.shade400;
      statusIcon = Icons.history;
      statusLabel = 'Past';
    } else if (isPeriodClosed || isAutoBlocked) {
      statusColor = Colors.grey.shade400;
      statusIcon = Icons.block_outlined;
      statusLabel = 'Closed';
    } else {
      switch (slot.status) {
        case SlotStatus.available:
          statusColor = AppColors.slotAvailable;
          statusIcon = Icons.check_circle_outline;
          statusLabel = 'Available';
          break;
        case SlotStatus.reserved:
          statusColor = AppColors.slotReserved;
          statusIcon = Icons.schedule;
          statusLabel = 'Reserved';
          break;
        case SlotStatus.booked:
          statusColor = AppColors.slotBooked;
          statusIcon = Icons.event_available;
          statusLabel = 'Booked';
          break;
        case SlotStatus.blocked:
          statusColor = AppColors.slotBlocked;
          statusIcon = Icons.block;
          statusLabel = 'Blocked';
          break;
        default:
          statusColor = AppColors.slotAvailable;
          statusIcon = Icons.check_circle_outline;
          statusLabel = 'Available';
      }
    }

    final isInteractive = !isPast && !isPeriodClosed && !isAutoBlocked;

    return GestureDetector(
      onTap: isInteractive ? () => _showSlotActions(slot) : null,
      child: Opacity(
        opacity: isPast ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: statusColor.withOpacity(isInteractive ? 0.1 : 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(isInteractive ? 0.5 : 0.3)),
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
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (isPeriodClosed)
                Text(
                  'Closed',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Text(
                  '₹${slot.price.toInt()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
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
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                slot.displayTimeRange,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Status: ${slot.status.displayName}',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              
              if (slot.status == SlotStatus.available) ...[
                _buildActionButton(
                  icon: Icons.block,
                  label: 'Block Slot',
                  color: AppColors.warning,
                  onTap: () async {
                    Navigator.pop(context);
                    await slotProvider.blockSlot(
                      slot.slotId,
                      authProvider.currentUserId!,
                      'Manually blocked by owner',
                    );
                    _loadSlots();
                  },
                ),
              ],
              
              if (slot.status == SlotStatus.blocked) ...[
                _buildActionButton(
                  icon: Icons.check,
                  label: 'Unblock Slot',
                  color: AppColors.success,
                  onTap: () async {
                    Navigator.pop(context);
                    await slotProvider.unblockSlot(slot.slotId);
                    _loadSlots();
                  },
                ),
              ],
              
              if (slot.status == SlotStatus.booked) ...[
                _buildActionButton(
                  icon: Icons.info,
                  label: 'View Booking Details',
                  color: AppColors.info,
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
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
