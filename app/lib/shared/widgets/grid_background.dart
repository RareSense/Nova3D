import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

class GridBackground extends StatelessWidget {
  const GridBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;

          return Stack(
            children: [
              // Dotted background
              Positioned.fill(child: CustomPaint(painter: _DotsPainter())),
              // Scattered sparkle decorations
              ..._kDecoItems.map((item) {
                final delayMs =
                    ((item.xFrac * 7 + item.yFrac * 13) * 2400).round().clamp(0, 2400);
                return Positioned(
                  left: item.xFrac * w - item.size / 2,
                  top: item.yFrac * h - item.size / 2,
                  child: _DecoWidget(
                    kind: item.kind,
                    color: item.color,
                    size: item.size,
                    rotDeg: item.rotDeg,
                    delay: Duration(milliseconds: delayMs),
                  ),
                );
              }),
              // Content
              child,
            ],
          );
        },
      );
}

// ── Decoration data ───────────────────────────────────────────────────────────

enum _DecoKind { sparkle, heart, star }

class _DecoItem {
  const _DecoItem({
    required this.xFrac,
    required this.yFrac,
    required this.kind,
    required this.color,
    this.size = 14.0,
    this.rotDeg = 0.0,
  });
  final double xFrac;
  final double yFrac;
  final _DecoKind kind;
  final Color color;
  final double size;
  final double rotDeg;
}

// Positions are fractions of the available width/height (edge-hugging, like the
// design's hand-placed decorations for the home artboard at ~1200×800).
const _kDecoItems = <_DecoItem>[
  _DecoItem(xFrac: 0.09, yFrac: 0.16, kind: _DecoKind.sparkle, color: kPink,   size: 16, rotDeg: -10),
  _DecoItem(xFrac: 0.91, yFrac: 0.14, kind: _DecoKind.star,    color: kButter, size: 16, rotDeg: 8),
  _DecoItem(xFrac: 0.05, yFrac: 0.45, kind: _DecoKind.sparkle, color: kLilac,  size: 14),
  _DecoItem(xFrac: 0.93, yFrac: 0.40, kind: _DecoKind.heart,   color: kPink,   size: 14),
  _DecoItem(xFrac: 0.08, yFrac: 0.77, kind: _DecoKind.sparkle, color: kMint,   size: 20, rotDeg: 15),
  _DecoItem(xFrac: 0.90, yFrac: 0.80, kind: _DecoKind.star,    color: kLilac,  size: 18, rotDeg: -8),
  _DecoItem(xFrac: 0.95, yFrac: 0.60, kind: _DecoKind.sparkle, color: kPink,   size: 12),
  _DecoItem(xFrac: 0.05, yFrac: 0.60, kind: _DecoKind.sparkle, color: kButter, size: 12, rotDeg: 20),
  _DecoItem(xFrac: 0.18, yFrac: 0.90, kind: _DecoKind.heart,   color: kLilac,  size: 12),
  _DecoItem(xFrac: 0.83, yFrac: 0.93, kind: _DecoKind.star,    color: kMint,   size: 13),
  _DecoItem(xFrac: 0.20, yFrac: 0.30, kind: _DecoKind.sparkle, color: kMint,   size: 11, rotDeg: 40),
  _DecoItem(xFrac: 0.80, yFrac: 0.29, kind: _DecoKind.sparkle, color: kPink,   size: 11, rotDeg: 18),
];

// ── Dots painter ──────────────────────────────────────────────────────────────
// Matches the design's "dots" pattern:
//   radial-gradient(circle, lineSoft 1.2px, transparent 1.2px) / 20px 20px

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kCream);
    const step = 20.0;
    const dotR = 1.2;
    final paint = Paint()
      ..color = kLineSoft
      ..style = PaintingStyle.fill;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), dotR, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter _) => false;
}

// ── Decoration widget ─────────────────────────────────────────────────────────
// Implements the three CSS keyframe animations from theme.jsx:
//   • nv-twinkle (sparkle) — 2.6 s: scale+rotate shrink+spin, opacity dip
//   • nv-heartbeat (heart) — 1.6 s: double-tap scale pulse
//   • nv-pop (star)        — 3.4 s: hold → vanish → snap back bigger

class _DecoWidget extends StatefulWidget {
  const _DecoWidget({
    required this.kind,
    required this.color,
    required this.size,
    required this.rotDeg,
    required this.delay,
  });
  final _DecoKind kind;
  final Color color;
  final double size;
  final double rotDeg;
  final Duration delay;

  @override
  State<_DecoWidget> createState() => _DecoWidgetState();
}

class _DecoWidgetState extends State<_DecoWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration());
    _buildAnimations();
    if (widget.delay == Duration.zero) {
      _ctrl.repeat();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.repeat();
      });
    }
  }

  Duration _duration() => switch (widget.kind) {
        _DecoKind.sparkle => const Duration(milliseconds: 2600),
        _DecoKind.heart   => const Duration(milliseconds: 1600),
        _DecoKind.star    => const Duration(milliseconds: 3400),
      };

  void _buildAnimations() {
    switch (widget.kind) {
      case _DecoKind.sparkle:
        // 0%→45%→55%→100%  scale: 1→0.35 (hold) →1
        // same intervals    rotate: 0→π (hold) →2π
        // same intervals    opacity: 1→0.55 (hold) →1
        _scale = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.35)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
          TweenSequenceItem(tween: Tween(begin: 0.35, end: 0.35), weight: 10),
          TweenSequenceItem(
            tween: Tween(begin: 0.35, end: 1.0)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
        ]).animate(_ctrl);
        _opacity = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.55)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 0.55, end: 0.55),
            weight: 10,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 0.55, end: 1.0)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
        ]).animate(_ctrl);
        _rotate = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(begin: 0.0, end: math.pi)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
          TweenSequenceItem(
            tween: Tween(begin: math.pi, end: math.pi),
            weight: 10,
          ),
          TweenSequenceItem(
            tween: Tween(begin: math.pi, end: math.pi * 2)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 45,
          ),
        ]).animate(_ctrl);

      case _DecoKind.heart:
        // 0%,55%,100%: 1  |  10%: 1.28  |  20%: 1  |  30%: 1.22  |  40%: 1
        _scale = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.00, end: 1.28), weight: 10),
          TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.00), weight: 10),
          TweenSequenceItem(tween: Tween(begin: 1.00, end: 1.22), weight: 10),
          TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.00), weight: 10),
          TweenSequenceItem(tween: Tween(begin: 1.00, end: 1.00), weight: 60),
        ]).animate(_ctrl);
        _opacity = Tween<double>(begin: 1.0, end: 1.0).animate(_ctrl);
        _rotate  = Tween<double>(begin: 0.0, end: 0.0).animate(_ctrl);

      case _DecoKind.star:
        // 0%–75%: hold  |  82%: vanish  |  88%: hold vanished  |
        // 93%: pop big  |  100%: settle
        _scale = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(begin: 1.00, end: 1.00),
            weight: 75,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 1.00, end: 0.00),
            weight: 7,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 0.00, end: 0.00),
            weight: 6,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 0.00, end: 1.40),
            weight: 5,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 1.40, end: 1.00),
            weight: 7,
          ),
        ]).animate(_ctrl);
        _opacity = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 75),
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 7),
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 6),
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
        ]).animate(_ctrl);
        _rotate = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 75),
          TweenSequenceItem(
            tween: Tween(begin: 0.0, end: -25 * math.pi / 180),
            weight: 13,
          ),
          TweenSequenceItem(
            tween: Tween(
              begin: -25 * math.pi / 180,
              end: 15 * math.pi / 180,
            ),
            weight: 5,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 15 * math.pi / 180, end: 0.0),
            weight: 7,
          ),
        ]).animate(_ctrl);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _glyph => switch (widget.kind) {
        _DecoKind.sparkle => '✦',
        _DecoKind.heart   => '♥',
        _DecoKind.star    => '★',
      };

  @override
  Widget build(BuildContext context) {
    final baseRot = widget.rotDeg * math.pi / 180;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.rotate(
        angle: baseRot + _rotate.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Opacity(
            opacity: _opacity.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
      ),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text(
            _glyph,
            style: TextStyle(
              color: widget.color,
              fontSize: widget.size * 0.9,
              height: 1,
              fontFamily: 'serif',
            ),
          ),
        ),
      ),
    );
  }
}
