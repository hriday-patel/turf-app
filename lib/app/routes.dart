import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_selection_screen.dart';
import '../features/auth/screens/owner_auth_screen.dart';
import '../features/auth/screens/player_auth_screen.dart';
import '../features/owner/screens/owner_dashboard_screen.dart';
import '../features/owner/screens/add_turf_screen.dart';
import '../features/owner/screens/my_turfs_screen.dart';
import '../features/owner/screens/turf_detail_screen.dart';
import '../features/owner/screens/slot_management_screen.dart';
import '../features/owner/screens/slot_booking_screen.dart';
import '../features/owner/screens/booking_management_screen.dart';
import '../features/owner/screens/booking_detail_screen.dart';
import '../features/owner/screens/manual_booking_screen.dart';
import '../features/owner/screens/verification_pending_screen.dart';

class AppRoutes {
  // Route observer for tracking navigation
  static final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
  
  // Route names
  static const String splash = '/';
  static const String loginSelection = '/login-selection';
  static const String ownerAuth = '/owner-auth';
  static const String ownerDashboard = '/owner-dashboard';
  static const String addTurf = '/add-turf';
  static const String myTurfs = '/my-turfs';
  static const String turfDetail = '/turf-detail';
  static const String slotManagement = '/slot-management';
  static const String slotBooking = '/slot-booking';
  static const String bookingManagement = '/booking-management';
  static const String bookingDetail = '/booking-detail';
  static const String manualBooking = '/manual-booking';
  static const String verificationPending = '/verification-pending';
  static const String playerAuth = '/player-auth';
  
  // Routes map
  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    loginSelection: (context) => const LoginSelectionScreen(),
    ownerAuth: (context) => const OwnerAuthScreen(),
    playerAuth: (context) => const PlayerAuthScreen(),
    ownerDashboard: (context) => const OwnerDashboardScreen(),
    addTurf: (context) => const AddTurfScreen(),
    myTurfs: (context) => const MyTurfsScreen(),
    verificationPending: (context) => const VerificationPendingScreen(),
    bookingManagement: (context) => const BookingManagementScreen(),
    slotBooking: (context) => const SlotBookingScreen(),
  };
  
  // For screens requiring arguments
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case turfDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => TurfDetailScreen(turfId: args['turfId']),
        );
      case slotManagement:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => SlotManagementScreen(turfId: args['turfId']),
        );
      case manualBooking:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => ManualBookingScreen(turfId: args['turfId']),
        );
      case bookingDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => BookingDetailScreen(bookingId: args['bookingId']),
        );
      default:
        return MaterialPageRoute(
          builder: (context) => const SplashScreen(),
        );
    }
  }
}

