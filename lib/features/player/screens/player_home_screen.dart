import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../config/abstract_bg.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/database_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../owner/providers/booking_provider.dart';

/// Player home screen.
///
/// Layout (Phase 5 Iter 23 hardened):
///   * Two-tab `IndexedStack` driven by [_selectedTab]:
///       - 0 = approved turfs list with horizontal date selector + booking sheet
///       - 1 = the player's own bookings list
///   * `_selectedDate` only affects the slot fetch when the user opens a turf;
///     it does NOT auto-refresh either tab on date change (intentional).
///   * `_logout` is wrapped in a nav-guard (`_isNavigating`) so double-taps
///     cannot stack `pushNamedAndRemoveUntil` calls.
///   * Each booking row in the modal sheet has its own busy flag
///     (`_bookingInFlight`) so spam-tapping cannot create duplicate bookings.
///   * Per-section error state (`_turfsError` / `_bookingsError`) so a
///     successful load on one section does not wipe the other's error.
class PlayerHomeScreen extends StatefulWidget {
  const PlayerHomeScreen({super.key});

  @override
  State<PlayerHomeScreen> createState() => _PlayerHomeScreenState();
}

class _PlayerHomeScreenState extends State<PlayerHomeScreen> {
  // ---- Layout constants (PH-14) -----------------------------------------
  static const double _dateSelectorHeight = 80;
  static const double _dateChipWidth = 76;
  static const double _modalHeightFraction = 0.82;
  static const double _selectedChipAlpha = 0.18;
  static const double _chipBgAlpha = 0.12;
  static const double _pillRadius = 999;
  static const double _slotBorderAlpha = 0.2;

  static const List<String> _weekdayShortNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  final DatabaseService _dbService = DatabaseService();

  DateTime _selectedDate = _todayAtMidnight();
  int _selectedTab = 0;
  bool _loadingTurfs = false;
  bool _loadingBookings = false;
  bool _isNavigating = false;

  List<TurfModel> _approvedTurfs = [];
  List<BookingModel> _bookings = [];

  String? _turfsError;
  String? _bookingsError;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  // ---- Helpers ----------------------------------------------------------

  static DateTime _todayAtMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Format a [DateTime] as a midnight-stable `yyyy-MM-dd` string in local
  /// time (PH-08): avoids the toIso8601String UTC-shift bug at edges of day.
  String _formatYmd(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  /// Safe truncation of an id for display (PH-02).
  String _shortId(String id, [int len = 8]) {
    if (id.isEmpty) return '';
    final n = id.length < len ? id.length : len;
    return id.substring(0, n).toUpperCase();
  }

  Future<void> _guardedNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await action();
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  // ---- Data loading -----------------------------------------------------

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadApprovedTurfs(),
      _loadMyBookings(),
    ]);
  }

  Future<void> _loadApprovedTurfs() async {
    setState(() {
      _loadingTurfs = true;
      _turfsError = null;
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
        _turfsError = '${AppStrings.playerHomeLoadTurfsFailedPrefix}$e';
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
      _bookingsError = null;
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
        _bookingsError = '${AppStrings.playerHomeLoadBookingsFailedPrefix}$e';
      });
    }
  }

  // ---- Actions ----------------------------------------------------------

  Future<void> _logout() async {
    await _guardedNavigate(() async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      try {
        await authProvider.signOut();
      } catch (_) {
        if (!mounted) return;
        showAppToast(
          context,
          AppStrings.playerHomeLogoutFailed,
          type: ToastType.error,
        );
        return;
      }
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.loginSelection,
        (route) => false,
      );
    });
  }

  Future<void> _openSlots(TurfModel turf) async {
    final dateStr = _formatYmd(_selectedDate);

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
      showAppToast(
        context,
        '${AppStrings.playerHomeLoadSlotsFailedPrefix}$e',
        type: ToastType.error,
      );
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
        AppStrings.playerHomeSessionExpired,
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
        final bookingInFlight = List<bool>.filled(modalSlots.length, false);

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final c = AppColors.of(modalContext);

            return Container(
              height:
                  MediaQuery.of(modalContext).size.height * _modalHeightFraction,
              decoration: BoxDecoration(
                color: c.surface,
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
                                style: TextStyle(color: c.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.playerHomeCloseTooltip,
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
                            child: Text(AppStrings.playerHomeNoSlots),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: modalSlots.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final slot = modalSlots[index];
                              final isAvailable =
                                  slot.status == SlotStatus.available;
                              final busy = bookingInFlight[index];
                              final canBook = isAvailable && !busy;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: c.glassBorder),
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
                                            '${AppStrings.playerHomeNetPrefix}${slot.netNumber} • ${AppStrings.playerHomeRupeePrefix}${slot.price.toInt()}',
                                            style: TextStyle(
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: !canBook
                                          ? null
                                          : () async {
                                              setModalState(() {
                                                bookingInFlight[index] = true;
                                              });

                                              String? bookingId;
                                              try {
                                                bookingId = await bookingProvider
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
                                              } finally {
                                                if (modalContext.mounted) {
                                                  setModalState(() {
                                                    bookingInFlight[index] =
                                                        false;
                                                  });
                                                }
                                              }

                                              if (!modalContext.mounted) {
                                                return;
                                              }

                                              if (bookingId == null) {
                                                showAppToast(
                                                  modalContext,
                                                  bookingProvider
                                                          .errorMessage ??
                                                      AppStrings
                                                          .playerHomeBookingFailed,
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

                                              showAppToast(
                                                modalContext,
                                                '${AppStrings.playerHomeBookingConfirmedPrefix}${_shortId(bookingId)}',
                                                type: ToastType.success,
                                              );
                                              await _loadMyBookings();
                                            },
                                      child: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              isAvailable
                                                  ? AppStrings.playerHomeBook
                                                  : slot.status.displayName,
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
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

  // ---- UI builders ------------------------------------------------------

  Widget _buildDateSelector() {
    final c = AppColors.of(context);

    return SizedBox(
      height: _dateSelectorHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final today = _todayAtMidnight();
          final date = today.add(Duration(days: index));
          final isSelected = date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;

          return InkWell(
            onTap: () {
              setState(() => _selectedDate = date);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: _dateChipWidth,
              decoration: BoxDecoration(
                color: isSelected
                    ? c.primary.withValues(alpha: _selectedChipAlpha)
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
                    _weekdayShortNames[date.weekday - 1],
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

    if (_turfsError != null && _approvedTurfs.isEmpty) {
      return Center(child: Text(_turfsError!));
    }

    if (_approvedTurfs.isEmpty) {
      return const Center(child: Text(AppStrings.playerHomeNoTurfs));
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
                        '${AppStrings.playerHomeNetsPrefix}${turf.numberOfNets} • ${turf.openTime}-${turf.closeTime}',
                        style: TextStyle(color: c.textSecondary),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _openSlots(turf),
                      child: const Text(AppStrings.playerHomeViewSlots),
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

    if (_bookingsError != null && _bookings.isEmpty) {
      return Center(child: Text(_bookingsError!));
    }

    if (_bookings.isEmpty) {
      return const Center(child: Text(AppStrings.playerHomeNoBookings));
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
                  '${AppStrings.playerHomeBookingIdPrefix}${_shortId(booking.bookingId)}',
                  style: TextStyle(color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('${AppStrings.playerHomeRupeePrefix}${booking.amount.toInt()}'),
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
        borderRadius: BorderRadius.circular(_pillRadius),
        color: c.primary.withValues(alpha: _chipBgAlpha),
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
    // PH-05: scope rebuilds to just the displayed player name.
    final playerName = context.select<AuthProvider, String>(
      (auth) => auth.currentPlayer?.name ?? AppStrings.playerHomeFallbackName,
    );
    // Silence the unused-variable lint without removing readability above.
    // ignore: unused_local_variable
    final _ = _slotBorderAlpha;

    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: Stack(
          children: [
            const RepaintBoundary(child: AbstractBgShapes()),
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
                                '${AppStrings.playerHomeGreetingPrefix}$playerName',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                AppStrings.playerHomeSubtitle,
                                style: TextStyle(color: c.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.playerHomeRefreshTooltip,
                          onPressed: _refreshAll,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: AppStrings.playerHomeLogoutTooltip,
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
            label: AppStrings.playerHomeTabTurfs,
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: AppStrings.playerHomeTabBookings,
          ),
        ],
      ),
    );
  }
}
