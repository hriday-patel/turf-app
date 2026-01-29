import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../app/routes.dart';
import '../../../data/models/turf_model.dart';
import '../providers/turf_provider.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/constants/enums.dart';
import '../../auth/providers/auth_provider.dart';

/// Turf Detail Screen
/// Shows full turf information and provides access to slot management
class TurfDetailScreen extends StatefulWidget {
  final String turfId;

  const TurfDetailScreen({super.key, required this.turfId});

  @override
  State<TurfDetailScreen> createState() => _TurfDetailScreenState();
}

class _TurfDetailScreenState extends State<TurfDetailScreen> with RouteAware {
  @override
  void initState() {
    super.initState();
    _refreshData();
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
    debugPrint('TurfDetail: didPopNext - refreshing data');
    _refreshData();
  }
  
  Future<void> _refreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    if (authProvider.currentUserId != null) {
      // Force refresh from database to get latest data
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TurfProvider>(
      builder: (context, turfProvider, _) {
        final turf = turfProvider.getTurfById(widget.turfId);

        if (turf == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Turf Details')),
            body: const Center(child: Text('Turf not found')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              // App Bar with Image
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primary,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    turf.turfName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                    ),
                    child: turf.primaryImageUrl != null
                        ? Image.network(
                            turf.primaryImageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
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
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.sports_cricket,
                              size: 80,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      // TODO: Edit turf
                    },
                  ),
                ],
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

                      // Action Buttons
                      _buildActionButtons(context, turf),
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
            label: 'Location',
            value: turf.city,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            icon: Icons.sports_cricket,
            label: 'Type',
            value: turf.turfType.displayName,
          ),
        ),
        Expanded(
          child: _buildStatItem(
            icon: Icons.access_time,
            label: 'Duration',
            value: '${turf.slotDurationMinutes} min',
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
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
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, TurfModel turf) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.slotManagement,
                arguments: {'turfId': turf.turfId},
              );
            },
            icon: const Icon(Icons.calendar_view_day),
            label: const Text('Manage Slots'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.manualBooking,
                arguments: {'turfId': turf.turfId},
              );
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add Booking'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsSection(TurfModel turf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(Icons.location_on, 'Address', turf.address),
          if (turf.description != null) ...[
            const Divider(height: 24),
            _buildDetailRow(Icons.info_outline, 'About', turf.description!),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingSection(TurfModel turf) {
    final pricingRules = turf.pricingRules;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pricing',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Edit pricing
                },
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${turf.numberOfNets} Net(s) Available',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Show first net pricing summary
          if (pricingRules.netPricing.isNotEmpty) ...[
            _buildDayTypePricingRow(
              'Weekday',
              pricingRules.netPricing.first.weekday,
              AppColors.primary,
            ),
            const Divider(height: 16),
            _buildDayTypePricingRow(
              'Weekend',
              pricingRules.netPricing.first.weekend,
              AppColors.secondary,
            ),
            const Divider(height: 16),
            _buildDayTypePricingRow(
              'Holiday',
              pricingRules.netPricing.first.holiday,
              AppColors.warning,
            ),
          ],
          if (turf.numberOfNets > 1) ...[
            const SizedBox(height: 12),
            Text(
              'Showing prices for Net 1. Other nets may have different pricing.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayTypePricingRow(String label, DayTypePricing pricing, Color color) {
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
            _buildTimeSlotPrice('Morning', pricing.morning.price, Icons.wb_sunny_outlined),
            _buildTimeSlotPrice('Afternoon', pricing.afternoon.price, Icons.wb_cloudy_outlined),
            _buildTimeSlotPrice('Evening', pricing.evening.price, Icons.wb_twilight),
            _buildTimeSlotPrice('Night', pricing.night.price, Icons.nightlight_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeSlotPrice(String label, double price, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          PriceCalculator.formatPrice(price),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, double dayPrice, double nightPrice, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny, size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text(
                  PriceCalculator.formatPrice(dayPrice),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.nightlight, size: 14, color: AppColors.info),
                const SizedBox(width: 4),
                Text(
                  PriceCalculator.formatPrice(nightPrice),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOperatingHours(TurfModel turf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operating Hours',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.access_time, color: AppColors.primary),
              const SizedBox(width: 12),
              Text(
                '${turf.openTime} - ${turf.closeTime}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: turf.daysOpen.map((day) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  day,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
