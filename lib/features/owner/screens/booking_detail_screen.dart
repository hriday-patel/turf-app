import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/services/database_service.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/booking_provider.dart';

/// Booking Detail Screen
/// Shows complete booking information with cancel and payment actions
class BookingDetailScreen extends StatefulWidget {
  final String bookingId;

  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> with RouteAware {
  final DatabaseService _dbService = DatabaseService();
  BookingModel? _booking;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBooking();
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
    debugPrint('BookingDetail: didPopNext - refreshing data');
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final data = await _dbService.getBooking(widget.bookingId);
      if (data != null) {
        setState(() {
          _booking = BookingModel.fromMap(data);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Booking not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load booking: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking? '
          'This action cannot be undone and the slot will become available again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true || _booking == null) return;

    setState(() => _isProcessing = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);

    final success = await bookingProvider.cancelBooking(
      _booking!.bookingId,
      _booking!.slotId,
      authProvider.currentUserId ?? 'owner',
      'Cancelled by owner',
    );

    setState(() => _isProcessing = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bookingProvider.errorMessage ?? 'Failed to cancel booking'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _markPaymentReceived() async {
    if (_booking == null) return;

    setState(() => _isProcessing = true);

    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final success = await bookingProvider.markPaymentReceived(_booking!.bookingId);

    if (success) {
      await _loadBooking();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment marked as received'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }

    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking Details'),
        backgroundColor: AppColors.primary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          ],
        ),
      );
    }

    if (_booking == null) {
      return const Center(child: Text('Booking not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Banner
          _buildStatusBanner(),
          const SizedBox(height: 20),

          // Customer Info
          _buildSection(
            title: 'Customer Information',
            icon: Icons.person_outline,
            children: [
              _buildInfoRow('Name', _booking!.customerName),
              _buildInfoRow('Phone', _booking!.customerPhone),
            ],
          ),
          const SizedBox(height: 16),

          // Booking Info
          _buildSection(
            title: 'Booking Details',
            icon: Icons.calendar_today_outlined,
            children: [
              _buildInfoRow('Turf', _booking!.turfName),
              if (_booking!.netNumber > 0)
                _buildInfoRow('Net', 'Net ${_booking!.netNumber}'),
              _buildInfoRow('Date', _booking!.bookingDate),
              _buildInfoRow('Time', _booking!.displayTimeRange),
              _buildInfoRow('Source', _booking!.bookingSource.displayName),
            ],
          ),
          const SizedBox(height: 16),

          // Payment Info
          _buildSection(
            title: 'Payment Information',
            icon: Icons.payment_outlined,
            children: [
              _buildInfoRow('Total Amount', '₹${_booking!.amount.toInt()}'),
              if (_booking!.advanceAmount > 0)
                _buildInfoRow('Advance Paid', '₹${_booking!.advanceAmount.toInt()}'),
              if (_booking!.isPartialPayment)
                _buildInfoRow('Remaining', '₹${_booking!.remainingAmount.toInt()}', valueColor: AppColors.warning),
              _buildInfoRow('Mode', _booking!.paymentMode.displayName),
              _buildInfoRow('Status', _booking!.paymentStatus.displayName),
              if (_booking!.transactionId != null)
                _buildInfoRow('Transaction ID', _booking!.transactionId!),
            ],
          ),
          const SizedBox(height: 24),

          // Action Buttons
          if (_booking!.isActive) ...[
            // Mark Payment Received (for pay at turf)
            if (_booking!.isPendingPayment)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _markPaymentReceived,
                  icon: const Icon(Icons.check_circle_outline),
                  label: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Mark Payment Received'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Cancel Booking
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _cancelBooking,
                icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
                label: const Text(
                  'Cancel Booking',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],

          // Cancellation Info (if cancelled)
          if (_booking!.bookingStatus == BookingStatus.cancelled) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Cancellation Details',
              icon: Icons.cancel_outlined,
              color: AppColors.error,
              children: [
                if (_booking!.cancelledBy != null)
                  _buildInfoRow('Cancelled By', _booking!.cancelledBy!),
                if (_booking!.cancellationReason != null)
                  _buildInfoRow('Reason', _booking!.cancellationReason!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isConfirmed = _booking!.bookingStatus == BookingStatus.confirmed;
    final color = isConfirmed ? AppColors.success : AppColors.error;
    final icon = isConfirmed ? Icons.check_circle : Icons.cancel;
    final text = _booking!.bookingStatus.displayName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking $text',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                'ID: ${_booking!.bookingId}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color ?? AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color ?? AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
