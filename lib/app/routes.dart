import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_selection_screen.dart';
import '../features/auth/screens/owner_auth_screen.dart';
import '../features/auth/screens/player_auth_screen.dart';
import '../features/player/screens/player_home_screen.dart';
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
import '../features/owner/screens/settings_screen.dart';
import '../features/owner/screens/analytics_screen.dart';

/// Centralized navigation registry for the FieldPass app.
///
/// Conventions:
///   * Static screens (no required arguments) live in [routes].
///   * Screens that need typed arguments are constructed in
///     [onGenerateRoute] using [_argString], which defensively coerces a
///     dynamic `Map` argument to a non-empty `String`.
///   * Unknown route names or invalid arguments fall through to
///     [_UnknownRouteScreen] instead of silently rerouting to splash, so
///     navigation bugs surface immediately during development.
///   * [routeObserver] is exposed for screens that need to react to route
///     transitions (e.g. refreshing data on `didPopNext`).
class AppRoutes {
  // Route observer for tracking navigation
  static final RouteObserver<PageRoute> routeObserver =
      RouteObserver<PageRoute>();

  /// Phase 6 Iter 1 (EDGE-04): global navigator key.
  ///
  /// Lets non-widget code (push-notification handlers, background callbacks,
  /// deep-link handlers added later) navigate without needing a [BuildContext].
  /// Wired into [MaterialApp.navigatorKey] in `app.dart`.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Phase 6 Iter 1 (EDGE-01): global double-tap guard.
  ///
  /// Wired into [MaterialApp.navigatorObservers]. Detects when the same
  /// route name is pushed twice within [_duplicatePushCooldown] and removes
  /// the duplicate, so an impatient double-tap on a button does not stack
  /// two copies of the same screen on the navigator.
  static final NavigatorObserver duplicatePushGuard = _DuplicatePushGuard();

  // Route names
  static const String splash = '/';
  static const String loginSelection = '/login-selection';
  static const String ownerAuth = '/owner-auth';
  static const String ownerDashboard = '/owner-dashboard';
  static const String playerHome = '/player-home';
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
  static const String settings = '/settings';
  static const String analytics = '/analytics';

  // Routes map
  static final Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    loginSelection: (context) => const LoginSelectionScreen(),
    ownerAuth: (context) => const OwnerAuthScreen(),
    playerAuth: (context) => const PlayerAuthScreen(),
    playerHome: (context) => const PlayerHomeScreen(),
    ownerDashboard: (context) => const OwnerDashboardScreen(),
    addTurf: (context) => const AddTurfScreen(),
    myTurfs: (context) => const MyTurfsScreen(),
    verificationPending: (context) => const VerificationPendingScreen(),
    bookingManagement: (context) => const BookingManagementScreen(),
    slotBooking: (context) => const SlotBookingScreen(),
    settings: (context) => const SettingsScreen(),
    analytics: (context) => const AnalyticsScreen(),
  };

  /// Phase 6 Iter 1 (CLEAN-01): strict route-argument extraction.
  ///
  /// Returns the argument only if it is a non-empty `String`. Numbers, maps,
  /// or other shapes return `null`, causing [_unknownRoute] to fire so the
  /// programming mistake surfaces immediately during testing instead of
  /// being silently coerced into a garbage ID that the backend later rejects.
  static String? _argString(Object? arguments, String key) {
    if (arguments is! Map) return null;
    final value = arguments[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// Detects whether a route name is actually an OAuth deep-link callback
  /// being routed through Flutter's Navigator.
  ///
  /// When Google OAuth completes, Android delivers the deep link
  /// `com.fieldpass.business://login-callback?code=<UUID>` to the app and
  /// Flutter's engine feeds the URL into Navigator as the initial route name
  /// (e.g. `/?code=<UUID>` or `/login-callback?code=<UUID>`). Without this
  /// guard, [onGenerateRoute] would treat that as an unknown route and show
  /// the "Page not found" screen even though Supabase has already consumed
  /// the `code` query param via `detectSessionInUri: true`.
  ///
  /// Returning `true` here causes [onGenerateRoute] to route to the splash
  /// screen instead, where `checkAuthState()` picks up the freshly-created
  /// Supabase session and continues the normal auth flow.
  static bool _isOAuthCallbackRoute(String? name) {
    if (name == null || name.isEmpty) return false;
    // Common shapes we have observed:
    //   "/?code=..."           (Flutter web / some Android builds)
    //   "/login-callback?..."  (deep-link host preserved)
    //   "/?error=..."          (OAuth error redirect)
    //   any path containing a `code=` or `error=` query param.
    if (name.contains('code=') || name.contains('error=')) return true;
    if (name.startsWith('/login-callback')) return true;
    return false;
  }

  // For screens requiring arguments
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // Phase Auth-Triage Iter 1 (AUTH-01): swallow Google OAuth deep-link
    // callbacks that Flutter routes through Navigator as `/?code=<UUID>`.
    // Supabase has already consumed the `code` via `detectSessionInUri: true`
    // by the time this fires; we just need to land on splash so
    // `checkAuthState()` runs against the new session.
    if (_isOAuthCallbackRoute(settings.name)) {
      debugPrint(
        '[AppRoutes] OAuth callback intercepted: ${settings.name} '
        '-> routing to splash',
      );
      return MaterialPageRoute(
        builder: (context) => const SplashScreen(),
        settings: const RouteSettings(name: splash),
      );
    }
    switch (settings.name) {
      case turfDetail:
        final turfId = _argString(settings.arguments, 'turfId');
        if (turfId == null) return _unknownRoute(settings);
        return MaterialPageRoute(
          builder: (context) => TurfDetailScreen(turfId: turfId),
          settings: settings,
        );
      case slotManagement:
        final turfId = _argString(settings.arguments, 'turfId');
        if (turfId == null) return _unknownRoute(settings);
        return MaterialPageRoute(
          builder: (context) => SlotManagementScreen(turfId: turfId),
          settings: settings,
        );
      case manualBooking:
        final turfId = _argString(settings.arguments, 'turfId');
        if (turfId == null) return _unknownRoute(settings);
        return MaterialPageRoute(
          builder: (context) => ManualBookingScreen(turfId: turfId),
          settings: settings,
        );
      case bookingDetail:
        final bookingId = _argString(settings.arguments, 'bookingId');
        if (bookingId == null) return _unknownRoute(settings);
        return MaterialPageRoute(
          builder: (context) => BookingDetailScreen(bookingId: bookingId),
          settings: settings,
        );
      default:
        return _unknownRoute(settings);
    }
  }

  static Route<dynamic> _unknownRoute(RouteSettings settings) {
    debugPrint(
      '[AppRoutes] Unknown or invalid route: ${settings.name} '
      'args=${settings.arguments}',
    );
    return MaterialPageRoute(
      builder: (context) => _UnknownRouteScreen(routeName: settings.name),
      settings: settings,
    );
  }
}

/// Fallback screen shown when [AppRoutes.onGenerateRoute] receives an
/// unknown route name or invalid arguments. Provides a clear error message
/// and a way back to the splash screen.
class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                routeName == null
                    ? 'The requested page could not be found.'
                    : 'The requested page "$routeName" could not be found.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                // Phase 6 Iter 1 (Q1/EDGE-03): jump straight to the login
                // picker rather than re-entering the 1.2s splash auth dance.
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.loginSelection,
                  (_) => false,
                ),
                child: const Text('Back to start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase 6 Iter 1 (EDGE-01): cooldown for [_DuplicatePushGuard].
const Duration _duplicatePushCooldown = Duration(milliseconds: 500);

/// Phase 6 Iter 1 (EDGE-01): swallows accidental double-pushes of the same
/// named route within [_duplicatePushCooldown]. Anonymous routes (those
/// without a name, e.g. raw `MaterialPageRoute` push from a dialog) are
/// ignored so this guard cannot interfere with bottom sheets / dialogs.
class _DuplicatePushGuard extends NavigatorObserver {
  String? _lastRouteName;
  DateTime _lastPushTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name == null) return; // anonymous (dialogs, bottom sheets) — ignore.
    final now = DateTime.now();
    if (name == _lastRouteName &&
        now.difference(_lastPushTime) < _duplicatePushCooldown) {
      // Duplicate within cooldown — schedule removal after the current frame
      // so we do not fight the navigator mid-transition.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navigator;
        if (nav == null) return;
        try {
          nav.removeRoute(route);
        } catch (e) {
          debugPrint('[AppRoutes] duplicate-push removal failed: $e');
        }
      });
      return;
    }
    _lastRouteName = name;
    _lastPushTime = now;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route.settings.name == _lastRouteName) {
      _lastRouteName = null;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route.settings.name == _lastRouteName) {
      _lastRouteName = null;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _lastRouteName = newRoute?.settings.name;
    _lastPushTime = DateTime.now();
  }
}
