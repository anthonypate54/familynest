import 'package:flutter/material.dart';

/// Custom page route with a simple slide transition
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SlidePageRoute({required this.page, RouteSettings? settings})
    : super(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Simple slide from right
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: Curves.easeInOut));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      );
}

/// Extension on BuildContext to provide easy navigation with custom transitions
extension NavigatorExtension on BuildContext {
  /// Push a new page with slide transition
  Future<T?> slideToPage<T extends Object?>({
    required Widget page,
    String? routeName,
    Object? arguments,
  }) {
    return Navigator.of(this).push(
      SlidePageRoute<T>(
        page: page,
        settings: RouteSettings(name: routeName, arguments: arguments),
      ),
    );
  }

  /// Push replacement with slide transition
  Future<T?> slideToReplacementPage<T extends Object?, TO extends Object?>({
    required Widget page,
    String? routeName,
    Object? arguments,
  }) {
    return Navigator.of(this).pushReplacement(
      SlidePageRoute<T>(
        page: page,
        settings: RouteSettings(name: routeName, arguments: arguments),
      ),
    );
  }

  /// Push and remove until with slide transition
  Future<T?> slideAndRemoveUntil<T extends Object?>({
    required Widget page,
    required RoutePredicate predicate,
    String? routeName,
    Object? arguments,
  }) {
    return Navigator.of(this).pushAndRemoveUntil(
      SlidePageRoute<T>(
        page: page,
        settings: RouteSettings(name: routeName, arguments: arguments),
      ),
      predicate,
    );
  }
}

/// Wrap the default MaterialPageRoute with SlidePageRoute
/// This is used to replace standard Navigator calls throughout the app
Route<T> slidePageRoute<T>({required Widget page, RouteSettings? settings}) {
  return SlidePageRoute<T>(page: page, settings: settings);
}

/// Function to override the default Navigator.push
Future<T?> slidePush<T extends Object?>(
  BuildContext context,
  Widget page, {
  String? routeName,
  Object? arguments,
}) {
  return Navigator.of(context).push(
    SlidePageRoute<T>(
      page: page,
      settings: RouteSettings(name: routeName, arguments: arguments),
    ),
  );
}

/// Function to override the default Navigator.pushReplacement
Future<T?> slidePushReplacement<T extends Object?, TO extends Object?>(
  BuildContext context,
  Widget page, {
  String? routeName,
  Object? arguments,
  TO? result,
}) {
  return Navigator.of(context).pushReplacement(
    SlidePageRoute<T>(
      page: page,
      settings: RouteSettings(name: routeName, arguments: arguments),
    ),
    result: result,
  );
}

/// Function to override the default Navigator.pushAndRemoveUntil
Future<T?> slidePushAndRemoveUntil<T extends Object?>(
  BuildContext context,
  Widget page,
  RoutePredicate predicate, {
  String? routeName,
  Object? arguments,
}) {
  return Navigator.of(context).pushAndRemoveUntil(
    SlidePageRoute<T>(
      page: page,
      settings: RouteSettings(name: routeName, arguments: arguments),
    ),
    predicate,
  );
}
