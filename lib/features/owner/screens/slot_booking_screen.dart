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
  
  // Toggle states stored per turf+net+date combination
  // Key format: "turfId_netNumber_date"
  final Map<String, bool> _dayOpenStates = {};
  final Map<String, bool> _morningOpenStates = {};
  final Map<String, bool> _afternoonOpenStates = {};
  final Map<String, bool> _eveningOpenStates = {};
  final Map<String, bool> _nightOpenStates = {};
  
  // Track manually overridden slots (open even when period is closed)
  // Key format: "turfId_netNumber_slotId"
  final Set<String> _manuallyOpenedSlots = {};
  
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
      _isLoading = true;
      // Note: We don't reset toggles - each net has its own state
    });
    // Force reload slots when switching nets
    _loadSlots();
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isLoading = true;
      // Note: We don't reset toggles - each date has its own state per turf+net
    });
    _loadSlots();
  }

  void _toggleDay(bool isOpen) async {
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
  }

  void _togglePeriod(String period, bool isOpen) async {
    final key = _currentStateKey;
    setState(() {
      switch (period) {
        case 'morning':
          _morningOpenStates[key] = isOpen;
          break;
        case 'afternoon':
          _afternoonOpenStates[key] = isOpen;
          break;
        case 'evening':
          _eveningOpenStates[key] = isOpen;
          break;
        case 'night':
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
  }

  Future<void> _applyPeriodChanges() async {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Only apply changes to slots for the CURRENT net
    final currentNetSlots = slotProvider.slots.where((s) => s.netNumber == _selectedNetNumber).toList();
    
    for (final slot in currentNetSlots) {
      final hour = int.tryParse(slot.startTime.split(':')[0]) ?? 0;
      bool shouldBeBlocked = false;
      
      // Time period divisions:
      // Morning: 6 AM - 12 PM (6-11)
      // Afternoon: 12 PM - 6 PM (12-17)
      // Evening: 6 PM - 12 AM (18-23)
      // Night: 12 AM - 6 AM (0-5)
      if (hour >= 6 && hour < 12) {
        shouldBeBlocked = !_isMorningOpen;
      } else if (hour >= 12 && hour < 18) {
        shouldBeBlocked = !_isAfternoonOpen;
      } else if (hour >= 18 && hour < 24) {
        shouldBeBlocked = !_isEveningOpen;
      } else {
        // 0-5 hours (night)
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
    // Time period divisions:
    // Morning: 6 AM - 12 PM (hours 6-11)
    // Afternoon: 12 PM - 6 PM (hours 12-17)
    // Evening: 6 PM - 12 AM (hours 18-23)
    // Night: 12 AM - 6 AM (hours 0-5)
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

  // Inline toggle widget for period headers
  Widget _buildInlinePeriodToggle(String period, bool isOpen) {
    return GestureDetector(
      onTap: () => _togglePeriod(period.toLowerCase(), !isOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOpen ? AppColors.success.withOpacity(0.15) : AppColors.error.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOpen ? AppColors.success : AppColors.error,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOpen ? Icons.lock_open : Icons.lock,
              size: 12,
              color: isOpen ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              isOpen ? 'OPEN' : 'CLOSED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isOpen ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Day toggle widget for net header
  Widget _buildDayToggle() {
    return GestureDetector(
      onTap: () => _toggleDay(!_isDayOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isDayOpen ? AppColors.success.withOpacity(0.15) : AppColors.error.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isDayOpen ? AppColors.success : AppColors.error,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isDayOpen ? Icons.wb_sunny : Icons.nights_stay,
              size: 16,
              color: _isDayOpen ? Colors.orange : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              _isDayOpen ? 'DAY OPEN' : 'DAY CLOSED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _isDayOpen ? AppColors.success : AppColors.error,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 32,
              height: 18,
              decoration: BoxDecoration(
                color: _isDayOpen ? AppColors.success : Colors.grey.shade400,
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
        // Morning: 6 AM - 12 PM, Afternoon: 12 PM - 6 PM, Evening: 6 PM - 12 AM, Night: 12 AM - 6 AM
        final night = slots.where((s) => _getTimePeriod(s.startTime) == 'Night').toList();
        final morning = slots.where((s) => _getTimePeriod(s.startTime) == 'Morning').toList();
        final afternoon = slots.where((s) => _getTimePeriod(s.startTime) == 'Afternoon').toList();
        final evening = slots.where((s) => _getTimePeriod(s.startTime) == 'Evening').toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Net indicator with Day toggle - for multi-net turfs
              if (_selectedTurf != null && _selectedTurf!.numberOfNets > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sports_cricket, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Slots for Net $_selectedNetNumber',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      _buildDayToggle(),
                    ],
                  ),
                ),
              
              // For single net turfs, show just the day toggle
              if (_selectedTurf != null && _selectedTurf!.numberOfNets == 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Today\'s Slots',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      _buildDayToggle(),
                    ],
                  ),
                ),
              
              // Legend
              _buildLegend(),
              const SizedBox(height: 20),
              
              // Time Period Sections with inline toggles (displayed in chronological order)
              if (night.isNotEmpty) _buildTimePeriodSection('Night', '12 AM - 6 AM', night, Icons.bedtime, 'night', _isNightOpen),
              if (morning.isNotEmpty) _buildTimePeriodSection('Morning', '6 AM - 12 PM', morning, Icons.wb_sunny, 'morning', _isMorningOpen),
              if (afternoon.isNotEmpty) _buildTimePeriodSection('Afternoon', '12 PM - 6 PM', afternoon, Icons.wb_cloudy, 'afternoon', _isAfternoonOpen),
              if (evening.isNotEmpty) _buildTimePeriodSection('Evening', '6 PM - 12 AM', evening, Icons.nightlight_round, 'evening', _isEveningOpen),
            ],
          ),
        );
      },
    );
  }

  String _getTimePeriod(String startTime) {
    final hour = int.tryParse(startTime.split(':')[0]) ?? 0;
    // Time period divisions:
    // Morning: 6 AM - 12 PM (hours 6-11)
    // Afternoon: 12 PM - 6 PM (hours 12-17)
    // Evening: 6 PM - 12 AM (hours 18-23)
    // Night: 12 AM - 6 AM (hours 0-5)
    if (hour >= 6 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 18) return 'Afternoon';
    if (hour >= 18 && hour < 24) return 'Evening';
    return 'Night'; // 0-5 hours
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

  Widget _buildTimePeriodSection(String title, String timeRange, List<SlotModel> slots, IconData icon, String periodKey, bool isOpen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with inline toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isOpen ? Colors.white : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOpen ? AppColors.primary.withOpacity(0.2) : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: isOpen ? AppColors.primary : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isOpen ? AppColors.textPrimary : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeRange,
                    style: TextStyle(
                      fontSize: 12,
                      color: isOpen ? AppColors.textSecondary : Colors.grey,
                    ),
                  ),
                ],
              ),
              _buildInlinePeriodToggle(periodKey, isOpen),
            ],
          ),
        ),
        // Slots grid
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
    
    // Check if this slot is manually opened (overriding period closure)
    final isManuallyOpened = _isSlotManuallyOpened(slot.slotId);
    
    // Effective period closed status (can be overridden by manual open)
    final effectivelyClosed = isPeriodClosed && !isManuallyOpened;

    Color bgColor;
    Color textColor;
    String statusLabel;
    bool showManualOverrideOption = false;
    
    // If period is closed but slot is manually opened, show as available
    if (isPeriodClosed && isManuallyOpened && slot.status == SlotStatus.available && !isPast) {
      bgColor = AppColors.success.withOpacity(0.1);
      textColor = AppColors.success;
      statusLabel = 'Open';
      showManualOverrideOption = true;
    } else if (effectivelyClosed && slot.status == SlotStatus.available) {
      bgColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
      statusLabel = 'Closed';
      showManualOverrideOption = true; // Allow opening this slot manually
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

    // Determine if slot is tappable
    final isTappable = !isPast && (
      !effectivelyClosed || 
      showManualOverrideOption ||
      isBooked || 
      isReserved || 
      isBlocked
    );

    return GestureDetector(
      onTap: isTappable ? () => _showSlotActions(slot, isPeriodClosed: isPeriodClosed, isManuallyOpened: isManuallyOpened) : null,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isManuallyOpened && isPeriodClosed 
                ? AppColors.success 
                : textColor.withOpacity(0.3),
            width: isManuallyOpened && isPeriodClosed ? 2 : 1,
          ),
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
            if (effectivelyClosed)
              Icon(Icons.lock, size: 14, color: textColor)
            else if (isManuallyOpened && isPeriodClosed)
              Icon(Icons.lock_open, size: 14, color: AppColors.success)
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

  void _showSlotActions(SlotModel slot, {bool isPeriodClosed = false, bool isManuallyOpened = false}) {
    final isAvailable = slot.status == SlotStatus.available;
    final isBooked = slot.status == SlotStatus.booked;
    final isReserved = slot.status == SlotStatus.reserved; // Pending payment
    final isBlocked = slot.status == SlotStatus.blocked;
    
    // Determine if slot is effectively available (period open or manually opened)
    final effectivelyAvailable = isAvailable && (!isPeriodClosed || isManuallyOpened);
    final showManualOpenOption = isPeriodClosed && isAvailable && !isManuallyOpened;
    final showManualCloseOption = isPeriodClosed && isAvailable && isManuallyOpened;

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
                if (isPeriodClosed && isManuallyOpened) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_open, size: 12, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Manually Opened',
                          style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600),
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
                AppColors.success,
                () {
                  Navigator.pop(context);
                  _toggleSlotManualOverride(slot.slotId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Slot opened - You can now create a booking'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            
            // Show close option when slot is manually opened
            if (showManualCloseOption) ...[
              _buildActionButton(
                'Close This Slot Again',
                Icons.lock,
                Colors.grey,
                () {
                  Navigator.pop(context);
                  _toggleSlotManualOverride(slot.slotId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Slot closed again'),
                      backgroundColor: Colors.grey,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            
            if (effectivelyAvailable) ...[
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

  String _buildBookingConfirmationMessage(String customerName, String dateStr) {
    final netInfo = widget.turf.numberOfNets > 1 ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}' : '';
    final advanceInfo = _advanceAmount > 0 
        ? '\n💵 *Advance Paid:* ₹${_advanceAmount.toInt()}${_advanceAmount < _bookingAmount ? '\n💳 *Remaining:* ₹${(_bookingAmount - _advanceAmount).toInt()}' : ''}'
        : '';
    
    const appName = 'TurfBook';
    const appContact = '📞 For customer support, call +91 9773424512';
    
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

  Future<void> _sendWhatsAppMessage(String phone, String message) async {
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

/// Booking Success Popup - Complete Redesign
/// Features: Auto-send messages via Admin WhatsApp, Receipt generation, Share options
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

class _BookingSuccessPopupState extends State<_BookingSuccessPopup> with TickerProviderStateMixin {
  // Admin WhatsApp number for all messages
  static const String _adminWhatsAppNumber = '919773424512';
  
  late AnimationController _bounceController;
  late AnimationController _slideController;
  late Animation<double> _bounceAnimation;
  late Animation<Offset> _slideAnimation;
  
  bool _isSendingConfirmation = false;
  bool _confirmationSent = false;
  bool _isMarkingPayment = false;
  int _currentStep = 0; // 0: Initial, 1: Confirmation Sent, 2: Complete

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
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Header
                _buildSuccessHeader(),
                
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
    );
  }

  Widget _buildSuccessHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withBlue(200),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.sports_cricket,
                    color: AppColors.primary,
                    size: 36,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
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
            'Booking Successful!',
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
              color: Colors.white.withOpacity(0.2),
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
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.stadium, color: AppColors.primary, size: 24),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Net ${widget.selectedNetNumber}',
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
                _buildReceiptRow(Icons.person, 'Customer', widget.customerName),
                _buildReceiptRow(Icons.calendar_today, 'Date', widget.dateStr),
                _buildReceiptRow(Icons.schedule, 'Time', widget.slot.displayTimeRange),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(
              color: AppColors.textSecondary,
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
    return Column(
      children: [
        // Total Amount
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Amount',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            Text(
              '₹${widget.bookingAmount.toInt()}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: AppColors.primary,
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
                  ? AppColors.success.withOpacity(0.1) 
                  : Colors.orange.withOpacity(0.1),
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
                          _isFullPayment ? Icons.check_circle : Icons.hourglass_bottom,
                          size: 16,
                          color: _isFullPayment ? AppColors.success : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isFullPayment ? 'Paid' : 'Advance',
                          style: TextStyle(
                            color: _isFullPayment ? AppColors.success : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹${widget.advanceAmount.toInt()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isFullPayment ? AppColors.success : Colors.orange,
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
                        'Balance Due',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '₹${_remainingAmount.toInt()}',
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
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  'Payment at venue',
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
    return Column(
      children: [
        // Send Confirmation via Admin WhatsApp
        _buildMainActionButton(
          icon: _confirmationSent ? Icons.check_circle : Icons.send,
          label: _confirmationSent ? 'Confirmation Sent!' : 'Send Booking Confirmation',
          sublabel: _confirmationSent ? null : 'via TurfBook WhatsApp',
          color: _confirmationSent ? AppColors.success : const Color(0xFF25D366),
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
                  label: 'Send Receipt',
                  color: AppColors.primary,
                  onTap: _sendPaymentReceipt,
                ),
              ),
            
            if (_hasAdvance) const SizedBox(width: 10),
            
            // Copy Details
            Expanded(
              child: _buildSmallActionButton(
                icon: Icons.copy,
                label: 'Copy Details',
                color: Colors.grey.shade700,
                onTap: _copyBookingDetails,
              ),
            ),
            
            const SizedBox(width: 10),
            
            // Share
            Expanded(
              child: _buildSmallActionButton(
                icon: Icons.share,
                label: 'Share',
                color: Colors.blue.shade600,
                onTap: _shareBookingDetails,
              ),
            ),
          ],
        ),
        
        // Mark Payment Button (for full advance)
        if (_isFullPayment) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isMarkingPayment ? null : _markPaymentConfirmed,
              icon: _isMarkingPayment 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified, size: 18),
              label: Text(_isMarkingPayment ? 'Confirming...' : 'Mark Payment Confirmed'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoading ? 'Sending...' : label,
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
                        color: Colors.white.withOpacity(0.8),
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
      color: color.withOpacity(0.1),
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
    return TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      ),
      child: Text(
        'Done',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ========== Action Methods ==========

  /// Build booking confirmation message (without phone number)
  String _buildConfirmationMessage() {
    final netInfo = widget.turf.numberOfNets > 1 ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}' : '';
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

📞 For customer support, call +91 9773424512

— *TurfBook*''';
  }

  /// Build payment receipt message (without phone number)
  String _buildReceiptMessage() {
    final netInfo = widget.turf.numberOfNets > 1 ? '\n🥅 *Net:* Net ${widget.selectedNetNumber}' : '';
    
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

📞 For customer support, call +91 9773424512

— *TurfBook*''';
  }

  /// Send booking confirmation via Admin WhatsApp
  Future<void> _sendBookingConfirmation() async {
    setState(() => _isSendingConfirmation = true);
    
    try {
      final message = _buildConfirmationMessage();
      await _sendViaAdminWhatsApp(widget.customerPhone, message);
      
      if (mounted) {
        setState(() {
          _isSendingConfirmation = false;
          _confirmationSent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingConfirmation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Send payment receipt via Admin WhatsApp
  Future<void> _sendPaymentReceipt() async {
    final message = _buildReceiptMessage();
    await _sendViaAdminWhatsApp(widget.customerPhone, message);
  }

  /// Send message via Admin WhatsApp (opens WhatsApp with admin number)
  /// All messages are sent from admin phone: +91 9773424512
  Future<void> _sendViaAdminWhatsApp(String customerPhone, String message) async {
    // Clean customer phone number
    String cleanCustomerPhone = customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanCustomerPhone.startsWith('91') && cleanCustomerPhone.length == 10) {
      cleanCustomerPhone = '91$cleanCustomerPhone';
    }
    
    // Append customer number to message so admin knows where to forward
    final messageWithRecipient = '$message\n\n📱 *Send to:* +$cleanCustomerPhone';
    
    final encodedMessage = Uri.encodeComponent(messageWithRecipient);
    // Open WhatsApp with admin number - message will be sent FROM admin's phone
    final whatsappUrl = 'https://wa.me/$_adminWhatsAppNumber?text=$encodedMessage';
    
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

  /// Mark payment as confirmed
  Future<void> _markPaymentConfirmed() async {
    setState(() => _isMarkingPayment = true);
    
    try {
      final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
      await bookingProvider.markPaymentReceived(widget.bookingId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment marked as confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isMarkingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Copy booking details to clipboard
  void _copyBookingDetails() {
    final netInfo = widget.turf.numberOfNets > 1 ? ' (Net ${widget.selectedNetNumber})' : '';
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
    '''.trim();
    
    Clipboard.setData(ClipboardData(text: details));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booking details copied!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Share booking details
  Future<void> _shareBookingDetails() async {
    final netInfo = widget.turf.numberOfNets > 1 ? ' (Net ${widget.selectedNetNumber})' : '';
    final shareText = '''
🏏 Booking at ${widget.turf.turfName}$netInfo

📅 ${widget.dateStr}
⏰ ${widget.slot.displayTimeRange}
💰 ₹${widget.bookingAmount.toInt()}

#${widget.bookingId.substring(0, 8).toUpperCase()}
— TurfBook
    '''.trim();
    
    // Use clipboard as fallback for sharing
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booking details copied for sharing!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
