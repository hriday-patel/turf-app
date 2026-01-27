import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../core/constants/enums.dart';
import '../../../data/models/turf_model.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../providers/booking_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Manual Booking Screen
/// Allows owner to create phone/walk-in bookings
class ManualBookingScreen extends StatefulWidget {
  final String turfId;
  const ManualBookingScreen({super.key, required this.turfId});

  @override
  State<ManualBookingScreen> createState() => _ManualBookingScreenState();
}

class _ManualBookingScreenState extends State<ManualBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  String? _selectedSlotId;
  double _selectedPrice = 0;
  String _selectedTimeRange = '';
  BookingSource _bookingSource = BookingSource.phone;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  void _loadSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    if (turf != null) {
      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      slotProvider.generateSlots(turf: turf, date: dateStr).then((_) {
        slotProvider.loadSlots(widget.turfId, dateStr);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate() || _selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a slot')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    final timeParts = _selectedTimeRange.split(' - ');
    final bookingId = await bookingProvider.createManualBooking(
      turfId: widget.turfId,
      slotId: _selectedSlotId!,
      bookingDate: _selectedDate.toIso8601String().split('T')[0],
      startTime: timeParts[0],
      endTime: timeParts[1],
      turfName: turf?.turfName ?? '',
      customerName: _nameController.text.trim(),
      customerPhone: _phoneController.text.trim(),
      bookingSource: _bookingSource,
      amount: _selectedPrice,
    );

    setState(() => _isLoading = false);

    if (bookingId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking created successfully!'), backgroundColor: AppColors.success),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manual Booking'),
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Picker
              _buildSectionTitle('Select Date'),
              _buildDatePicker(),
              const SizedBox(height: 24),
              
              // Slot Selection
              _buildSectionTitle('Select Time Slot'),
              _buildSlotGrid(),
              const SizedBox(height: 24),
              
              // Customer Info
              _buildSectionTitle('Customer Details'),
              _buildTextField(_nameController, 'Customer Name', Icons.person),
              const SizedBox(height: 12),
              _buildTextField(_phoneController, 'Phone Number', Icons.phone, isPhone: true),
              const SizedBox(height: 24),
              
              // Booking Source
              _buildSectionTitle('Booking Source'),
              _buildSourceSelector(),
              const SizedBox(height: 32),
              
              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('Confirm Booking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TableCalendar(
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _selectedDate,
        calendarFormat: CalendarFormat.week,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDate = selected;
            _selectedSlotId = null;
          });
          _loadSlots();
        },
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: AppColors.primary.withOpacity(0.3), shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildSlotGrid() {
    return Consumer<SlotProvider>(
      builder: (context, provider, _) {
        final available = provider.slots.where((s) => s.status == SlotStatus.available).toList();
        
        if (provider.isLoading) return const Center(child: CircularProgressIndicator());
        if (available.isEmpty) return const Text('No available slots for this date');

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: available.map((slot) {
            final isSelected = _selectedSlotId == slot.slotId;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedSlotId = slot.slotId;
                _selectedPrice = slot.price;
                _selectedTimeRange = '${slot.startTime} - ${slot.endTime}';
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
                ),
                child: Column(
                  children: [
                    Text(slot.displayTimeRange.split(' - ')[0], style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textPrimary)),
                    Text('₹${slot.price.toInt()}', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white70 : AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPhone = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.name,
      inputFormatters: isPhone ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))] : null,
      validator: (v) => v?.isEmpty == true ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildSourceSelector() {
    return Row(
      children: [
        _sourceChip(BookingSource.phone, Icons.phone, 'Phone'),
        const SizedBox(width: 12),
        _sourceChip(BookingSource.walkIn, Icons.directions_walk, 'Walk-In'),
      ],
    );
  }

  Widget _sourceChip(BookingSource source, IconData icon, String label) {
    final isSelected = _bookingSource == source;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _bookingSource = source),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.white : AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
