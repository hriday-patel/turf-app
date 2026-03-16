import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/routes.dart';
import '../../../config/colors.dart';
import '../../../core/constants/enums.dart';
import '../../../data/models/booking_model.dart';
import '../providers/turf_provider.dart';
import '../providers/booking_provider.dart';
import '../../auth/providers/auth_provider.dart';

class BookingManagementScreen extends StatefulWidget {
  const BookingManagementScreen({super.key});

  @override
  State<BookingManagementScreen> createState() =>
      _BookingManagementScreenState();
}

class _BookingManagementScreenState extends State<BookingManagementScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late TabController _tabController;
  String _lastBookingLoadKey = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBookings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRoutes.routeObserver.subscribe(this, route);
    }
    _ensureBookingsLoaded();
  }

  void _loadBookings() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    // Only load bookings for approved turfs
    final approvedTurfIds =
        turfProvider.approvedTurfs.map((t) => t.turfId).toList();
    if (approvedTurfIds.isNotEmpty && authProvider.currentUserId != null) {
      bookingProvider.loadOwnerBookings(
          authProvider.currentUserId!, approvedTurfIds);
    }
  }

  Future<void> _ensureBookingsLoaded() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    final ownerId = authProvider.currentUserId;
    if (ownerId == null || ownerId.isEmpty) return;

    if (turfProvider.turfs.isEmpty) {
      turfProvider.loadOwnerTurfs(ownerId);
      await turfProvider.refreshTurfs(ownerId);
      if (!mounted) return;
    }

    final approvedTurfIds =
        turfProvider.approvedTurfs.map((t) => t.turfId).toList();
    if (approvedTurfIds.isEmpty) return;

    final loadKey = '$ownerId:${approvedTurfIds.join(',')}';
    if (loadKey == _lastBookingLoadKey) return;
    _lastBookingLoadKey = loadKey;
    bookingProvider.loadOwnerBookings(ownerId, approvedTurfIds);
  }

  Future<void> _forceRefreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    // Force refresh turfs first to get latest verification status
    if (authProvider.currentUserId != null) {
      await turfProvider.refreshTurfs(authProvider.currentUserId!);

      if (!mounted) return;
      // Only load bookings for approved turfs
      final approvedTurfIds =
          turfProvider.approvedTurfs.map((t) => t.turfId).toList();
      if (approvedTurfIds.isNotEmpty) {
        bookingProvider.loadOwnerBookings(
            authProvider.currentUserId!, approvedTurfIds);
      }
    }
  }

  @override
  void dispose() {
    AppRoutes.routeObserver.unsubscribe(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('BookingManagement: didPopNext - refreshing data');
    _forceRefreshData();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const tabLabels = ['All', 'Paid', 'Pending', 'Cancelled'];
    final tabColors = [c.primary, c.success, c.warning, c.error];
    return Scaffold(
      backgroundColor: c.inputBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──
            Container(
              color: c.surface,
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios,
                            color: c.textPrimary, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text('Booking History',
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18)),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // ── Tabs ──
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      return Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: c.inputBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: List.generate(4, (i) {
                            final selected = _tabController.index == i;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _tabController.animateTo(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? c.surface
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.06),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1))
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      tabLabels[i],
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: selected
                                            ? tabColors[i]
                                            : c.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList('all'),
                  _buildList('paid'),
                  _buildList('pending'),
                  _buildList('cancelled'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(String filter) {
    return Consumer<BookingProvider>(
      builder: (context, provider, _) {
        final c = AppColors.of(context);
        var bookings = provider.bookings;

        if (filter == 'paid') {
          // Only bookings manually marked as paid by owner (exclude cancelled)
          bookings = bookings
              .where((b) =>
                  b.paymentStatus == PaymentStatus.paid &&
                  b.bookingStatus != BookingStatus.cancelled)
              .toList();
        } else if (filter == 'pending') {
          // All unpaid bookings: pay at turf OR pending (has advance but not confirmed) - exclude cancelled
          bookings = bookings
              .where((b) =>
                  (b.paymentStatus == PaymentStatus.payAtTurf ||
                      b.paymentStatus == PaymentStatus.pending) &&
                  b.bookingStatus != BookingStatus.cancelled)
              .toList();
        } else if (filter == 'cancelled') {
          // All cancelled bookings
          bookings = bookings
              .where((b) => b.bookingStatus == BookingStatus.cancelled)
              .toList();
        } else if (filter == 'all') {
          // All bookings (paid, pending, and cancelled)
        }

        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy,
                    size: 64, color: c.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('No bookings', style: TextStyle(color: c.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) => _AnimatedCardEntry(
            index: index,
            child: _buildCard(bookings[index]),
          ),
        );
      },
    );
  }

  Widget _buildCard(BookingModel b) {
    final c = AppColors.of(context);
    final hasAdvance = b.advanceAmount > 0;
    final isCancelled = b.bookingStatus == BookingStatus.cancelled;

    // Status edge colors
    final Color mainStrip;
    final Color layerStrip;
    if (isCancelled) {
      mainStrip = c.error;
      layerStrip = const Color(0xFFFCA5A5);
    } else if (b.paymentStatus == PaymentStatus.paid) {
      mainStrip = c.success;
      layerStrip = const Color(0xFF86EFAC);
    } else {
      mainStrip = c.warning;
      layerStrip = const Color(0xFFFCD34D);
    }

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.pushNamed(
          context,
          AppRoutes.bookingDetail,
          arguments: {'bookingId': b.bookingId},
        );
        // Refresh list if booking was cancelled
        if (result == true) {
          _loadBookings();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Layered left status edge
                Row(
                  children: [
                    Container(width: 3.5, color: mainStrip),
                    Container(width: 3.5, color: layerStrip),
                  ],
                ),
                // Card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(b.customerName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: c.textPrimary)),
                            ),
                            _statusBadge(b),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${b.bookingDate} • ${b.displayTimeRange}',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('${b.turfName} • ₹${b.amount.toInt()}',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 14)),
                        if (hasAdvance && !isCancelled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: b.paymentStatus == PaymentStatus.paid
                                      ? c.successLight
                                      : const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  b.paymentStatus == PaymentStatus.paid
                                      ? 'Paid: ₹${b.amount.toInt()}'
                                      : b.advanceAmount >= b.amount
                                          ? 'Advance (Full): ₹${b.advanceAmount.toInt()}'
                                          : 'Advance: ₹${b.advanceAmount.toInt()} | Due: ₹${(b.amount - b.advanceAmount).toInt()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: b.paymentStatus == PaymentStatus.paid
                                        ? const Color(0xFF166534)
                                        : const Color(0xFFC2410C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('Tap for details',
                                style: TextStyle(
                                    color: c.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios,
                                size: 12, color: c.primary),
                          ],
                        ),
                      ],
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

  Widget _statusBadge(BookingModel booking) {
    final c = AppColors.of(context);
    // If cancelled, show cancelled badge
    if (booking.bookingStatus == BookingStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: c.errorLight, borderRadius: BorderRadius.circular(20)),
        child: const Text('Cancelled',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B))),
      );
    }

    Color bgColor;
    Color textColor;
    String label;
    switch (booking.paymentStatus) {
      case PaymentStatus.paid:
        bgColor = c.successLight;
        textColor = const Color(0xFF166534);
        label = 'Paid';
        break;
      case PaymentStatus.pending:
        bgColor = c.warningLight;
        textColor = const Color(0xFF92400E);
        label = 'Pending Payment';
        break;
      case PaymentStatus.payAtTurf:
        bgColor = c.warningLight;
        textColor = const Color(0xFF92400E);
        label = 'Pay at Turf';
        break;
      default:
        bgColor = c.inputBackground;
        textColor = c.textSecondary;
        label = booking.paymentStatus.displayName;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
    );
  }
}

/// Staggered fade + slide entrance for list cards
class _AnimatedCardEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedCardEntry({required this.index, required this.child});
  @override
  State<_AnimatedCardEntry> createState() => _AnimatedCardEntryState();
}

class _AnimatedCardEntryState extends State<_AnimatedCardEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: 40 * widget.index.clamp(0, 8)), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
