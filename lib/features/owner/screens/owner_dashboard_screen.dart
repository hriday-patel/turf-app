import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../config/section_container.dart';
import '../../../config/theme_provider.dart';
import '../../../core/constants/strings.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../../../data/models/booking_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';
import '../providers/booking_provider.dart';

/// Owner Dashboard Screen
/// Central hub for turf owners to manage their business
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  late final PageController _carouselController;
  double _carouselPage = 0;
  Timer? _autoSlideTimer;

  // Quick Actions staggered entrance animation
  late final AnimationController _actionAnimController;
  late final List<Animation<double>> _actionFadeAnims;
  late final List<Animation<Offset>> _actionSlideAnims;
  static const int _carouselRealCount = 4;
  // Large multiplier for infinite loop illusion
  static const int _carouselLoopMultiplier = 1000;
  static const int _carouselInitialPage = _carouselLoopMultiplier ~/ 2 * _carouselRealCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carouselController = PageController(
      viewportFraction: 0.80,
      initialPage: _carouselInitialPage,
    );
    _carouselPage = _carouselInitialPage.toDouble();
    _carouselController.addListener(() {
      setState(() {
        _carouselPage = _carouselController.page ?? 0;
      });
    });
    _startAutoSlide();

    // Staggered animation for 4 Quick Action cards (350ms each, staggered)
    _actionAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _actionFadeAnims = List.generate(4, (i) {
      final start = i * 0.15;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _actionAnimController, curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _actionSlideAnims = List.generate(4, (i) {
      final start = i * 0.15;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 10), end: Offset.zero).animate(
        CurvedAnimation(parent: _actionAnimController, curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });
    _actionAnimController.forward();

    _loadData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRoutes.routeObserver.subscribe(this, route);
    }
  }
  
  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _actionAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppRoutes.routeObserver.unsubscribe(this);
    _carouselController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (_carouselController.hasClients) {
        _carouselController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
    // Resume after 5 seconds of inactivity
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _startAutoSlide();
    });
  }
  
  @override
  void didPopNext() {
    // Called when returning to this screen from another screen
    debugPrint('Dashboard: didPopNext - refreshing data');
    _forceRefreshData();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes to foreground
      _forceRefreshData();
    }
  }

  Future<void> _forceRefreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);

    if (authProvider.currentUserId != null) {
      // Force refresh from database to get latest verification status
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
      
      // Refresh Quick Overview stats for approved turfs
      final approvedTurfIds = turfProvider.approvedTurfs.map((t) => t.turfId).toList();
      if (approvedTurfIds.isNotEmpty) {
        bookingProvider.loadTodaysBookings(approvedTurfIds);
        bookingProvider.loadPendingPayments(approvedTurfIds);
      }
      
      // Refresh Recent Bookings for ALL turfs
      final allTurfIds = turfProvider.turfIds;
      if (allTurfIds.isNotEmpty) {
        bookingProvider.loadRecentBookings(allTurfIds);
      }
    }
  }

  void _loadData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);

    if (authProvider.currentUserId != null) {
      turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
    }
  }

  void _refreshBookings() {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    
    // Load Quick Overview stats for approved turfs
    final approvedTurfIds = turfProvider.approvedTurfs.map((t) => t.turfId).toList();
    if (approvedTurfIds.isNotEmpty) {
      bookingProvider.loadTodaysBookings(approvedTurfIds);
      bookingProvider.loadPendingPayments(approvedTurfIds);
    }
    
    // Load Recent Bookings for ALL turfs
    final allTurfIds = turfProvider.turfIds;
    if (allTurfIds.isNotEmpty) {
      bookingProvider.loadRecentBookings(allTurfIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _forceRefreshData,
            color: c.primary,
            backgroundColor: c.surface,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: _buildQuickStats()),
                SliverToBoxAdapter(child: _buildActionCards()),
                SliverToBoxAdapter(child: _buildRecentActivity()),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: [c.primary, c.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => Navigator.pushNamed(context, AppRoutes.addTurf),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: c.onPrimary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add Turf',
                    style: TextStyle(color: c.onPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final c = AppColors.of(context);
        final owner = authProvider.currentOwner;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          fontSize: 14,
                          color: c.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        owner?.name ?? 'Owner',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Theme toggle
                      Consumer<ThemeProvider>(
                        builder: (context, themeProvider, _) {
                          return GestureDetector(
                            onTap: () => themeProvider.toggle(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: c.glassFill,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.glassBorder),
                              ),
                              child: Icon(
                                themeProvider.isDarkMode
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                                color: c.primary,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        icon: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.glassFill,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.primary.withValues(alpha: 0.3)),
                            boxShadow: AppColors.neonGlow(blur: 8),
                          ),
                          child: Center(
                            child: Text(
                              (owner?.name ?? 'O').substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        onSelected: (value) async {
                          if (value == 'settings') {
                            Navigator.pushNamed(context, AppRoutes.settings);
                          } else if (value == 'logout') {
                            final didLogout =
                                await _confirmAndSignOut(authProvider);
                            if (mounted && didLogout) {
                              Navigator.pushReplacementNamed(context, AppRoutes.loginSelection);
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(children: [Icon(Icons.person_outline, color: c.textSecondary), const SizedBox(width: 8), Text('Profile', style: TextStyle(color: c.textPrimary))]),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(children: [Icon(Icons.logout, color: c.error), const SizedBox(width: 8), Text('Logout', style: TextStyle(color: c.error))]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date pill
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                borderRadius: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, color: c.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _getFormattedDate(),
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _bookingsInitialized = false;

  Future<bool> _confirmAndSignOut(AuthProvider authProvider) async {
    final c = AppColors.of(context);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            bool isLoading = false;

            return StatefulBuilder(
              builder: (dialogContext, setDialogState) {
                return PopScope(
                  canPop: false,
                  child: AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                setDialogState(() => isLoading = true);
                                await authProvider.signOut();
                                if (!mounted) return;

                                if (authProvider.errorMessage != null) {
                                  setDialogState(() => isLoading = false);
                                  return;
                                }

                                if (Navigator.canPop(dialogContext)) {
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                        child: isLoading
                            ? const _BouncingBallLoader()
                            : Text('Logout', style: TextStyle(color: c.error)),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ) ??
        false;
  }

  Widget _buildQuickStats() {
    return Consumer2<TurfProvider, BookingProvider>(
      builder: (context, turfProvider, bookingProvider, _) {
        final c = AppColors.of(context);
        // Initialize bookings once when turfs become available
        if (turfProvider.turfIds.isNotEmpty && !_bookingsInitialized) {
          _bookingsInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _refreshBookings();
          });
        }

        return SectionContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 170,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _pauseAutoSlide();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _carouselController,
                    itemCount: _carouselRealCount * _carouselLoopMultiplier,
                    itemBuilder: (context, index) {
                      final realIndex = index % _carouselRealCount;
                      final cards = [
                        _CarouselCardData(
                          title: "Today's Bookings",
                          value: '${bookingProvider.todaysCount}',
                          icon: Icons.event_available,
                          iconColor: const Color(0xFF1F9D57),
                          bgColor: const Color(0xFFCFEED8),
                          subtitle: 'Confirmed',
                        ),
                        _CarouselCardData(
                          title: 'Pending Payments',
                          value: '${bookingProvider.pendingPaymentsCount}',
                          icon: Icons.currency_rupee,
                          iconColor: const Color(0xFFEA6A1B),
                          bgColor: const Color(0xFFFFD8BF),
                          subtitle: 'Pay at turf',
                        ),
                        _CarouselCardData(
                          title: 'Total Turfs',
                          value: '${turfProvider.totalTurfs}',
                          icon: Icons.sports_cricket,
                          iconColor: const Color(0xFF5B47C7),
                          bgColor: const Color(0xFFD9CCFF),
                          subtitle: '${turfProvider.approvedCount} approved',
                        ),
                        _CarouselCardData(
                          title: 'Pending Approval',
                          value: '${turfProvider.pendingCount}',
                          icon: Icons.pending_actions,
                          iconColor: const Color(0xFFC69214),
                          bgColor: const Color(0xFFFFE7A8),
                          subtitle: 'Verification',
                        ),
                      ];

                      // Scale: active = 1.0, neighbors shrink to 0.9
                      final diff = (index - _carouselPage).abs();
                      final scale = (1 - diff * 0.10).clamp(0.88, 1.0);
                      final opacity = (1 - diff * 0.25).clamp(0.6, 1.0);

                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: _buildCarouselCard(cards[realIndex]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCarouselCard(_CarouselCardData data) {
    // Carousel cards always have light pastel backgrounds — text must be dark for contrast
    const darkText = Color(0xFF1E293B);
    const subtitleText = Color(0xFF475569);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.bgColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Subtle decorative circle top-right
          Positioned(
            top: -14,
            right: -14,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: data.iconColor.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: data.iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(data.icon, color: data.iconColor, size: 24),
                  ),
                  Text(
                    data.value,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: data.iconColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '',
                style: TextStyle(fontSize: 0),
              ),
              Text(
                data.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: subtitleText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    final c = AppColors.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards() {
    final c = AppColors.of(context);
    return SectionContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Row 1 + Row 2: Left tall card + two right cards stacked
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left tall card spanning two rows
                Expanded(
                  child: _animatedCard(
                    index: 0,
                    child: _buildDashCard(
                      title: 'Booking Dashboard',
                      subtitle: 'Create bookings and manage slot availability',
                      icon: Icons.access_time_outlined,
                      bgColor: const Color(0xFF1F2937),
                      onTap: () => Navigator.pushNamed(context, AppRoutes.slotBooking),
                      tall: true,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Right column: two stacked cards
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          index: 1,
                          child: _buildDashCard(
                            title: 'View Turfs',
                            subtitle: 'Manage your turfs, view status and edit details',
                            icon: Icons.stadium_outlined,
                            bgColor: const Color(0xFF273445),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.myTurfs),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _animatedCard(
                          index: 2,
                          child: _buildDashCard(
                            title: 'View History',
                            subtitle: 'View all bookings and manage payments',
                            icon: Icons.calendar_month_outlined,
                            bgColor: const Color(0xFF334155),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.bookingManagement),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Row 3: Full width card
          _animatedCard(
            index: 3,
            child: _buildDashCard(
              title: 'Analytics Dashboard',
              subtitle: 'View trends, analyse peak hours and utilisation metrics',
              icon: Icons.analytics_outlined,
              bgColor: const Color(0xFF3F4D63),
              onTap: () => Navigator.pushNamed(context, AppRoutes.analytics),
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedCard({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _actionAnimController,
      builder: (context, _) {
        return Transform.translate(
          offset: _actionSlideAnims[index].value,
          child: Opacity(
            opacity: _actionFadeAnims[index].value,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildDashCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color bgColor,
    required VoidCallback onTap,
    bool tall = false,
    bool fullWidth = false,
  }) {
    const iconColor = Color(0xFFE2E8F0);
    const primaryText = Color(0xFFF8FAFC);
    const secondaryText = Color(0xFFCBD5E1);
    final iconBgColor = Color.lerp(bgColor, Colors.white, 0.12)!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: tall ? const BoxConstraints(minHeight: 220) : null,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fullWidth ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            if (!fullWidth) const Spacer(),
            if (fullWidth) const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: secondaryText,
                height: 1.3,
              ),
            ),
            if (tall) const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final c = AppColors.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Consumer<BookingProvider>(
      builder: (context, bookingProvider, _) {
        final c = AppColors.of(context);
        final recentBookings = bookingProvider.recentBookings;
        
        return NotchedSectionContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Bookings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.bookingManagement);
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recentBookings.isEmpty)
                _buildEmptyState()
              else
                _buildTimeline(recentBookings),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final c = AppColors.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 48,
              color: c.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No recent bookings',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBookingDateShort(String bookingDate) {
    try {
      final parts = bookingDate.split('-');
      if (parts.length == 3) {
        final day = parts[2];
        final monthIndex = int.parse(parts[1]);
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        return '$day\n${months[monthIndex - 1]}';
      }
    } catch (_) {}
    return bookingDate;
  }

  Widget _buildTimeline(List<BookingModel> bookings) {
    final c = AppColors.of(context);
    return Column(
      children: List.generate(bookings.length, (index) {
        final booking = bookings[index];
        final isLast = index == bookings.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: date & time
              SizedBox(
                width: 48,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatBookingDateShort(booking.bookingDate),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              // Timeline column: marker + line
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: c.primaryLight,
                        ),
                      ),
                  ],
                ),
              ),
              // Right: booking card
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  child: _buildTimelineCard(booking),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTimelineCard(BookingModel booking) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: c.textPrimary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.customerName.isNotEmpty ? booking.customerName : 'Customer',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_outlined, size: 13, color: c.textSecondary),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        booking.displayTimeRange,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildPaymentBadge(booking.paymentStatus.displayName),
        ],
      ),
    );
  }

  Widget _buildPaymentBadge(String status) {
    final c = AppColors.of(context);
    final bool isPaid = status.toLowerCase() == 'paid';
    final Color bgColor = isPaid ? c.successLight : c.border;
    final Color textColor = isPaid ? c.success : c.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}

class _CarouselCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String subtitle;

  const _CarouselCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.subtitle,
  });
}

class _BouncingBallLoader extends StatefulWidget {
  const _BouncingBallLoader();

  @override
  State<_BouncingBallLoader> createState() => _BouncingBallLoaderState();
}

class _BouncingBallLoaderState extends State<_BouncingBallLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final bounce = Curves.easeInOut.transform(_controller.value);
          return Align(
            alignment: Alignment(0.0, 1.0 - (bounce * 2.0)),
            child: child,
          );
        },
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
