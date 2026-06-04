import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Blossom palette ──────────────────────────────────────────────────────────
const kCream = Color(0xFFFFFBF4);
const kSurface = Color(0xFFFFFFFF);
const kInk = Color(0xFF2A2440);
const kInkSoft = Color(0xFF6B6391);
const kInkMuted = Color(0xFF9C97B5);
const kPink = Color(0xFFFFA8C5);
const kPinkBg = Color(0xFFFFE3EE);
const kMint = Color(0xFF8AD0DA);
const kMintBg = Color(0xFFDFF2F4);
const kButter = Color(0xFFFFD96B);
const kButterBg = Color(0xFFFFF1C7);
const kLilac = Color(0xFFB69CE8);
const kLilacBg = Color(0xFFE8DEFA);
const kLineSoft = Color(0xFFE5E0EF);

// Legacy aliases — keep existing names so every file compiles without change
const kBgDark = kCream;
const kBgSecondary = kSurface;
const kBgTertiary = kLineSoft;
const kBorderColor = kInk;
const kAccentBlue = kLilac;
const kTextPrimary = kInk;
const kTextSecondary = kInkSoft;
const kTextMuted = kInkMuted;
const kSuccessGreen = Color(0xFF7DCE9B);
const kErrorRed = Color(0xFFFF8B8B);

// ── Typography helpers ────────────────────────────────────────────────────────
TextStyle kVt323(double size, {Color color = kInk, double letterSpacing = 0.5}) =>
    GoogleFonts.vt323(fontSize: size, color: color, letterSpacing: letterSpacing, height: 1.05);

TextStyle kSilkscreen(double size, {Color color = kInk, double letterSpacing = 0.6}) =>
    GoogleFonts.silkscreen(fontSize: size, color: color, letterSpacing: letterSpacing);

// ── Chunky card decoration ────────────────────────────────────────────────────
BoxDecoration kChunkyCard({
  Color bg = kSurface,
  double radius = 14,
  bool shadow = true,
  Color? borderColor,
  Color? shadowColor,
}) =>
    BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? kInk, width: 1.5),
      boxShadow: shadow
          ? [BoxShadow(color: shadowColor ?? kInk, offset: const Offset(3, 3), blurRadius: 0)]
          : [],
    );

// ── Theme ─────────────────────────────────────────────────────────────────────
ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: false);
  return base.copyWith(
    scaffoldBackgroundColor: kCream,
    colorScheme: const ColorScheme.light(
      primary: kLilac,
      secondary: kPink,
      surface: kSurface,
      error: kErrorRed,
      onPrimary: kInk,
      onSecondary: kInk,
      onSurface: kInk,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      bodyLarge: GoogleFonts.inter(color: kInk),
      bodyMedium: GoogleFonts.inter(color: kInkSoft),
      bodySmall: GoogleFonts.inter(color: kInkMuted),
      titleLarge: GoogleFonts.inter(color: kInk, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.inter(color: kInk, fontWeight: FontWeight.w500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kInk, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kLineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kInk, width: 1.5),
      ),
      hintStyle: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPink,
        foregroundColor: kInk,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kInk, width: 1.5),
        ),
        textStyle: GoogleFonts.silkscreen(fontSize: 12, letterSpacing: 0.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kInk, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.silkscreen(fontSize: 12, letterSpacing: 0.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kLilac,
        textStyle: GoogleFonts.inter(fontSize: 13),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kSurface),
    cardColor: kSurface,
    dividerColor: kLineSoft,
    iconTheme: const IconThemeData(color: kInkSoft),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: GoogleFonts.inter(color: kSurface, fontSize: 13),
    ),
  );
}
