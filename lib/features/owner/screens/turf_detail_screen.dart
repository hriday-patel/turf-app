import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../app/routes.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/strings.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../data/models/turf_model.dart';
import '../providers/turf_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'add_turf_screen.dart';

/// Turf Detail Screen
///
/// Displays full read-only information for a single turf the current owner
/// has access to. Sourced from [TurfProvider] (which holds the owner's full
/// turf list) and refreshed lazily via [TurfProvider.refreshTurfs].
///
/// Behaviour:
/// * Verifies that the requested [turfId] belongs to the signed-in owner; if
///   not, shows an unauthorized state instead of leaking another owner's data.
/// * Refreshes once on first build and again when the user pops back from a
///   pushed child screen (RouteAware), debounced via [_isRefreshing].
/// * Surfaces a refresh failure as a toast and lets the user retry via the
///   AppBar overflow menu.
/// * Provides quick navigation to Edit Turf and Manage Slots from the
///   overflow menu so the owner does not have to back out to `MyTurfs`.
class TurfDetailScreen extends StatefulWidget {
  final String turfId;

  const TurfDetailScreen({super.key, required this.turfId});

  @override
  State<TurfDetailScreen> createState() => _TurfDetailScreenState();
}

class _TurfDetailScreenState extends State<TurfDetailScreen> with RouteAware {
  bool _isRefreshing = false;
  int _selectedNetIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshData());
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
    _refreshData();
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    final ownerId = authProvider.currentUserId;
    if (ownerId == null) return;
    _isRefreshing = true;
    try {
      await turfProvider.refreshTurfs(ownerId);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          AppStrings.turfDetailRefreshFailed,
          type: ToastType.error,
        );
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId =
        Provider.of<AuthProvider>(context, listen: false).currentUserId;
    return Selector<TurfProvider, TurfModel?>(
      selector: (_, p) => p.getTurfById(widget.turfId),
      builder: (context, turf, _) {
        final c = AppColors.of(context);

        if (turf == null) {
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              backgroundColor: c.surface,
              leading: const BackButton(),
              title: const Text(AppStrings.turfDetailTitle),
            ),
            body: Center(
              child: Text(
                AppStrings.turfDetailNotFound,
                style: TextStyle(color: c.textPrimary),
              ),
            ),
          );
        }

        // TD-01: ownership guard — never display another owner's turf data.
        if (ownerId != null &&
            turf.ownerId.isNotEmpty &&
            turf.ownerId != ownerId) {
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              backgroundColor: c.surface,
              leading: const BackButton(),
              title: const Text(AppStrings.turfDetailTitle),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppStrings.turfDetailNotAuthorized,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textPrimary),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: c.background,
          body: GlassScaffoldBackground(
            child: CustomScrollView(
              slivers: [
                // App Bar with Image
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: c.surface,
                  actions: [
                    PopupMenuButton<String>(
                      tooltip: AppStrings.turfDetailMoreActionsTooltip,
                      icon: Icon(Icons.more_vert, color: c.textPrimary),
                      onSelected: (value) => _handleAction(value, turf),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text(AppStrings.turfDetailActionEdit),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'slots',
                          child: ListTile(
                            leading: Icon(Icons.event_available_outlined),
                            title: Text(AppStrings.turfDetailActionManageSlots),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'refresh',
                          child: ListTile(
                            leading: Icon(Icons.refresh),
                            title: Text(AppStrings.turfDetailActionRefresh),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      turf.turfName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: c.scaffoldGradient,
                      ),
                      child: turf.primaryImageUrl != null
                          ? Image.network(
                              turf.primaryImageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              cacheWidth:
                                  (MediaQuery.of(context).devicePixelRatio *
                                          MediaQuery.of(context).size.width)
                                      .round(),
                              gaplessPlayback: true,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: c.primary,
                                    value: loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                .cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.sports_cricket,
                                    size: 80,
                                    color: c.primary.withValues(alpha: 0.5),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                Icons.sports_cricket,
                                size: 80,
                                color: c.primary.withValues(alpha: 0.5),
                              ),
                            ),
                    ),
                  ),
                ),

                // Content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Stats
                        _buildQuickStats(turf),
                        const SizedBox(height: 24),

                        // Details Section
                        _buildDetailsSection(turf),
                        const SizedBox(height: 24),

                        // Pricing Section
                        _buildPricingSection(turf),
                        const SizedBox(height: 24),

                        // Operating Hours
                        _buildOperatingHours(turf),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(TurfModel turf) {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            icon: Icons.location_on,
            label: AppStrings.turfDetailStatLocation,
            value: turf.city,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            icon: Icons.sports_cricket,
            label: AppStrings.turfDetailStatType,
            value: turf.turfType.displayName,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            icon: Icons.access_time,
            label: AppStrings.turfDetailStatDuration,
            value:
                '${turf.slotDurationMinutes}${AppStrings.turfDetailDurationSuffix}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: c.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(TurfModel turf) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.turfDetailSectionDetails,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(Icons.location_on, AppStrings.turfDetailLabelAddress,
              turf.address),
          if (turf.description != null) ...[
            const Divider(height: 24),
            _buildDetailRow(Icons.info_outline, AppStrings.turfDetailLabelAbout,
                turf.description!),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final c = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: c.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingSection(TurfModel turf) {
    final c = AppColors.of(context);
    final pricingRules = turf.pricingRules;
    final netCount = pricingRules.netPricing.length;
    if (netCount == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.turfDetailSectionPricing,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.turfDetailPricingUnavailable,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ],
        ),
      );
    }

    final safeNetIndex = _selectedNetIndex >= netCount ? 0 : _selectedNetIndex;
    final selectedNet = pricingRules.netPricing[safeNetIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.turfDetailSectionPricing,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
              if (netCount > 1)
                DropdownButton<int>(
                  value: safeNetIndex,
                  underline: const SizedBox.shrink(),
                  items: List.generate(
                    netCount,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${AppStrings.turfDetailNetSelectorPrefix}${i + 1}',
                      ),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedNetIndex = v);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${turf.numberOfNets}${AppStrings.turfDetailNetsAvailableSuffix}',
            style: TextStyle(
              fontSize: 13,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _buildDayTypePricingRow(
            AppStrings.turfDetailDayWeekday,
            selectedNet.weekday,
            c.primary,
          ),
          const Divider(height: 16),
          _buildDayTypePricingRow(
            AppStrings.turfDetailDayWeekend,
            selectedNet.weekend,
            c.secondary,
          ),
          const Divider(height: 16),
          _buildDayTypePricingRow(
            AppStrings.turfDetailDayHoliday,
            selectedNet.holiday,
            c.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildDayTypePricingRow(
      String label, DayTypePricing pricing, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTimeSlotPrice(AppStrings.turfDetailSlotMorning,
                pricing.morning.price, Icons.wb_sunny_outlined),
            _buildTimeSlotPrice(AppStrings.turfDetailSlotAfternoon,
                pricing.afternoon.price, Icons.wb_cloudy_outlined),
            _buildTimeSlotPrice(AppStrings.turfDetailSlotEvening,
                pricing.evening.price, Icons.wb_twilight),
            _buildTimeSlotPrice(AppStrings.turfDetailSlotNight,
                pricing.night.price, Icons.nightlight_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeSlotPrice(String label, double price, IconData icon) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Icon(icon, size: 16, color: c.textSecondary),
        const SizedBox(height: 4),
        Text(
          PriceCalculator.formatPrice(price),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildOperatingHours(TurfModel turf) {
    final c = AppColors.of(context);
    final sortedDays = _sortDaysOfWeek(turf.daysOpen);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.turfDetailSectionHours,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time, color: c.primary),
              const SizedBox(width: 12),
              Text(
                '${_formatTime(turf.openTime)} - ${_formatTime(turf.closeTime)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sortedDays.map((day) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  day,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.primary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _handleAction(String value, TurfModel turf) {
    switch (value) {
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => AddTurfScreen(editTurf: turf),
          ),
        );
        break;
      case 'slots':
        Navigator.pushNamed(
          context,
          AppRoutes.slotManagement,
          arguments: {'turfId': turf.turfId},
        );
        break;
      case 'refresh':
        _refreshData();
        break;
    }
  }

  // TD-23: Sort day chips in canonical Mon→Sun order regardless of DB order.
  static const List<String> _weekOrder = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  List<String> _sortDaysOfWeek(List<String> days) {
    final sorted = [...days];
    sorted.sort((a, b) {
      final ai =
          _weekOrder.indexWhere((d) => d.toLowerCase() == a.toLowerCase());
      final bi =
          _weekOrder.indexWhere((d) => d.toLowerCase() == b.toLowerCase());
      if (ai == -1 && bi == -1) return a.compareTo(b);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return sorted;
  }

  // TD-15: Strip trailing seconds ("09:00:00" → "09:00") from raw DB time strings.
  String _formatTime(String raw) {
    final parts = raw.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return raw;
  }
}
