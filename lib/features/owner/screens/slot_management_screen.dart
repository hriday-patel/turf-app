import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../core/constants/enums.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSlots();
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
    _loadSlots();
  }

  void _loadSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    if (turf != null) {
      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      
      // First generate slots if they don't exist, then load
      slotProvider.generateSlots(turf: turf, date: dateStr).then((_) {
        slotProvider.loadSlots(widget.turfId, dateStr);
      });
    }
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() => _selectedDate = selectedDay);
    _loadSlots();
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
              
              // Slot Status Legend
              _buildLegend(),
              
              // Slots Grid
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
        ],
      ),
    );
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

        if (slotProvider.slots.isEmpty) {
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

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: slotProvider.slots.length,
          itemBuilder: (context, index) {
            final slot = slotProvider.slots[index];
            return _buildSlotCard(slot);
          },
        );
      },
    );
  }

  Widget _buildSlotCard(dynamic slot) {
    Color statusColor;
    IconData statusIcon;

    switch (slot.status) {
      case SlotStatus.available:
        statusColor = AppColors.slotAvailable;
        statusIcon = Icons.check_circle_outline;
        break;
      case SlotStatus.reserved:
        statusColor = AppColors.slotReserved;
        statusIcon = Icons.schedule;
        break;
      case SlotStatus.booked:
        statusColor = AppColors.slotBooked;
        statusIcon = Icons.event_available;
        break;
      case SlotStatus.blocked:
        statusColor = AppColors.slotBlocked;
        statusIcon = Icons.block;
        break;
      default:
        statusColor = AppColors.slotAvailable;
        statusIcon = Icons.check_circle_outline;
    }

    return GestureDetector(
      onTap: () => _showSlotActions(slot),
      child: Container(
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withOpacity(0.5)),
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
    );
  }

  void _showSlotActions(dynamic slot) {
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
