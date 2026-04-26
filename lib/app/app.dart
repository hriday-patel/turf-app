import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/theme_provider.dart';
import '../core/constants/strings.dart';
import 'routes.dart';

/// Root [MaterialApp] for the FieldPass turf-booking application.
///
/// Responsibilities:
///   * Provides global theming (light/dark) driven by [ThemeProvider].
///   * Wires the navigator with [AppRoutes.routes] (static screens) and
///     [AppRoutes.onGenerateRoute] (screens requiring arguments).
///   * Installs system UI overlay style (status / nav bars) declaratively via
///     [AnnotatedRegion] so it tracks theme changes without imperative calls
///     on every rebuild.
///   * Clamps text scale to a sane range so glassmorphic layouts do not break
///     under extreme accessibility scaling.
class TurfApp extends StatelessWidget {
  const TurfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final isDark = themeProvider.isDarkMode;
        // Phase 6 Iter 2 (Q1/EDGE-01): make the Android system navigation bar
        // transparent so it blends with whatever screen is showing instead of
        // painting a fixed band against potentially mismatched content.
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            navigatorKey: AppRoutes.navigatorKey,
            initialRoute: AppRoutes.splash,
            routes: AppRoutes.routes,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            navigatorObservers: [
              AppRoutes.routeObserver,
              AppRoutes.duplicatePushGuard,
            ],
            builder: (context, child) {
              // Phase 6 Iter 2 (Q5/CLEAN-01): MaterialApp always supplies a
              // non-null child here; the previous SizedBox.shrink fallback
              // was dead-defensive. Assert and pass through directly.
              assert(
                  child != null, 'MaterialApp builder child must be non-null');
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.30,
                  ),
                ),
                child: child!,
              );
            },
          ),
        );
      },
    );
  }
}
