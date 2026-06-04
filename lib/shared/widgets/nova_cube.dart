import 'package:flutter/material.dart';

// Pixel-art cube mascot. 16×16 grid, scales to any [size].
// Floats gently up/down by default; pass [animate: false] to disable.
//
// Grid key: K=ink  B=lilac(body)  L=lilacBg(top-highlight)
//           D=bodyDark  S=shine(white)  A=accent(pink)
class NovaCube extends StatefulWidget {
  const NovaCube({super.key, this.size = 64, this.animate = true});
  final double size;
  final bool animate;

  @override
  State<NovaCube> createState() => _NovaCubeState();
}

class _NovaCubeState extends State<NovaCube>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bob;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _bob = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CustomPaint(painter: _Painter()),
      );
    }
    return AnimatedBuilder(
      animation: _bob,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -4 * _bob.value),
        child: child,
      ),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CustomPaint(painter: _Painter()),
      ),
    );
  }
}

// ── Pixel painter ─────────────────────────────────────────────────────────────

class _Painter extends CustomPainter {
  const _Painter();

  static const _ink    = Color(0xFF2A2440);
  static const _body   = Color(0xFFB69CE8);
  static const _light  = Color(0xFFE8DEFA);
  static const _dark   = Color(0xFF8E76C9);
  static const _shine  = Color(0xFFFFFFFF);
  static const _accent = Color(0xFFFFA8C5);

  // Flat list of (x, y, colorIndex) triples.
  // colorIndex → [ink, body, light, dark, shine, accent]
  static const _p = <int>[
    // Sparkle above (accent)
    8,1,5,
    7,2,5, 8,2,5, 9,2,5,
    8,3,5,
    // Top edge
    4,4,0, 5,4,0, 6,4,0, 7,4,0, 8,4,0, 9,4,0, 10,4,0, 11,4,0,
    // Top face (light) with ink corners
    3,5,0,
    4,5,2, 5,5,2, 6,5,2, 7,5,2, 8,5,2, 9,5,2, 10,5,2, 11,5,2,
    12,5,0,
    // Row 6 — body with ink bevel
    2,6,0, 3,6,0,
    4,6,1, 5,6,1, 6,6,1, 7,6,1, 8,6,1, 9,6,1, 10,6,1, 11,6,1,
    12,6,0, 13,6,0,
    // Row 7
    2,7,0,
    3,7,1, 4,7,1, 5,7,1, 6,7,1, 7,7,1, 8,7,1, 9,7,1, 10,7,1, 11,7,1,
    12,7,3, 13,7,0,
    // Row 8 — eye whites
    2,8,0,
    3,8,1, 4,8,1, 5,8,4, 6,8,1, 7,8,1, 8,8,1, 9,8,1, 10,8,4, 11,8,1,
    12,8,3, 13,8,0,
    // Row 9 — pupils
    2,9,0,
    3,9,1, 4,9,1, 5,9,0, 6,9,1, 7,9,1, 8,9,1, 9,9,1, 10,9,0, 11,9,1,
    12,9,3, 13,9,0,
    // Row 10
    2,10,0,
    3,10,1, 4,10,1, 5,10,1, 6,10,1, 7,10,1, 8,10,1, 9,10,1, 10,10,1, 11,10,1,
    12,10,3, 13,10,0,
    // Row 11 — mouth
    2,11,0,
    3,11,1, 4,11,1, 5,11,1,
    6,11,0, 7,11,0, 8,11,0, 9,11,0,
    10,11,1, 11,11,1, 12,11,1,
    13,11,0,
    // Row 12
    2,12,0,
    3,12,1, 4,12,1, 5,12,1, 6,12,1, 7,12,1, 8,12,1, 9,12,1, 10,12,1, 11,12,1,
    12,12,3, 13,12,0,
    // Row 13 — bottom shadow
    2,13,0, 3,13,0,
    4,13,3, 5,13,3, 6,13,3, 7,13,3, 8,13,3, 9,13,3, 10,13,3, 11,13,3,
    12,13,0, 13,13,0,
    // Row 14 — bottom edge
    4,14,0, 5,14,0, 6,14,0, 7,14,0, 8,14,0, 9,14,0, 10,14,0, 11,14,0,
  ];

  static const _palette = [_ink, _body, _light, _dark, _shine, _accent];

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / 16;
    final paint = Paint();
    for (var i = 0; i < _p.length; i += 3) {
      paint.color = _palette[_p[i + 2]];
      canvas.drawRect(
        Rect.fromLTWH(_p[i] * px, _p[i + 1] * px, px, px),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Painter _) => false;
}
