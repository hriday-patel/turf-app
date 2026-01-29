import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/owner/providers/turf_provider.dart';
import '../../features/owner/providers/booking_provider.dart';

/// Global Refresh Service
/// Provides centralized data refresh functionality across the app
class RefreshService {
  static RefreshService? _instance;
  
  RefreshService._();
  
  static RefreshService get instance {
    _instance ??= RefreshService._();
    return _instance!;
  }

  /// Refresh all owner data (turfs and bookings)
  static void refreshOwnerData(BuildContext context) {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final bookingProvider = Provider.of<BookingProvider>(context, listen: false);

      if (authProvider.currentUserId != null) {
        debugPrint('RefreshService: Refreshing owner data...');
        turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
        
        // Refresh bookings after a small delay to ensure turfs are loaded
        Future.delayed(const Duration(milliseconds: 300), () {
          if (turfProvider.turfIds.isNotEmpty) {
            bookingProvider.loadTodaysBookings(turfProvider.turfIds);
            bookingProvider.loadPendingPayments(turfProvider.turfIds);
          }
        });
      }
    } catch (e) {
      debugPrint('RefreshService: Error refreshing data: $e');
    }
  }

  /// Refresh just turfs
  static void refreshTurfs(BuildContext context) {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);

      if (authProvider.currentUserId != null) {
        debugPrint('RefreshService: Refreshing turfs...');
        turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
      }
    } catch (e) {
      debugPrint('RefreshService: Error refreshing turfs: $e');
    }
  }

  /// Refresh bookings for given turf IDs
  static void refreshBookings(BuildContext context, List<String> turfIds) {
    try {
      final bookingProvider = Provider.of<BookingProvider>(context, listen: false);

      if (turfIds.isNotEmpty) {
        debugPrint('RefreshService: Refreshing bookings...');
        bookingProvider.loadTodaysBookings(turfIds);
        bookingProvider.loadPendingPayments(turfIds);
      }
    } catch (e) {
      debugPrint('RefreshService: Error refreshing bookings: $e');
    }
  }
}

/// Mixin to add automatic refresh capability to StatefulWidget screens
/// Usage: 
///   class _MyScreenState extends State<MyScreen> with AutoRefreshMixin<MyScreen> {
///     @override
///     void onScreenVisible() {
///       RefreshService.refreshOwnerData(context);
///     }
///   }
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> implements RouteAware {
  RouteObserver<PageRoute>? _routeObserver;

  /// Override this to define what happens when screen becomes visible
  void onScreenVisible() {
    // Default: refresh owner data
    RefreshService.refreshOwnerData(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToRouteObserver();
  }

  void _subscribeToRouteObserver() {
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      // Get route observer from the navigator
      final navigator = Navigator.of(context);
      try {
        // Try to find route observer
        _routeObserver = navigator.widget.observers
            .whereType<RouteObserver<PageRoute>>()
            .firstOrNull;
        _routeObserver?.subscribe(this, route);
      } catch (e) {
        debugPrint('AutoRefreshMixin: Could not subscribe to route observer');
      }
    }
  }

  @override
  void dispose() {
    _routeObserver?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when returning to this screen from another screen
    debugPrint('AutoRefreshMixin: didPopNext - ${T.toString()}');
    onScreenVisible();
  }

  @override
  void didPush() {
    // Called when this screen is pushed onto the navigator
    debugPrint('AutoRefreshMixin: didPush - ${T.toString()}');
  }

  @override
  void didPop() {
    // Called when this screen is popped
    debugPrint('AutoRefreshMixin: didPop - ${T.toString()}');
  }

  @override
  void didPushNext() {
    // Called when a new screen is pushed on top of this one
    debugPrint('AutoRefreshMixin: didPushNext - ${T.toString()}');
  }
}
