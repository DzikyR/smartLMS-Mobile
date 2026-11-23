import 'package:flutter/material.dart';

import 'site.dart';

/// Token warna web (src/app/globals.css, dikonversi dari oklch). Primary/secondary/accent/background
/// dapat ditimpa dari Tampilan Situs — sama seperti themeVars() di web.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.primary,
    required this.onPrimary,
    required this.primaryDeep,
    required this.background,
    required this.foreground,
    required this.card,
    required this.secondary,
    required this.onSecondary,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.destructive,
    required this.tints,
  });

  final Color primary, onPrimary, primaryDeep, background, foreground, card, secondary, onSecondary, muted, mutedForeground, border, destructive;

  /// violet / orange / green / sky / rose → (latar, teks)
  final Map<String, (Color, Color)> tints;

  (Color, Color) tint(String name) => tints[name] ?? tints['violet']!;

  static Color _hex(String? v, Color fallback) {
    if (v == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return fallback;
    return Color(int.parse('ff${v.substring(1)}', radix: 16));
  }

  static double _lum(Color c) => c.computeLuminance();
  static double _contrast(Color a, Color b) {
    final x = _lum(a), y = _lum(b);
    return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
  }

  /// Teks di atas warna: kandidat pertama yang kontrasnya ≥ 4,5 (sama dengan pickForeground di web).
  static Color _fg(Color bg, List<Color> candidates) => candidates.firstWhere((c) => _contrast(bg, c) >= 4.5, orElse: () => candidates.reduce((a, b) => _contrast(bg, a) >= _contrast(bg, b) ? a : b));

  static const _ink = Color(0xFF15131F);

  factory Palette.of(Brightness brightness, SiteConfig site) {
    final light = brightness == Brightness.light;
    final custom = light ? site.light : site.dark;
    final primary = _hex(custom['primary'], light ? const Color(0xFF5B4FE9) : const Color(0xFF8A7EF0));
    final secondary = _hex(custom['secondary'], light ? const Color(0xFFEEEDFA) : const Color(0xFF2B2A3F));
    final background = _hex(custom['background'], light ? const Color(0xFFF5F5FB) : const Color(0xFF16141F));
    final foreground = light ? const Color(0xFF161726) : const Color(0xFFF1F1F5);
    return Palette(
      primary: primary,
      onPrimary: _fg(primary, [Colors.white, _ink]),
      primaryDeep: Color.lerp(primary, Colors.black, 0.2)!,
      background: background,
      foreground: foreground,
      card: light ? Colors.white : const Color(0xFF181926),
      secondary: secondary,
      onSecondary: _fg(secondary, light ? [const Color(0xFF353179), foreground, _ink] : [const Color(0xFFDBDBF8), foreground, Colors.white]),
      muted: light ? const Color(0xFFF3F3F9) : const Color(0xFF212330),
      mutedForeground: light ? const Color(0xFF6E7080) : const Color(0xFFA2A3B1),
      border: light ? const Color(0xFFE5E5ED) : const Color(0x17FFFFFF),
      destructive: light ? const Color(0xFFE6293F) : const Color(0xFFFF6367),
      tints: light
          ? const {
              'violet': (Color(0xFFEBECFF), Color(0xFF5645D5)),
              'orange': (Color(0xFFFFEDD6), Color(0xFFD35F00)),
              'green': (Color(0xFFDAFBEB), Color(0xFF008760)),
              'sky': (Color(0xFFDFF6FF), Color(0xFF0079B5)),
              'rose': (Color(0xFFFFEAED), Color(0xFFD63053)),
            }
          : const {
              'violet': (Color(0xFF282850), Color(0xFFBDBBFF)),
              'orange': (Color(0xFF4A2A12), Color(0xFFFFBF7F)),
              'green': (Color(0xFF13382A), Color(0xFF82D9B4)),
              'sky': (Color(0xFF133446), Color(0xFF94D0F4)),
              'rose': (Color(0xFF4A2229), Color(0xFFF6B0B9)),
            },
    );
  }

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => other is Palette && t >= 0.5 ? other : this;
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// Radius web: --radius 0.75rem → rounded-xl ≈ 17, rounded-2xl ≈ 22.
const kRadius = 12.0;
const kRadiusXl = 17.0;
const kRadius2xl = 22.0;

/// Font web Plus Jakarta Sans dibundel di assets/fonts (tersedia walau offline).
ThemeData buildTheme(Brightness brightness, SiteConfig site) {
  final p = Palette.of(brightness, site);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    error: p.destructive,
    onError: Colors.white,
    surface: p.card,
    onSurface: p.foreground,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.background,
    surfaceContainer: p.muted,
    surfaceContainerHigh: p.muted,
    surfaceContainerHighest: p.muted,
    onSurfaceVariant: p.mutedForeground,
    outline: p.border,
    outlineVariant: p.border,
    primaryContainer: p.tint('violet').$1,
    onPrimaryContainer: p.tint('violet').$2,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness, fontFamily: 'PlusJakartaSans');
  final text = base.textTheme.apply(bodyColor: p.foreground, displayColor: p.foreground);
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(kRadiusXl),
    borderSide: BorderSide(color: p.border),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    textTheme: text,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    dividerTheme: DividerThemeData(color: p.border, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: BorderSide(color: p.primary, width: 1.6)),
      errorBorder: field.copyWith(borderSide: BorderSide(color: p.destructive)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size(48, 48),
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusXl)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.foreground,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusXl)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.card, shape: const RoundedRectangleBorder()),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius2xl)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, showDragHandle: true),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusXl)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.secondary),
  );
}
