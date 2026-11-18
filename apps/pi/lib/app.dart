import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pi_runtime/pi_runtime.dart';

import 'home_page.dart';
import 'icloud_sync.dart';

class PiApp extends StatefulWidget {
  const PiApp({required this.runtime, this.cloudSync, super.key});

  final PiRuntime runtime;
  final ICloudSyncService? cloudSync;

  @override
  State<PiApp> createState() => _PiAppState();
}

class _PiAppState extends State<PiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.runtime.reminders.reconcile());
    final cloudSync = widget.cloudSync;
    if (cloudSync != null) {
      unawaited(cloudSync.checkDailySchedule());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PiRuntimeScope(
    runtime: widget.runtime,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi',
      theme: _theme,
      home: const PiHomePage(),
    ),
  );
}

const _background = Color(0xFF0D0F17);
const _surface = Color(0xFF181A25);
const _surfaceHigh = Color(0xFF202330);
const _primary = Color(0xFFA99BFF);
const _onSurface = Color(0xFFF4F1FA);
const _muted = Color(0xFFA9A5B4);

final _scheme =
    ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.dark,
      surface: _surface,
    ).copyWith(
      primary: _primary,
      onPrimary: const Color(0xFF171128),
      secondary: const Color(0xFF7CCCF2),
      surface: _surface,
      onSurface: _onSurface,
      outline: const Color(0xFF454653),
      outlineVariant: const Color(0xFF2B2D39),
      error: const Color(0xFFFF8F91),
    );

final _theme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  colorScheme: _scheme,
  scaffoldBackgroundColor: _background,
  canvasColor: _background,
  splashFactory: InkSparkle.splashFactory,
  textTheme: ThemeData.dark().textTheme.copyWith(
    headlineSmall: const TextStyle(
      color: _onSurface,
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -.45,
    ),
    titleLarge: const TextStyle(
      color: _onSurface,
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -.2,
    ),
    titleMedium: const TextStyle(
      color: _onSurface,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: const TextStyle(color: _onSurface, fontSize: 16, height: 1.5),
    bodyMedium: const TextStyle(color: _muted, fontSize: 14, height: 1.5),
    bodySmall: const TextStyle(color: _muted, fontSize: 12, height: 1.45),
    labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: _background,
    foregroundColor: _onSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: _onSurface,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -.2,
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 68,
    backgroundColor: const Color(0xFF13151F),
    surfaceTintColor: Colors.transparent,
    indicatorColor: _primary.withValues(alpha: .16),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        size: 23,
        color: states.contains(WidgetState.selected) ? _primary : _muted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected) ? _onSurface : _muted,
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
      ),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: _surface,
    surfaceTintColor: Colors.transparent,
    modalBackgroundColor: _surface,
    modalBarrierColor: Color(0xB3000000),
    showDragHandle: true,
    dragHandleColor: Color(0xFF555765),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: _surface,
    surfaceTintColor: Colors.transparent,
    elevation: 24,
    shadowColor: Colors.black.withValues(alpha: .55),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    titleTextStyle: const TextStyle(
      color: _onSurface,
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3,
    ),
    contentTextStyle: const TextStyle(
      color: _muted,
      fontSize: 14,
      height: 1.55,
    ),
    actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _surfaceHigh,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    labelStyle: const TextStyle(color: _muted),
    floatingLabelStyle: const TextStyle(
      color: _primary,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: TextStyle(color: _muted.withValues(alpha: .65)),
    prefixIconColor: _muted,
    suffixIconColor: _muted,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF292C39)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFFF8F91)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: _onSurface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      side: const BorderSide(color: Color(0xFF343643)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: _primary,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: _muted,
      highlightColor: _primary.withValues(alpha: .12),
    ),
  ),
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    side: const BorderSide(color: Color(0xFF656776), width: 1.5),
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? _primary : null,
    ),
    checkColor: const WidgetStatePropertyAll(Color(0xFF171128)),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _onSurface
          : const Color(0xFF858693),
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _primary
          : const Color(0xFF343642),
    ),
    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: _surfaceHigh,
    selectedColor: _primary.withValues(alpha: .2),
    disabledColor: _surfaceHigh.withValues(alpha: .5),
    side: const BorderSide(color: Color(0xFF30323F)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    labelStyle: const TextStyle(color: _onSurface, fontSize: 13),
    secondaryLabelStyle: const TextStyle(
      color: Color(0xFFCFC8FF),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(56, 44)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _primary.withValues(alpha: .18)
            : _surfaceHigh,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _primary : _muted,
      ),
      side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFF333542))),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: _muted,
    textColor: _onSurface,
    titleTextStyle: TextStyle(
      color: _onSurface,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    subtitleTextStyle: TextStyle(color: _muted, fontSize: 12, height: 1.45),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF292B37),
    thickness: 1,
    space: 1,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: const Color(0xFF2A2C38),
    contentTextStyle: const TextStyle(color: _onSurface),
    behavior: SnackBarBehavior.floating,
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: _primary,
    linearTrackColor: Color(0xFF292B37),
  ),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  ),
);
