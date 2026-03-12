import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/services/database_service.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../providers/booking_provider.dart';
import '../../../config/colors.dart';

/// Booking Detail Screen
/// Shows complete booking information with cancel and payment actions
class BookingDetailScreen extends StatefulWidget {
  final String bookingId;

  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> with RouteAware, TickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  BookingModel? _booking;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceOpacity;
  late final Animation<Offset> _entranceSlide;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _entranceOpacity = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));
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
    _entranceCtrl.dispose();
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
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _booking = BookingModel.fromMap(data);
          _isLoading = false;
        });
        _entranceCtrl.forward();
      } else {
        setState(() {
          _errorMessage = 'Booking not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load booking: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking() async {
    final c = AppColors.of(context);
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
            style: TextButton.styleFrom(foregroundColor: c.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true || _booking == null) return;

    setState(() => _isProcessing = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);

    if (authProvider.currentUserId == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    final success = await bookingProvider.cancelBooking(
      _booking!.bookingId,
      _booking!.slotId,
      authProvider.currentUserId!,
      'Cancelled by owner',
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      showAppToast(context, 'Booking cancelled successfully', type: ToastType.success);
      Navigator.pop(context, true);
    } else {
      showAppToast(context, bookingProvider.errorMessage ?? 'Failed to cancel booking', type: ToastType.error);
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
        showAppToast(context, 'Payment marked as received', type: ToastType.success);
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.inputBackground,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Container(
              color: c.surface,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: c.textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Booking Details', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final c = AppColors.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: c.error),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: TextStyle(color: c.error), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_booking == null) {
      return const Center(child: Text('Booking not found'));
    }

    return FadeTransition(
      opacity: _entranceOpacity,
      child: SlideTransition(
        position: _entranceSlide,
        child: SingleChildScrollView(
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
                _buildInfoRow('Remaining', '₹${_booking!.remainingAmount.toInt()}', valueColor: c.warning),
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
              _SwipeToConfirm(
                onConfirm: _isProcessing ? null : _markPaymentReceived,
                isProcessing: _isProcessing,
                label: 'Mark Payment Received',
                icon: Icons.check_circle_outline,
                trackColor: c.successLight,
                borderColor: c.success,
                textColor: c.success,
                thumbColor: c.successLight,
              ),
            const SizedBox(height: 12),

            // Cancel Booking
            _SwipeToConfirm(
              onConfirm: _isProcessing ? null : _cancelBooking,
              isProcessing: _isProcessing,
              label: 'Cancel Booking',
              icon: Icons.cancel_outlined,
              trackColor: c.errorLight,
              borderColor: c.error,
              textColor: c.error,
              thumbColor: c.errorLight,
            ),
          ],

          // Cancellation Info (if cancelled)
          if (_booking!.bookingStatus == BookingStatus.cancelled) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Cancellation Details',
              icon: Icons.cancel_outlined,
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
      ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final c = AppColors.of(context);
    final isCancelled = _booking!.bookingStatus == BookingStatus.cancelled;
    final isConfirmed = _booking!.bookingStatus == BookingStatus.confirmed;
    final isPending = _booking!.isPendingPayment;

    Color bg, border, textColor;
    IconData icon;

    if (isCancelled) {
      bg = c.errorLight;
      border = c.error.withValues(alpha: 0.4);
      textColor = c.error;
      icon = Icons.cancel_rounded;
    } else if (isPending) {
      bg = c.warningLight;
      border = c.warning;
      textColor = c.warning;
      icon = Icons.schedule_rounded;
    } else {
      bg = c.successLight;
      border = c.success.withValues(alpha: 0.4);
      textColor = c.success;
      icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCancelled ? 'Booking Cancelled' : isPending ? 'Payment Pending' : 'Booking Confirmed',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${_booking!.bookingId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
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
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          Divider(height: 20, color: c.border),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: valueColor ?? c.textPrimary,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scale-on-press wrapper for action buttons
class _ScaleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _ScaleButton({required this.onTap, required this.child});
  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.98)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// Swipe-to-confirm pill slider control
class _SwipeToConfirm extends StatefulWidget {
  final VoidCallback? onConfirm;
  final bool isProcessing;
  final String label;
  final IconData icon;
  final Color trackColor;
  final Color borderColor;
  final Color textColor;
  final Color thumbColor;

  const _SwipeToConfirm({
    required this.onConfirm,
    required this.isProcessing,
    required this.label,
    required this.icon,
    required this.trackColor,
    required this.borderColor,
    required this.textColor,
    required this.thumbColor,
  });

  @override
  State<_SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<_SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragExtent = 0;
  bool _confirmed = false;
  late final AnimationController _resetCtrl;
  late Animation<double> _resetAnim;

  static const double _thumbSize = 48;
  static const double _trackHeight = 58;
  static const double _trackPadding = 5;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(covariant _SwipeToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset slider when processing finishes (action completed or dialog dismissed)
    if (oldWidget.isProcessing && !widget.isProcessing && _confirmed) {
      _animateReset();
    }
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    super.dispose();
  }

  void _animateReset() {
    final startVal = _dragExtent;
    if (startVal <= 0) {
      setState(() { _confirmed = false; _dragExtent = 0; });
      return;
    }
    _resetAnim = Tween<double>(begin: startVal, end: 0).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOut),
    );
    _resetCtrl.removeStatusListener(_onResetDone);
    _resetCtrl.addStatusListener(_onResetDone);
    _resetCtrl.forward(from: 0);
    _resetCtrl.addListener(_onResetTick);
  }

  void _onResetTick() {
    if (mounted) setState(() => _dragExtent = _resetAnim.value);
  }

  void _onResetDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      _resetCtrl.removeListener(_onResetTick);
      _resetCtrl.removeStatusListener(_onResetDone);
      setState(() { _confirmed = false; _dragExtent = 0; });
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (_confirmed || widget.isProcessing || widget.onConfirm == null) return;
    setState(() {
      _dragExtent = (_dragExtent + details.delta.dx).clamp(0.0, maxDrag);
    });
  }

  void _onDragEnd(double maxDrag) {
    if (_confirmed || widget.isProcessing) return;
    if (_dragExtent >= maxDrag * 0.85) {
      setState(() {
        _confirmed = true;
        _dragExtent = maxDrag;
      });
      widget.onConfirm?.call();
      // Schedule reset in case the action doesn't trigger isProcessing
      // (e.g. dialog dismissed without confirming)
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _confirmed && !widget.isProcessing) {
          _animateReset();
        }
      });
    } else {
      // Animate back to start
      _animateReset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _thumbSize - (_trackPadding * 2);
        final progress = maxDrag > 0 ? (_dragExtent / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          width: double.infinity,
          height: _trackHeight,
          decoration: BoxDecoration(
            color: widget.trackColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: widget.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Label text (fades as thumb slides)
              Center(
                child: Opacity(
                  opacity: widget.isProcessing ? 0.0 : (1.0 - progress * 1.5).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, color: widget.textColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Processing indicator
              if (widget.isProcessing)
                Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.textColor,
                    ),
                  ),
                ),
              // Draggable thumb
              if (!widget.isProcessing)
                Positioned(
                  left: _trackPadding + _dragExtent,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _onDragUpdate(d, maxDrag),
                    onHorizontalDragEnd: (_) => _onDragEnd(maxDrag),
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: widget.thumbColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: widget.borderColor.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: widget.textColor,
                        size: 26,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
