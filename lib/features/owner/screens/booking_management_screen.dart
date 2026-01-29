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
    _tabController = TabController(length: 3, vsync: this);
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
    
    if (turfProvider.turfIds.isNotEmpty && authProvider.currentUserId != null) {
      bookingProvider.loadOwnerBookings(authProvider.currentUserId!, turfProvider.turfIds);
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
    _loadBookings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bookings'),
        backgroundColor: AppColors.primary,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'All'), Tab(text: 'Today'), Tab(text: 'Pending')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList('all'),
          _buildList('today'),
          _buildList('pending'),
        ],
      ),
    );
  }

  Widget _buildList(String filter) {
    return Consumer<BookingProvider>(
      builder: (context, provider, _) {
        var bookings = provider.bookings;
        final today = DateTime.now().toIso8601String().split('T')[0];
        
        if (filter == 'today') {
          bookings = bookings.where((b) => b.bookingDate == today).toList();
        } else if (filter == 'pending') {
          bookings = bookings.where((b) => b.paymentStatus == PaymentStatus.payAtTurf).toList();
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(b.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                _statusBadge(b.paymentStatus),
              ],
            ),
            const SizedBox(height: 8),
            Text('${b.bookingDate} • ${b.displayTimeRange}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text('${b.turfName} • ₹${b.amount.toInt()}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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

  Widget _statusBadge(PaymentStatus status) {
    final color = status == PaymentStatus.paid ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(status.displayName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
