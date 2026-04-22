import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../providers/slot_provider.dart';
import '../providers/booking_provider.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../auth/utils/auth_form_utils.dart';

/// Manual Booking Screen
/// Allows owner to create phone/walk-in bookings
class ManualBookingScreen extends StatefulWidget {
  final String turfId;
  const ManualBookingScreen({super.key, required this.turfId});

  @override
  State<ManualBookingScreen> createState() => _ManualBookingScreenState();
}

class _ManualBookingScreenState extends State<ManualBookingScreen>
    with RouteAware {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _priceController = TextEditingController();
  final _advanceController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedSlotId;
  double _selectedPrice = 0;
  String _selectedTimeRange = '';
  int _selectedNetNumber = 1;
  BookingSource _bookingSource = BookingSource.phone;
  bool _isLoading = false;

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

  @override
  void initState() {
    super.initState();
    _selectedDate = _minSelectableDate;
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
    _nameController.dispose();
    _phoneController.dispose();
    _priceController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('ManualBooking: didPopNext - refreshing slots');
    _loadSlots();
  }

  void _loadSlots() {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    if (turf != null) {
      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      slotProvider.generateSlots(turf: turf, date: dateStr).then((_) async {
        await slotProvider.loadSlots(widget.turfId, dateStr);
      });
    }
  }

  Future<void> _submitBooking() async {
    // U4: Prevent double-submit. Synchronously block re-entry before validation/network.
    if (_isLoading) return;
    if (!_formKey.currentState!.validate() || _selectedSlotId == null) {
      showAppToast(context, 'Please fill all fields and select a slot',
          type: ToastType.warning);
      return;
    }

    setState(() => _isLoading = true);

    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);
    final turf = turfProvider.getTurfById(widget.turfId);

    if (turf == null) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      showAppToast(context, 'Turf not found. It may have been deleted.',
          type: ToastType.error);
      return;
    }

    final editedPrice =
        double.tryParse(_priceController.text) ?? _selectedPrice;
    final advanceAmount = double.tryParse(_advanceController.text) ?? 0;

    final timeParts = _selectedTimeRange.split(' - ');
    if (timeParts.length < 2) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      showAppToast(context, 'Invalid time slot selection. Please re-select.',
          type: ToastType.error);
      return;
    }
    final bookingId = await bookingProvider.createManualBooking(
      turfId: widget.turfId,
      slotId: _selectedSlotId!,
      bookingDate: _selectedDate.toIso8601String().split('T')[0],
      startTime: timeParts[0],
      endTime: timeParts[1],
      turfName: turf.turfName,
      customerName: _nameController.text.trim(),
      customerPhone: _phoneController.text.trim(),
      bookingSource: _bookingSource,
      amount: editedPrice,
      advanceAmount: advanceAmount,
      netNumber: _selectedNetNumber,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (bookingId != null) {
      showAppToast(context, 'Booking created successfully!',
          type: ToastType.success);

      // Send WhatsApp confirmation
      if (_phoneController.text.trim().isNotEmpty) {
        WhatsAppService.sendBookingConfirmation(
          customerPhone: _phoneController.text.trim(),
          bookingId: bookingId,
          turfName: turf.turfName,
          netNumber: _selectedNetNumber,
          date: _selectedDate.toIso8601String().split('T')[0],
          startTime: timeParts[0],
          endTime: timeParts[1],
          amount: editedPrice,
          advanceAmount: advanceAmount,
        );
      }

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassAppBar(title: 'Manual Booking'),
              Expanded(
                child: SingleChildScrollView(
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
                        _buildTextField(
                            _nameController, 'Customer Name', Icons.person),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _phoneController, 'Phone Number', Icons.phone,
                            isPhone: true),
                        const SizedBox(height: 24),

                        // Pricing
                        _buildSectionTitle('Payment Details'),
                        _buildPriceField(),
                        const SizedBox(height: 12),
                        _buildAdvanceField(),
                        if (_selectedSlotId != null) ...[
                          const SizedBox(height: 8),
                          _buildBalanceDisplay(),
                        ],
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
                              backgroundColor: c.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? CircularProgressIndicator(
                                    color: c.onPrimary, strokeWidth: 2)
                                : const Text('Confirm Booking',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: c.textPrimary)),
    );
  }

  Widget _buildDatePicker() {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
          color: c.glassFill, borderRadius: BorderRadius.circular(12)),
      child: TableCalendar(
        firstDay: _minSelectableDate,
        lastDay: _maxSelectableDate,
        focusedDay: _selectedDate,
        calendarFormat: CalendarFormat.week,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDate = _clampDateToBookingRange(selected);
            _selectedSlotId = null;
          });
          _loadSlots();
        },
        calendarStyle: CalendarStyle(
          selectedDecoration:
              BoxDecoration(color: c.primary, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.3), shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildSlotGrid() {
    final c = AppColors.of(context);
    return Consumer<SlotProvider>(
      builder: (context, provider, _) {
        final available = provider.slots
            .where((s) => s.status == SlotStatus.available)
            .toList();

        if (provider.isLoading)
          return const Center(child: CircularProgressIndicator());
        if (available.isEmpty)
          return const Text('No available slots for this date');

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: available.map((slot) {
            final isSelected = _selectedSlotId == slot.slotId;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedSlotId = slot.slotId;
                _selectedPrice = slot.price;
                _priceController.text = slot.price.toInt().toString();
                _selectedTimeRange = '${slot.startTime} - ${slot.endTime}';
                _selectedNetNumber = slot.netNumber;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? c.primary : c.glassFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? c.primary : c.divider),
                ),
                child: Column(
                  children: [
                    Text(slot.displayTimeRange.split(' - ')[0],
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? c.onPrimary : c.textPrimary)),
                    Text('₹${slot.price.toInt()}',
                        style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? c.onPrimary.withValues(alpha: 0.7)
                                : c.textSecondary)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {bool isPhone = false}) {
    final c = AppColors.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.name,
      // U7: For phone, accept digits only (10-digit Indian mobile). U8: name length cap.
      inputFormatters: isPhone
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10)
            ]
          : [LengthLimitingTextInputFormatter(60)],
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return 'Required';
        if (isPhone) {
          // U7: Require valid 10-digit Indian mobile
          if (!AuthFormUtils.isValidIndianPhoneInput(t)) {
            return 'Enter a valid 10-digit phone';
          }
        } else {
          // U8: Cap customer name at 60 chars (also enforced by inputFormatter)
          if (t.length > 60) return 'Max 60 characters';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: c.glassFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.glassBorder)),
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
    final c = AppColors.of(context);
    final isSelected = _bookingSource == source;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _bookingSource = source),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? c.primary : c.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? c.primary : c.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isSelected ? c.onPrimary : c.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? c.onPrimary : c.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    final c = AppColors.of(context);
    // U9: Clamp manual price to within ±50% of the slot's listed price.
    final double listed = _selectedPrice;
    final int? minAllowed = listed > 0 ? (listed * 0.5).round() : null;
    final int? maxAllowed = listed > 0 ? (listed * 1.5).round() : null;
    return TextFormField(
      controller: _priceController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        final parsed = int.tryParse(v);
        if (parsed == null || parsed <= 0) return 'Enter valid amount';
        if (minAllowed != null && maxAllowed != null) {
          if (parsed < minAllowed || parsed > maxAllowed) {
            return 'Allowed range ₹$minAllowed – ₹$maxAllowed';
          }
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Slot Price (₹)',
        helperText: listed > 0
            ? 'Listed ₹${listed.toInt()} · allowed ₹$minAllowed–₹$maxAllowed'
            : null,
        prefixIcon: const Icon(Icons.currency_rupee),
        filled: true,
        fillColor: c.glassFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.glassBorder)),
      ),
    );
  }

  Widget _buildAdvanceField() {
    final c = AppColors.of(context);
    return TextFormField(
      controller: _advanceController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Advance Amount (₹)',
        hintText: '0',
        prefixIcon: const Icon(Icons.account_balance_wallet),
        filled: true,
        fillColor: c.glassFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.glassBorder)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildBalanceDisplay() {
    final c = AppColors.of(context);
    final total = double.tryParse(_priceController.text) ?? _selectedPrice;
    final advance = double.tryParse(_advanceController.text) ?? 0;
    final balance = (total - advance).clamp(0, double.infinity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: balance > 0
            ? c.warning.withValues(alpha: 0.1)
            : c.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: balance > 0
                ? c.warning.withValues(alpha: 0.3)
                : c.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Balance Due',
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
          Text(
            '₹${balance.toInt()}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: balance > 0 ? c.warning : c.success,
            ),
          ),
        ],
      ),
    );
  }
}
