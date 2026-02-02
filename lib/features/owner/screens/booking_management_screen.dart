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
  State<BookingManagementScreen> createState() => _BookingManagementScreenState();
}

class _BookingManagementScreenState extends State<BookingManagementScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late TabController _tabController;

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
  }

  void _loadBookings() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    
    // Only load bookings for approved turfs
    final approvedTurfIds = turfProvider.approvedTurfs.map((t) => t.turfId).toList();
    if (approvedTurfIds.isNotEmpty && authProvider.currentUserId != null) {
      bookingProvider.loadOwnerBookings(authProvider.currentUserId!, approvedTurfIds);
    }
  }

  Future<void> _forceRefreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    
    // Force refresh turfs first to get latest verification status
    if (authProvider.currentUserId != null) {
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
      
      // Only load bookings for approved turfs
      final approvedTurfIds = turfProvider.approvedTurfs.map((t) => t.turfId).toList();
      if (approvedTurfIds.isNotEmpty) {
        bookingProvider.loadOwnerBookings(authProvider.currentUserId!, approvedTurfIds);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: AppColors.primary,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'All'), Tab(text: 'Paid'), Tab(text: 'Pending'), Tab(text: 'Cancelled')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList('all'),
          _buildList('paid'),
          _buildList('pending'),
          _buildList('cancelled'),
        ],
      ),
    );
  }

  Widget _buildList(String filter) {
    return Consumer<BookingProvider>(
      builder: (context, provider, _) {
        var bookings = provider.bookings;
        
        if (filter == 'paid') {
          // Only bookings manually marked as paid by owner (exclude cancelled)
          bookings = bookings.where((b) => 
            b.paymentStatus == PaymentStatus.paid && 
            b.bookingStatus != BookingStatus.cancelled
          ).toList();
        } else if (filter == 'pending') {
          // All unpaid bookings: pay at turf OR pending (has advance but not confirmed) - exclude cancelled
          bookings = bookings.where((b) => 
            (b.paymentStatus == PaymentStatus.payAtTurf || 
            b.paymentStatus == PaymentStatus.pending) &&
            b.bookingStatus != BookingStatus.cancelled
          ).toList();
        } else if (filter == 'cancelled') {
          // All cancelled bookings
          bookings = bookings.where((b) => b.bookingStatus == BookingStatus.cancelled).toList();
        } else if (filter == 'all') {
          // All non-cancelled bookings
          bookings = bookings.where((b) => b.bookingStatus != BookingStatus.cancelled).toList();
        }

        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('No bookings', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) => _buildCard(bookings[index]),
        );
      },
    );
  }

  Widget _buildCard(BookingModel b) {
    final hasAdvance = b.advanceAmount > 0;
    final isCancelled = b.bookingStatus == BookingStatus.cancelled;
    
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCancelled ? Colors.red.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isCancelled ? Border.all(color: Colors.red.withOpacity(0.2)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(b.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                _statusBadge(b),
              ],
            ),
            const SizedBox(height: 8),
            Text('${b.bookingDate} • ${b.displayTimeRange}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: Text('${b.turfName} • ₹${b.amount.toInt()}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
              ],
            ),
            if (hasAdvance && !isCancelled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      // All advance payments shown in orange until manually marked as paid
                      color: b.paymentStatus == PaymentStatus.paid 
                          ? AppColors.success.withOpacity(0.1) 
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
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
                            ? AppColors.success 
                            : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Tap for details', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(BookingModel booking) {
    // If cancelled, show cancelled badge
    if (booking.bookingStatus == BookingStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
        child: const Text('Cancelled', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
      );
    }
    
    Color color;
    String label;
    switch (booking.paymentStatus) {
      case PaymentStatus.paid:
        color = AppColors.success;
        label = 'Paid';
        break;
      case PaymentStatus.pending:
        // Pending means has advance but not confirmed - show as Pending Payment
        color = Colors.orange;
        label = 'Pending Payment';
        break;
      case PaymentStatus.payAtTurf:
        color = AppColors.warning;
        label = 'Pay at Turf';
        break;
      default:
        color = AppColors.textSecondary;
        label = booking.paymentStatus.displayName;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
