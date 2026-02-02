import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/colors.dart';
import '../../../core/constants/enums.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../providers/booking_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Comprehensive Slot Booking Screen
/// Allows owner to view all slots and create manual bookings
class SlotBookingScreen extends StatefulWidget {
  const SlotBookingScreen({super.key});

  @override
  State<SlotBookingScreen> createState() => _SlotBookingScreenState();
}

class _SlotBookingScreenState extends State<SlotBookingScreen> with RouteAware {
  TurfModel? _selectedTurf;
  int _selectedNetNumber = 1;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  
  // Day closure toggles
  bool _isDayOpen = true;
  bool _isMorningOpen = true;
  bool _isAfternoonOpen = true;
  bool _isEveningOpen = true;
  bool _isNightOpen = true;

  @override
  void initState() {
    super.initState();
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
    AppRoutes.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('SlotBooking: didPopNext - refreshing slots');
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    
    // Force refresh turfs first to get latest verification status
    if (authProvider.currentUserId != null) {
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
    }
    
    // Re-initialize with only approved turfs
    _initializeData();
  }

  void _initializeData() {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final approvedTurfs = turfProvider.turfs.where((t) => t.verificationStatus == VerificationStatus.approved).toList();
    
    // Check if currently selected turf is still approved
    if (_selectedTurf != null) {
      final stillApproved = approvedTurfs.any((t) => t.turfId == _selectedTurf!.turfId);
      if (!stillApproved) {
        // Current turf is no longer approved, clear selection
        setState(() {
          _selectedTurf = null;
          _selectedNetNumber = 1;
        });
      }
    }
    
    // If no turf selected but we have approved turfs, select first one
    if (_selectedTurf == null && approvedTurfs.isNotEmpty) {
      setState(() {
        _selectedTurf = approvedTurfs.first;
        _selectedNetNumber = 1;
      });
    }
    
    if (_selectedTurf != null) {
      _loadSlots();
    }
  }

  void _loadSlots() {
    if (_selectedTurf == null) return;
    
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final dateStr = _selectedDate.toIso8601String().split('T')[0];
    
    slotProvider.generateSlots(turf: _selectedTurf!, date: dateStr).then((_) {
      slotProvider.loadSlots(_selectedTurf!.turfId, dateStr);
    });
  }

  void _onTurfSelected(TurfModel turf) {
    // Verify turf is still approved before selecting
    if (turf.verificationStatus != VerificationStatus.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This turf is no longer approved'), backgroundColor: Colors.orange),
      );
      _refreshAllData();
      return;
    }
    
    setState(() {
      _selectedTurf = turf;
      _selectedNetNumber = 1;
      _isLoading = true;
    });
    _loadSlots();
  }

  void _onNetSelected(int netNumber) {
    setState(() {
      _selectedNetNumber = netNumber;
    });
    // No need to reload slots, just filter the existing ones
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isLoading = true;
      // Reset toggles when changing date
      _isDayOpen = true;
      _isMorningOpen = true;
      _isAfternoonOpen = true;
      _isEveningOpen = true;
      _isNightOpen = true;
    });
    _loadSlots();
  }

  void _toggleDay(bool isOpen) async {
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
      if (!_isMorningOpen && !_isAfternoonOpen && !_isEveningOpen && !_isNightOpen) {
        _isDayOpen = false;
      } else if (!_isDayOpen) {
        _isDayOpen = true;
      }
    });
    await _applyPeriodChanges();
  }

  Future<void> _applyPeriodChanges() async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    for (final slot in slotProvider.slots) {
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      bool shouldBeBlocked = false;
      
      if (hour >= 6 && hour < 12) {
        shouldBeBlocked = !_isMorningOpen;
      } else if (hour >= 12 && hour < 18) {
        shouldBeBlocked = !_isAfternoonOpen;
      } else if (hour >= 18 && hour < 24) {
        shouldBeBlocked = !_isEveningOpen;
      } else {
        shouldBeBlocked = !_isNightOpen;
      }
      
      if (shouldBeBlocked && slot.status == SlotStatus.available) {
        await slotProvider.blockSlot(
          slot.slotId,
          authProvider.currentUserId!,
          'Period closed by owner',
        );
      } else if (!shouldBeBlocked && slot.status == SlotStatus.blocked) {
        await slotProvider.unblockSlot(slot.slotId);
      }
    }
    
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

  @override
  Widget build(BuildContext context) {
    final turfProvider = Provider.of<TurfProvider>(context);
    final approvedTurfs = turfProvider.turfs.where((t) => t.verificationStatus == VerificationStatus.approved).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking'),
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: approvedTurfs.isEmpty
          ? _buildEmptyState()
          : Row(
              children: [
                // Left Sidebar - Turf & Net Selector
                _buildSidebar(approvedTurfs),
                
                // Main Content
                Expanded(
                  child: Column(
                    children: [
                      // Date Picker
                      _buildDatePicker(),
                      
                      // Day Controls (On/Off toggles)
                      _buildDayControls(),
                      
                      // Slots Grid
                      Expanded(
                        child: _buildSlotsContent(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.stadium_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'No Approved Turfs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a turf and get it approved to manage slots',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.addTurf),
            icon: const Icon(Icons.add),
            label: const Text('Add Turf'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<TurfModel> turfs) {
    return Container(
      width: 200,
      color: Colors.white,
      child: Column(
        children: [
          // Turf Selector Header
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primary.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.stadium, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Select Venue',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.15) : null,
                      border: Border(
                        left: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.transparent,
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
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
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
                            color: AppColors.textSecondary,
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
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Net',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      _selectedTurf!.numberOfNets,
                      (index) {
                        final netNumber = index + 1;
                        final isSelected = _selectedNetNumber == netNumber;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedNetNumber = netNumber),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                            ),
                            child: Text(
                              'Net $netNumber',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
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
    );
  }

  Widget _buildDatePicker() {
    return Container(
      color: Colors.white,
      child: TableCalendar(
        firstDay: DateTime.now().subtract(const Duration(days: 1)),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _selectedDate,
        calendarFormat: CalendarFormat.week,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
        onDaySelected: (selected, focused) => _onDateSelected(selected),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          headerPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
        ),
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

  Widget _buildSlotsContent() {
    return Consumer<SlotProvider>(
      builder: (context, slotProvider, _) {
        if (slotProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        var slots = slotProvider.slots;
        if (slots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 16),
                const Text('No slots available for this date'),
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
                Icon(Icons.event_busy, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('No slots for Net $_selectedNetNumber'),
              ],
            ),
          );
        }

        // Group slots by time period
        final lateNight = slots.where((s) => _getTimePeriod(s.startTime) == 'Late Night').toList();
        final morning = slots.where((s) => _getTimePeriod(s.startTime) == 'Morning').toList();
        final afternoon = slots.where((s) => _getTimePeriod(s.startTime) == 'Afternoon').toList();
        final night = slots.where((s) => _getTimePeriod(s.startTime) == 'Night').toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Net indicator for multi-net turfs
              if (_selectedTurf != null && _selectedTurf!.numberOfNets > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_cricket, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Slots for Net $_selectedNetNumber',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Legend
              _buildLegend(),
              const SizedBox(height: 20),
              
              // Time Period Sections
              if (lateNight.isNotEmpty) _buildTimePeriodSection('Late Night', '12 AM - 6 AM', lateNight, Icons.bedtime),
              if (morning.isNotEmpty) _buildTimePeriodSection('Morning', '6 AM - 12 PM', morning, Icons.wb_sunny),
              if (afternoon.isNotEmpty) _buildTimePeriodSection('Afternoon', '12 PM - 6 PM', afternoon, Icons.wb_cloudy),
              if (night.isNotEmpty) _buildTimePeriodSection('Night', '6 PM - 12 AM', night, Icons.nightlight_round),
            ],
          ),
        );
      },
    );
  }

  String _getTimePeriod(String startTime) {
    final hour = int.tryParse(startTime.split(':')[0]) ?? 0;
    if (hour >= 0 && hour < 6) return 'Late Night';
    if (hour >= 6 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 18) return 'Afternoon';
    return 'Night';
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem('Available', AppColors.success),
          _buildLegendItem('Pending Payment', Colors.orange),
          _buildLegendItem('Booked', AppColors.error),
          _buildLegendItem('Blocked', Colors.grey),
          _buildLegendItem('Closed', Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
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
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildTimePeriodSection(String title, String timeRange, List<SlotModel> slots, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(timeRange, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: slots.map((slot) => _buildSlotCard(slot)).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSlotCard(SlotModel slot) {
    final isPast = _isSlotPast(slot);
    final isAvailable = slot.status == SlotStatus.available && !isPast;
    final isBooked = slot.status == SlotStatus.booked;
    final isReserved = slot.status == SlotStatus.reserved; // Pending payment
    final isBlocked = slot.status == SlotStatus.blocked;
    
    // Check if slot's period is closed
    final period = _getSlotPeriod(slot);
    final isPeriodClosed = _isPeriodClosed(period);

    Color bgColor;
    Color textColor;
    String statusLabel;
    
    // If period is closed, show slot as grey/closed (visual feedback)
    if (isPeriodClosed) {
      bgColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
      statusLabel = 'Closed';
    } else if (isPast) {
      bgColor = Colors.grey.shade200;
      textColor = Colors.grey;
      statusLabel = 'Past';
    } else if (isBooked) {
      bgColor = AppColors.error.withOpacity(0.1);
      textColor = AppColors.error;
      statusLabel = 'Booked';
    } else if (isReserved) {
      bgColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orange;
      statusLabel = 'Pending Payment';
    } else if (isBlocked) {
      bgColor = Colors.grey.shade300;
      textColor = Colors.grey.shade700;
      statusLabel = 'Blocked';
    } else {
      bgColor = AppColors.success.withOpacity(0.1);
      textColor = AppColors.success;
      statusLabel = 'Available';
    }

    return GestureDetector(
      onTap: (isPast || isPeriodClosed) ? null : () => _showSlotActions(slot),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: textColor.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              slot.displayTimeRange.split(' - ')[0],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            if (isPeriodClosed)
              Icon(Icons.block, size: 14, color: textColor)
            else
              Text(
                '₹${slot.price.toInt()}',
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withOpacity(0.8),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 9,
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
      final slotTime = DateTime(now.year, now.month, now.day, slotHour, slotMinute);
      return now.isAfter(slotTime);
    }
    
    return false;
  }

  void _showSlotActions(SlotModel slot) {
    final isAvailable = slot.status == SlotStatus.available;
    final isBooked = slot.status == SlotStatus.booked;
    final isReserved = slot.status == SlotStatus.reserved; // Pending payment
    final isBlocked = slot.status == SlotStatus.blocked;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  '₹${slot.price.toInt()}',
                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                ),
                if (isReserved) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Pending Payment',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            
            if (isAvailable) ...[
              _buildActionButton(
                'Create Booking',
                Icons.add_circle,
                AppColors.primary,
                () {
                  Navigator.pop(context);
                  _showBookingDialog(slot);
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'Block Slot',
                Icons.block,
                Colors.grey,
                () {
                  Navigator.pop(context);
                  _blockSlot(slot);
                },
              ),
            ],
            
            if (isBlocked)
              _buildActionButton(
                'Unblock Slot',
                Icons.check_circle,
                AppColors.success,
                () {
                  Navigator.pop(context);
                  _unblockSlot(slot);
                },
              ),
            
            if (isBooked || isReserved)
              _buildActionButton(
                'View Booking Details',
                Icons.visibility,
                AppColors.primary,
                () async {
                  Navigator.pop(context);
                  await _viewBookingDetails(slot);
                },
              ),
            
            if (isReserved) ...[
              const SizedBox(height: 12),
              _buildActionButton(
                'Mark Payment Received',
                Icons.check_circle,
                AppColors.success,
                () async {
                  Navigator.pop(context);
                  await _markPaymentAndUpdateSlot(slot);
                },
              ),
            ],
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _viewBookingDetails(SlotModel slot) async {
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final booking = await bookingProvider.getBookingBySlotId(slot.slotId);
    
    if (booking != null && mounted) {
      Navigator.pushNamed(
        context,
        AppRoutes.bookingDetail,
        arguments: {'bookingId': booking.bookingId},
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking details not found')),
      );
    }
  }

  Future<void> _markPaymentAndUpdateSlot(SlotModel slot) async {
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    
    final booking = await bookingProvider.getBookingBySlotId(slot.slotId);
    if (booking != null) {
      await bookingProvider.markPaymentReceived(booking.bookingId);
      await slotProvider.markSlotAsBooked(slot.slotId);
      _loadSlots();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment marked as received'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final ownerId = authProvider.currentUserId ?? '';
    await slotProvider.blockSlot(slot.slotId, ownerId, 'Blocked by owner');
    _loadSlots();
  }

  Future<void> _unblockSlot(SlotModel slot) async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    await slotProvider.unblockSlot(slot.slotId);
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

  PaymentStatus get _paymentStatus {
    // All bookings start as pending until owner manually marks as paid
    // Even if full advance is entered, it's still pending confirmation
    if (_advanceAmount > 0) return PaymentStatus.pending; // Has advance - pending confirmation
    return PaymentStatus.payAtTurf; // No advance - pay at turf
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.selectedDate.day}/${widget.selectedDate.month}/${widget.selectedDate.year}';
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Create Booking',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Slot Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.stadium, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.turf.turfName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(dateStr, style: TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(widget.slot.displayTimeRange, style: TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Booking Amount', style: TextStyle(fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  controller: _bookingAmountController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                  decoration: InputDecoration(
                                    prefixText: '₹',
                                    prefixStyle: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  validator: (v) {
                                    if (v?.isEmpty == true) return 'Required';
                                    final amount = double.tryParse(v!) ?? 0;
                                    if (amount <= 0) return 'Invalid';
                                    return null;
                                  },
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              if (_isPeakRate()) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Peak',
                                    style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Customer Details
                const Text('Customer Details', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (v) => v?.isEmpty == true ? 'Please enter name' : null,
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
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (v) {
                    if (v?.isEmpty == true) return 'Please enter phone number';
                    if (v!.length != 10) return 'Phone number must be 10 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Advance Amount (Required - enter 0 if no advance)
                Row(
                  children: [
                    const Text('Advance Amount', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Text(
                      '(Enter 0 if no advance)',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _advanceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Advance Amount',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    hintText: '0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (v) {
                    if (v?.isEmpty == true) return 'Please enter advance amount (0 if none)';
                    final advance = double.tryParse(v!) ?? 0;
                    if (advance < 0) return 'Cannot be negative';
                    if (advance > _bookingAmount) return 'Cannot exceed booking amount';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                
                // Payment Status Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _advanceAmount > 0 ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info,
                        size: 16,
                        color: _advanceAmount > 0 ? Colors.orange : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _advanceAmount >= _bookingAmount
                              ? 'Full payment: ₹${_advanceAmount.toInt()} (pending confirmation)'
                              : _advanceAmount > 0
                                  ? 'Advance: ₹${_advanceAmount.toInt()} | Remaining: ₹${(_bookingAmount - _advanceAmount).toInt()}'
                                  : 'Payment: ₹${_bookingAmount.toInt()} (Pay at Turf)',
                          style: TextStyle(
                            color: _advanceAmount > 0 ? Colors.orange : Colors.blue,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Booking Source
                const Text('Booking Source', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(child: _buildSourceChip(BookingSource.phone, Icons.phone, 'Phone')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSourceChip(BookingSource.walkIn, Icons.directions_walk, 'Walk-In')),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Create Booking Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Create Booking',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPeakRate() {
    final hour = int.tryParse(widget.slot.startTime.split(':')[0]) ?? 0;
    return hour >= 18 || hour < 6; // Evening and night are peak
  }

  Widget _buildSourceChip(BookingSource source, IconData icon, String label) {
    final isSelected = _bookingSource == source;
    return GestureDetector(
      onTap: () => setState(() => _bookingSource = source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : AppColors.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBooking() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final timeParts = widget.slot.displayTimeRange.split(' - ');
    
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
      amount: _bookingAmount,  // Use editable booking amount
      advanceAmount: _advanceAmount,
      netNumber: widget.selectedNetNumber,
    );

    setState(() => _isLoading = false);

    if (bookingId != null && mounted) {
      Navigator.pop(context);
      widget.onBookingCreated();
      
      // Show payment confirmation dialog with owner info
      final owner = authProvider.currentOwner;
      _showPaymentConfirmation(bookingId, owner);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create booking'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPaymentConfirmation(String bookingId, dynamic owner) {
    final dateStr = '${widget.selectedDate.day}/${widget.selectedDate.month}/${widget.selectedDate.year}';
    final customerName = _nameController.text.trim();
    final customerPhone = _phoneController.text.trim();
    final ownerName = owner?.name ?? 'Owner';
    final ownerPhone = owner?.phone ?? '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Booking Created!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.turf.turfName}${widget.turf.numberOfNets > 1 ? ' - Net ${widget.selectedNetNumber}' : ''}\n$dateStr | ${widget.slot.displayTimeRange}',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              if (_advanceAmount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _advanceAmount >= widget.slot.price 
                        ? AppColors.success.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _advanceAmount >= widget.slot.price 
                        ? 'Full Advance: ₹${_advanceAmount.toInt()} (Pending Confirmation)'
                        : 'Advance: ₹${_advanceAmount.toInt()} | Remaining: ₹${(widget.slot.price - _advanceAmount).toInt()}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              // WhatsApp Booking Confirmation
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _sendWhatsAppMessage(
                    customerPhone,
                    _buildBookingConfirmationMessage(customerName, dateStr),
                  ),
                  icon: const Icon(Icons.message, color: Colors.white),
                  label: const Text('Send Booking Confirmation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366), // WhatsApp green
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Payment Status Section - show info for advance payments
              // NOTE: Don't ask for payment confirmation immediately - that happens later when customer arrives
              if (_advanceAmount > 0 && _advanceAmount < _bookingAmount)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Payment Info',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Advance Received:', style: TextStyle(fontSize: 13)),
                          Text('₹${_advanceAmount.toInt()}', 
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Remaining (at arrival):', style: TextStyle(fontSize: 13)),
                          Text('₹${(_bookingAmount - _advanceAmount).toInt()}', 
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Collect remaining amount when customer arrives. Mark as paid from booking history.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              
              // For full payment, show confirmation option
              if (_advanceAmount >= _bookingAmount)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Full Payment Received',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Amount: ₹${_bookingAmount.toInt()}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
                            await bookingProvider.markPaymentReceived(bookingId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              // Send payment confirmation via WhatsApp
                              _sendWhatsAppMessage(
                                customerPhone,
                                _buildPaymentConfirmationMessage(customerName, dateStr),
                              );
                            }
                          },
                          icon: const Icon(Icons.verified, color: Colors.white, size: 18),
                          label: const Text('Confirm & Send Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildBookingConfirmationMessage(String customerName, String dateStr) {
    final netInfo = widget.turf.numberOfNets > 1 ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}' : '';
    final advanceInfo = _advanceAmount > 0 
        ? '\n💵 *Advance Paid:* ₹${_advanceAmount.toInt()}${_advanceAmount < _bookingAmount ? '\n💳 *Remaining:* ₹${(_bookingAmount - _advanceAmount).toInt()}' : ''}'
        : '';
    
    // Use app branding instead of owner's contact
    const appName = 'TurfBook';
    const appContact = 'For any queries, contact us through the app.';
    
    return '''🎉 *Booking Confirmed!*

Hi $customerName,

Your booking has been confirmed:

📍 *Venue:* ${widget.turf.turfName}$netInfo
📅 *Date:* $dateStr
⏰ *Time:* ${widget.slot.displayTimeRange}
💰 *Total Amount:* ₹${_bookingAmount.toInt()}$advanceInfo

Please arrive 10 minutes before your slot time.

$appContact

Thank you for choosing $appName! 🏏''';
  }

  String _buildPaymentConfirmationMessage(String customerName, String dateStr) {
    final netInfo = widget.turf.numberOfNets > 1 ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}' : '';
    
    // Use app branding instead of owner's contact
    const appName = 'TurfBook';
    
    return '''✅ *Payment Received!*

Hi $customerName,

We have received your full payment of ₹${_bookingAmount.toInt()} for:

📍 *Venue:* ${widget.turf.turfName}$netInfo
📅 *Date:* $dateStr
⏰ *Time:* ${widget.slot.displayTimeRange}

See you at the turf! 🏏

Thank you for choosing $appName!''';
  }

  Future<void> _sendWhatsAppMessage(String phone, String message) async {
    // Clean phone number
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanPhone.startsWith('91') && cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }
    
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = 'https://wa.me/$cleanPhone?text=$encodedMessage';
    
    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open WhatsApp')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
