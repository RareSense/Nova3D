import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';

class SuggestionPills extends StatelessWidget {
  const SuggestionPills({super.key, required this.onSelect});
  final void Function(String) onSelect;

  static const _suggestions = [
    ('A modern chair with wooden legs', kPinkBg),
    ('A low-poly mountain landscape', kMintBg),
    ('A sci-fi space helmet', kLilacBg),
    ('A medieval stone castle tower', kButterBg),
    ('A futuristic car concept', kPinkBg),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _suggestions.map((entry) {
          final (text, bg) = entry;
          return _Pill(
            text: text,
            bg: bg,
            onTap: () => onSelect(text),
          );
        }).toList(),
      );
}

class _Pill extends StatefulWidget {
  const _Pill({required this.text, required this.bg, required this.onTap});
  final String text;
  final Color bg;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(
              _pressed ? 2 : 0, _pressed ? 2 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: widget.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: _pressed
                ? []
                : const [
                    BoxShadow(
                        color: kInk, offset: Offset(2, 2), blurRadius: 0)
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✦',
                  style: TextStyle(color: kInkSoft, fontSize: 10)),
              const SizedBox(width: 6),
              Text(
                widget.text,
                style: GoogleFonts.inter(
                    color: kInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
}
