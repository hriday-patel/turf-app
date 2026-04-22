import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/strings.dart';
import '../../../app/routes.dart';
import '../providers/turf_provider.dart';
import '../../../data/models/turf_model.dart';
import '../../../core/constants/enums.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
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
  final Set<String> _pendingStatusUpdates = {};
  String? _lastLoadedOwnerId;
  bool _isRefreshingTurfs =
      false; // small-stuff: guard against overlapping refreshes

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

    // Ensure turfs load even when auth became ready after initState.
    _ensureTurfsLoaded();
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
    if (_isRefreshingTurfs)
      return; // small-stuff: skip if a load is already running
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    if (authProvider.currentUserId != null) {
      _isRefreshingTurfs = true;
      try {
        // Force refresh from database to get latest data
        await turfProvider.refreshTurfs(authProvider.currentUserId!);
      } finally {
        _isRefreshingTurfs = false;
      }
    }
  }

  Future<void> _ensureTurfsLoaded() async {
    if (_isRefreshingTurfs)
      return; // small-stuff: don't stomp on an in-flight refresh
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerId = authProvider.currentUserId;
    if (ownerId == null || ownerId.isEmpty) return;
    if (_lastLoadedOwnerId == ownerId) return;

    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    _lastLoadedOwnerId = ownerId;
    _isRefreshingTurfs = true;
    try {
      turfProvider.loadOwnerTurfs(ownerId);
      await turfProvider.refreshTurfs(ownerId);
    } finally {
      _isRefreshingTurfs = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Glass app bar
              GlassAppBar(
                title: AppStrings.myTurfs,
                actions: [
                  IconButton(
                    icon: Icon(Icons.add, color: c.primary),
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.addTurf),
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: c.primary,
                  indicatorWeight: 2,
                  labelColor: c.primary,
                  unselectedLabelColor: c.textSecondary,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'All Turfs'),
                    Tab(text: 'Pending'),
                    Tab(text: 'Approved'),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<TurfProvider>(
                  builder: (context, turfProvider, _) {
                    final allTurfs = turfProvider.turfs;
                    final pendingTurfs = allTurfs
                        .where((t) =>
                            t.verificationStatus == VerificationStatus.pending)
                        .toList();
                    final approvedTurfs = allTurfs
                        .where((t) =>
                            t.verificationStatus == VerificationStatus.approved)
                        .toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTurfList(context, allTurfs, 'No turfs yet'),
                        _buildTurfList(
                            context, pendingTurfs, 'No pending turfs'),
                        _buildTurfList(
                            context, approvedTurfs, 'No approved turfs'),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: c.glassFill,
              shape: BoxShape.circle,
              border: Border.all(color: c.glassBorder),
              boxShadow: AppColors.neonGlow(color: c.primary),
            ),
            child: Icon(
              Icons.stadium_outlined,
              size: 50,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a turf to start accepting bookings',
            style: TextStyle(
              fontSize: 14,
              color: c.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 180,
            child: GlassButton(
              label: 'Add Turf',
              icon: Icons.add,
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addTurf),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurfCard(BuildContext context, TurfModel turf) {
    final c = AppColors.of(context);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
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
                  color: c.primary.withValues(alpha: 0.1),
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
                                value: loadingProgress.expectedTotalBytes !=
                                        null
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
                                color: c.primary.withValues(alpha: 0.5),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.sports_cricket,
                          size: 50,
                          color: c.primary.withValues(alpha: 0.5),
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
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
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${turf.address}, ${turf.city}',
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textSecondary,
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
                      color: c.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: c.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: c.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            turf.verificationStatus ==
                                    VerificationStatus.pending
                                ? 'Awaiting admin verification'
                                : 'Turf rejected: ${turf.rejectionReason ?? "Contact support"}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.warning,
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
                          foregroundColor: c.primary,
                          side: BorderSide(color: c.primary),
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
                          backgroundColor: c.primary,
                          foregroundColor: c.onPrimary,
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
    final c = AppColors.of(context);
    final isUpdating = _pendingStatusUpdates.contains(turf.turfId);
    final statusColor = switch (turf.status) {
      TurfStatus.open => c.success,
      TurfStatus.closed => c.error,
      TurfStatus.renovation => c.warning,
    };
    final statusLightColor = switch (turf.status) {
      TurfStatus.open => c.successLight,
      TurfStatus.closed => c.error.withValues(alpha: 0.12),
      TurfStatus.renovation => c.warningLight,
    };

    return PopupMenuButton<TurfStatus>(
      enabled: !isUpdating,
      onSelected: (status) => _handleStatusUpdate(turf, status),
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
                color: isSelected ? c.primary : c.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                status.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? c.primary : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: statusLightColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: statusColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isUpdating)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              )
            else
              Icon(
                turf.status == TurfStatus.open
                    ? Icons.toggle_on
                    : Icons.toggle_off,
                size: 18,
                color: statusColor,
              ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                turf.status.displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleStatusUpdate(TurfModel turf, TurfStatus status) async {
    if (_pendingStatusUpdates.contains(turf.turfId)) {
      return;
    }

    if (status == turf.status && status != TurfStatus.renovation) {
      return;
    }

    // U6: Confirm before flipping turf visibility status.
    if (status != TurfStatus.renovation) {
      final visibilityNote = status == TurfStatus.open
          ? 'Customers will be able to see and book this turf again.'
          : "Customers won't see or book this turf while it's ${status.displayName.toLowerCase()}.";
      final confirmed = await showDialog<bool>(
        context: this.context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Change status to ${status.displayName}?'),
          content: Text('${turf.turfName}\n\n$visibilityNote'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }

    List<int> renovationNets = <int>[];
    if (status == TurfStatus.renovation) {
      final selectedNets = await _showRenovationNetSelector(turf);
      if (selectedNets == null) {
        return;
      }
      if (selectedNets.isEmpty) {
        if (!mounted) return;
        showAppToast(
          this.context,
          'Select at least one net for under renovation',
          type: ToastType.warning,
        );
        return;
      }
      renovationNets = selectedNets;
    }

    setState(() {
      _pendingStatusUpdates.add(turf.turfId);
    });

    try {
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final success = await turfProvider.updateTurfStatus(
        turf.turfId,
        status,
        renovationNetNumbers: renovationNets,
      );

      if (!mounted) return;

      if (success) {
        await _refreshTurfs();
        if (!mounted) return;
        showAppToast(
          this.context,
          'Turf status updated to ${status.displayName}',
          type: ToastType.success,
        );
      } else {
        showAppToast(
          this.context,
          turfProvider.errorMessage ?? 'Failed to update turf status',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingStatusUpdates.remove(turf.turfId);
        });
      }
    }
  }

  Future<List<int>?> _showRenovationNetSelector(TurfModel turf) async {
    final selected = turf.renovationNetNumbers.isNotEmpty
        ? turf.renovationNetNumbers.toSet()
        : <int>{1};

    return showDialog<List<int>>(
      context: this.context,
      builder: (dialogContext) {
        final c = AppColors.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: c.surface,
              title: const Text('Select Nets Under Renovation'),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(turf.numberOfNets, (index) {
                      final netNumber = index + 1;
                      final isChecked = selected.contains(netNumber);
                      return CheckboxListTile(
                        value: isChecked,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Net $netNumber'),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) {
                          setStateDialog(() {
                            if (checked == true) {
                              selected.add(netNumber);
                            } else {
                              selected.remove(netNumber);
                            }
                          });
                        },
                      );
                    }),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final sorted = selected.toList()..sort();
                    Navigator.of(dialogContext).pop(sorted);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToEdit(BuildContext context, TurfModel turf) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTurfScreen(editTurf: turf),
      ),
    ).then((result) {
      if (!mounted) return;
      if (result == true) {
        // Refresh turfs after editing
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.currentUserId != null) {
          Provider.of<TurfProvider>(context, listen: false)
              .loadOwnerTurfs(authProvider.currentUserId!);
        }
      }
    });
  }

  Widget _buildTurfStatusBadge(TurfStatus status) {
    final c = AppColors.of(context);
    Color color;
    IconData icon;

    switch (status) {
      case TurfStatus.open:
        color = c.success;
        icon = Icons.check_circle;
        break;
      case TurfStatus.closed:
        color = c.error;
        icon = Icons.cancel;
        break;
      case TurfStatus.renovation:
        color = c.warning;
        icon = Icons.construction;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder),
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
    final c = AppColors.of(context);
    Color color;
    String text;

    switch (status) {
      case VerificationStatus.approved:
        color = c.success;
        text = 'Approved';
        break;
      case VerificationStatus.pending:
        color = c.warning;
        text = 'Pending';
        break;
      case VerificationStatus.rejected:
        color = c.error;
        text = 'Rejected';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}
