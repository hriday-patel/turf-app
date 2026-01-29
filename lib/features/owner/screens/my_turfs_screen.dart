import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../../../data/models/turf_model.dart';
import '../../../core/constants/enums.dart';
import '../../auth/providers/auth_provider.dart';
import 'add_turf_screen.dart';

/// My Turfs Screen
/// Shows list of owner's turfs with 3 tabs: All, Pending, Approved
class MyTurfsScreen extends StatefulWidget {
  const MyTurfsScreen({super.key});

  @override
  State<MyTurfsScreen> createState() => _MyTurfsScreenState();
}

class _MyTurfsScreenState extends State<MyTurfsScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshTurfs();
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
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  void didPopNext() {
    // Called when returning to this screen
    debugPrint('MyTurfs: didPopNext - refreshing data');
    _refreshTurfs();
  }
  
  Future<void> _refreshTurfs() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    if (authProvider.currentUserId != null) {
      // Force refresh from database to get latest data
      await turfProvider.refreshTurfs(authProvider.currentUserId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.myTurfs),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.addTurf),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All Turfs'),
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
          ],
        ),
      ),
      body: Consumer<TurfProvider>(
        builder: (context, turfProvider, _) {
          final allTurfs = turfProvider.turfs;
          final pendingTurfs = allTurfs
              .where((t) => t.verificationStatus == VerificationStatus.pending)
              .toList();
          final approvedTurfs = allTurfs
              .where((t) => t.verificationStatus == VerificationStatus.approved)
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildTurfList(context, allTurfs, 'No turfs yet'),
              _buildTurfList(context, pendingTurfs, 'No pending turfs'),
              _buildTurfList(context, approvedTurfs, 'No approved turfs'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTurfList(
      BuildContext context, List<TurfModel> turfs, String emptyMessage) {
    if (turfs.isEmpty) {
      return _buildEmptyState(context, emptyMessage);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: turfs.length,
      itemBuilder: (context, index) {
        final turf = turfs[index];
        return _buildTurfCard(context, turf);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.stadium_outlined,
              size: 50,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a turf to start accepting bookings',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.addTurf),
            icon: const Icon(Icons.add),
            label: const Text('Add Turf'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurfCard(BuildContext context, TurfModel turf) {
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image/Placeholder with status overlay
          Stack(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: turf.primaryImageUrl != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Image.network(
                          turf.primaryImageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 140,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
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
                                size: 50,
                                color: AppColors.primary.withOpacity(0.5),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.sports_cricket,
                          size: 50,
                          color: AppColors.primary.withOpacity(0.5),
                        ),
                      ),
              ),
              // Turf status badge (open/closed/renovation)
              if (turf.isApproved)
                Positioned(
                  top: 10,
                  left: 10,
                  child: _buildTurfStatusBadge(turf.status),
                ),
            ],
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        turf.turfName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildVerificationStatusBadge(turf.verificationStatus),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${turf.address}, ${turf.city}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    _buildInfoChip(
                      icon: Icons.access_time,
                      text: '${turf.openTime} - ${turf.closeTime}',
                    ),
                    const SizedBox(width: 12),
                    _buildInfoChip(
                      icon: Icons.sports_cricket,
                      text: turf.turfType.displayName,
                    ),
                    const SizedBox(width: 12),
                    _buildInfoChip(
                      icon: Icons.grid_view,
                      text: '${turf.numberOfNets} Nets',
                    ),
                  ],
                ),

                if (!turf.isApproved) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            turf.verificationStatus == VerificationStatus.pending
                                ? 'Awaiting admin verification'
                                : 'Turf rejected: ${turf.rejectionReason ?? "Contact support"}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateToEdit(context, turf),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (turf.isApproved) ...[
                      Expanded(
                        child: _buildStatusToggleButton(context, turf),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: turf.isApproved
                            ? () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.turfDetail,
                                  arguments: {'turfId': turf.turfId},
                                )
                            : null,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusToggleButton(BuildContext context, TurfModel turf) {
    final isOpen = turf.status == TurfStatus.open;

    return PopupMenuButton<TurfStatus>(
      onSelected: (status) async {
        final turfProvider = Provider.of<TurfProvider>(context, listen: false);
        final success = await turfProvider.updateTurfStatus(turf.turfId, status);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Turf status updated to ${status.displayName}'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      },
      itemBuilder: (context) => TurfStatus.values.map((status) {
        final isSelected = turf.status == status;
        return PopupMenuItem(
          value: status,
          child: Row(
            children: [
              Icon(
                status == TurfStatus.open
                    ? Icons.check_circle
                    : status == TurfStatus.closed
                        ? Icons.cancel
                        : Icons.construction,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                status.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isOpen ? AppColors.successLight : AppColors.warningLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOpen ? AppColors.success : AppColors.warning,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOpen ? Icons.toggle_on : Icons.toggle_off,
              size: 18,
              color: isOpen ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 4),
            Text(
              turf.status.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOpen ? AppColors.success : AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(BuildContext context, TurfModel turf) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTurfScreen(editTurf: turf),
      ),
    ).then((result) {
      if (result == true) {
        // Refresh turfs after editing
        final authProvider =
            Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.currentUserId != null) {
          Provider.of<TurfProvider>(context, listen: false)
              .loadOwnerTurfs(authProvider.currentUserId!);
        }
      }
    });
  }

  Widget _buildTurfStatusBadge(TurfStatus status) {
    Color color;
    IconData icon;

    switch (status) {
      case TurfStatus.open:
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case TurfStatus.closed:
        color = AppColors.error;
        icon = Icons.cancel;
        break;
      case TurfStatus.renovation:
        color = AppColors.warning;
        icon = Icons.construction;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStatusBadge(VerificationStatus status) {
    Color color;
    String text;

    switch (status) {
      case VerificationStatus.approved:
        color = AppColors.success;
        text = 'Approved';
        break;
      case VerificationStatus.pending:
        color = AppColors.warning;
        text = 'Pending';
        break;
      case VerificationStatus.rejected:
        color = AppColors.error;
        text = 'Rejected';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
