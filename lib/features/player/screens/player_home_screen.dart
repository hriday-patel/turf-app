import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../config/abstract_bg.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/database_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../owner/providers/booking_provider.dart';

class PlayerHomeScreen extends StatefulWidget {
  const PlayerHomeScreen({super.key});

  @override
  State<PlayerHomeScreen> createState() => _PlayerHomeScreenState();
}

class _PlayerHomeScreenState extends State<PlayerHomeScreen> {
  final DatabaseService _dbService = DatabaseService();

  DateTime _selectedDate = DateTime.now();
  int _selectedTab = 0;
  bool _loadingTurfs = false;
  bool _loadingBookings = false;

  List<TurfModel> _approvedTurfs = [];
  List<BookingModel> _bookings = [];

  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadApprovedTurfs(),
      _loadMyBookings(),
    ]);
  }

  Future<void> _loadApprovedTurfs() async {
    setState(() {
      _loadingTurfs = true;
      _error = null;
    });

    try {
      final rows = await _dbService.getApprovedTurfs();
      final turfs = rows.map((row) => TurfModel.fromMap(row)).toList();

      if (!mounted) return;
      setState(() {
        _approvedTurfs = turfs
            .where((t) => t.status != TurfStatus.renovation)
            .toList(growable: false);
        _loadingTurfs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTurfs = false;
        _error = 'Failed to load turfs: $e';
      });
    }
  }

  Future<void> _loadMyBookings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    setState(() {
      _loadingBookings = true;
      _error = null;
    });

    try {
      final rows = await _dbService.getPlayerBookings(userId);
      if (!mounted) return;
      setState(() {
        _bookings = rows.map((row) => BookingModel.fromMap(row)).toList();
        _loadingBookings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBookings = false;
        _error = 'Failed to load your bookings: $e';
      });
    }
  }

  Future<void> _logout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.loginSelection,
      (route) => false,
    );
  }

  Future<void> _openSlots(TurfModel turf) async {
    final dateStr = _selectedDate.toIso8601String().split('T').first;

    List<SlotModel> slots;
    try {
      final rows = await _dbService.fetchTurfSlotsForDate(turf.turfId, dateStr);
      slots = rows
          .map((row) => SlotModel.fromMap(row))
          .where((slot) => slot.status != SlotStatus.blocked)
          .toList()
        ..sort((a, b) {
          final netCmp = a.netNumber.compareTo(b.netNumber);
          if (netCmp != 0) return netCmp;
          return a.startTime.compareTo(b.startTime);
        });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Failed to load slots: $e', type: ToastType.error);
      return;
    }

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final bookingProvider =
        Provider.of<BookingProvider>(context, listen: false);

    final userId = authProvider.currentUserId;
    final player = authProvider.currentPlayer;

    if (userId == null || player == null) {
      showAppToast(
        context,
        'Session expired. Please login again.',
        type: ToastType.error,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final modalSlots = List<SlotModel>.from(slots);

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: BoxDecoration(
                color: AppColors.of(context).surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                turf.turfName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  color: AppColors.of(context).textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: modalSlots.isEmpty
                        ? const Center(
                            child: Text('No slots available for selected date'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (context, index) {
                              final slot = modalSlots[index];
                              final isAvailable =
                                  slot.status == SlotStatus.available;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            slot.displayTimeRange,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Net ${slot.netNumber} • Rs ${slot.price.toInt()}',
                                            style: TextStyle(
                                              color: AppColors.of(context)
                                                  .textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: !isAvailable
                                          ? null
                                          : () async {
                                              final bookingId =
                                                  await bookingProvider
                                                      .createAppBooking(
                                                turfId: turf.turfId,
                                                slotId: slot.slotId,
                                                bookingDate: dateStr,
                                                startTime: slot.startTime,
                                                endTime: slot.endTime,
                                                turfName: turf.turfName,
                                                userId: userId,
                                                customerName: player.name,
                                                customerPhone: player.phone,
                                                paymentMode:
                                                    PaymentMode.offline,
                                                amount: slot.price,
                                              );

                                              if (bookingId == null) {
                                                if (!modalContext.mounted) {
                                                  return;
                                                }
                                                showAppToast(
                                                  modalContext,
                                                  bookingProvider
                                                          .errorMessage ??
                                                      'Booking failed.',
                                                  type: ToastType.error,
                                                );
                                                return;
                                              }

                                              setModalState(() {
                                                modalSlots[index] =
                                                    slot.copyWith(
                                                  status: SlotStatus.reserved,
                                                );
                                              });

                                              if (!modalContext.mounted) {
                                                return;
                                              }
                                              showAppToast(
                                                modalContext,
                                                'Booking confirmed. ID: ${bookingId.substring(0, 8).toUpperCase()}',
                                                type: ToastType.success,
                                              );
                                              await _loadMyBookings();
                                            },
                                      child: Text(isAvailable
                                          ? 'Book'
                                          : slot.status.displayName),
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemCount: modalSlots.length,
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateSelector() {
    final c = AppColors.of(context);

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final date = DateTime.now().add(Duration(days: index));
          final isSelected = date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;

          return InkWell(
            onTap: () {
              setState(() => _selectedDate = date);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 76,
              decoration: BoxDecoration(
                color: isSelected
                    ? c.primary.withValues(alpha: 0.18)
                    : c.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? c.primary : c.glassBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun'
                    ][date.weekday - 1],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTurfsTab() {
    if (_loadingTurfs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _approvedTurfs.isEmpty) {
      return Center(child: Text(_error!));
    }

    if (_approvedTurfs.isEmpty) {
      return const Center(child: Text('No approved turfs available yet.'));
    }

    final c = AppColors.of(context);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _approvedTurfs.length,
        itemBuilder: (context, index) {
          final turf = _approvedTurfs[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: c.glassFill,
              border: Border.all(color: c.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turf.turfName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${turf.city} • ${turf.turfType.displayName}',
                  style: TextStyle(color: c.textSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nets: ${turf.numberOfNets} • ${turf.openTime}-${turf.closeTime}',
                        style: TextStyle(color: c.textSecondary),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _openSlots(turf),
                      child: const Text('View Slots'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookingsTab() {
    if (_loadingBookings) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bookings.isEmpty) {
      return const Center(child: Text('No bookings yet.'));
    }

    final c = AppColors.of(context);

    return RefreshIndicator(
      onRefresh: _loadMyBookings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final booking = _bookings[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: c.glassFill,
              border: Border.all(color: c.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.turfName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${booking.bookingDate} • ${booking.displayTimeRange}',
                  style: TextStyle(color: c.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Booking ID: ${booking.bookingId.substring(0, 8).toUpperCase()}',
                  style: TextStyle(color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Rs ${booking.amount.toInt()}'),
                    _chip(booking.paymentStatus.displayName),
                    _chip(booking.bookingStatus.displayName),
                  ],
                ),
              ],
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _bookings.length,
      ),
    );
  }

  Widget _chip(String text) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: c.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final playerName = authProvider.currentPlayer?.name ?? 'Player';

    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const AbstractBgShapes(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hi, $playerName',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                'Book from approved turfs',
                                style: TextStyle(color: c.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _refreshAll,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout),
                        ),
                      ],
                    ),
                  ),
                  _buildDateSelector(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedTab,
                      children: [
                        _buildTurfsTab(),
                        _buildBookingsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
          if (index == 1) {
            _loadMyBookings();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.stadium_outlined),
            selectedIcon: Icon(Icons.stadium),
            label: 'Turfs',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Bookings',
          ),
        ],
      ),
    );
  }
}
