import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How the Android navigation bar behaves while the app is in the foreground.
enum NavigationBarMode {
  /// Hidden until the user swipes from the bottom edge, then it slides over
  /// the interface.
  overlay('Overlay'),

  /// Hidden until the user swipes from the bottom edge; the interface moves
  /// up to leave room for the bar.
  push('Push content up'),

  /// Always visible below the interface.
  always('Always visible');

  const NavigationBarMode(this.label);

  final String label;

  static NavigationBarMode fromName(Object? name) {
    return switch (name) {
      'push' => NavigationBarMode.push,
      'always' => NavigationBarMode.always,
      _ => NavigationBarMode.overlay,
    };
  }
}

class SystemNavigationBar {
  SystemNavigationBar._();

  static const MethodChannel _channel = MethodChannel('roxum/system_ui');

  static final ValueNotifier<NavigationBarMode> mode =
      ValueNotifier(NavigationBarMode.overlay);

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Applies the navigation bar mode on Android. Flutter cannot express a
  /// visible status bar together with a hidden navigation bar that only
  /// appears on an edge swipe, so the host activity owns the system bars. On
  /// other platforms the caller keeps using the Flutter system chrome API.
  static Future<void> configure(
    NavigationBarMode value, {
    bool keepVisibleWithKeyboard = false,
  }) async {
    mode.value = value;
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('setNavigationBarMode', {
      'mode': value.name,
      'keepVisibleWithKeyboard': keepVisibleWithKeyboard,
    });
  }

  /// Tells the activity whether the keyboard is open, so it can keep the
  /// navigation bar visible while typing when that option is enabled.
  static Future<void> setKeyboardVisible(bool visible) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('setKeyboardVisible', {
      'visible': visible,
    });
  }

  /// Hides the navigation bar again after it was revealed by an edge swipe.
  static Future<void> hide() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('hideNavigationBar');
  }
}

/// Applies the bottom inset of the Android navigation bar to the interface.
///
/// In [NavigationBarMode.overlay] and [NavigationBarMode.always] the system
/// reports the inset and this widget does nothing. In
/// [NavigationBarMode.push] the bar is hidden by default but reports its inset
/// when the user reveals it, so the inset is animated here and the interface
/// moves up instead of being covered. The bar is hidden again after a short
/// delay so the interface returns to the full height.
class SystemNavigationBarInset extends StatefulWidget {
  const SystemNavigationBarInset({super.key, required this.child});

  final Widget child;

  @override
  State<SystemNavigationBarInset> createState() =>
      _SystemNavigationBarInsetState();
}

class _SystemNavigationBarInsetState extends State<SystemNavigationBarInset> {
  bool? _keyboardVisible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (visible == _keyboardVisible) return;
    _keyboardVisible = visible;
    unawaited(SystemNavigationBar.setKeyboardVisible(visible));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NavigationBarMode>(
      valueListenable: SystemNavigationBar.mode,
      builder: (context, mode, child) {
        if (mode != NavigationBarMode.push) return child!;
        return _PushContentInset(child: child!);
      },
      child: widget.child,
    );
  }
}

class _PushContentInset extends StatefulWidget {
  const _PushContentInset({required this.child});

  final Widget child;

  @override
  State<_PushContentInset> createState() => _PushContentInsetState();
}

class _PushContentInsetState extends State<_PushContentInset> {
  static const Duration _animationDuration = Duration(milliseconds: 250);
  static const Duration _autoHideDelay = Duration(seconds: 3);

  Timer? _autoHideTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (bottom <= 0) {
      _autoHideTimer?.cancel();
      _autoHideTimer = null;
      return;
    }
    _autoHideTimer ??= Timer(_autoHideDelay, _hideNavigationBar);
  }

  void _hideNavigationBar() {
    _autoHideTimer = null;
    unawaited(SystemNavigationBar.hide());
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: media.padding.bottom),
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      builder: (context, bottom, child) {
        return MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(bottom: bottom),
          ),
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}
