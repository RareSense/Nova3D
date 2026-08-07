import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

class GenerationProgressCard extends StatefulWidget {
  const GenerationProgressCard({
    super.key,
    required this.statusText,
    this.title = 'generating',
    this.modelLabel,
    this.progress,
    this.progressStep,
    this.progressTotalSteps,
    this.stageLabel,
  });
  final String statusText;

  /// Header verb, e.g. 'generating' or 'texturing'.
  final String title;

  /// Real model/engine label shown in the toolbar. Hidden when null/empty —
  /// never a hardcoded placeholder.
  final String? modelLabel;

  /// GraphFlow-derived stage progress. Null/zero is an honest starting state;
  /// this widget never advances progress based on elapsed time.
  final double? progress;
  final int? progressStep;
  final int? progressTotalSteps;
  final String? stageLabel;

  @override
  State<GenerationProgressCard> createState() => _GenerationProgressCardState();
}

class _GenerationProgressCardState extends State<GenerationProgressCard>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _bobCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _heartCtrl;
  late final List<AnimationController> _vertCtrls;
  late final List<AnimationController> _sparkCtrls;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _bobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _vertCtrls = List.generate(8, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });

    const delays = [0, 400, 900, 1300, 1800, 600, 1500, 2100];
    _sparkCtrls = List.generate(8, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      );
      Future.delayed(Duration(milliseconds: delays[i]), () {
        if (mounted) c.repeat();
      });
      return c;
    });
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _bobCtrl.dispose();
    _scanCtrl.dispose();
    _heartCtrl.dispose();
    for (final c in _vertCtrls) {
      c.dispose();
    }
    for (final c in _sparkCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The card runs many looping animations + a per-frame CustomPaint. Isolate
    // its repaints so they don't invalidate the whole chat/app layer each frame
    // (which stuttered scrolling everywhere while a run was in progress).
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kBubbleMaxWidth),
        child: SizedBox(
          height: kViewerDefaultHeight,
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kInk, width: 1.5),
              boxShadow: const [
                BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                _buildTitleStrip(),
                Expanded(
                  child: _Viewport(
                    spinCtrl: _spinCtrl,
                    bobCtrl: _bobCtrl,
                    scanCtrl: _scanCtrl,
                    heartCtrl: _heartCtrl,
                    vertCtrls: _vertCtrls,
                    sparkCtrls: _sparkCtrls,
                    statusText: widget.statusText,
                    stageLabel: widget.stageLabel,
                    progressStep: widget.progressStep,
                    progressTotalSteps: widget.progressTotalSteps,
                  ),
                ),
                _buildToolbar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleStrip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: const BoxDecoration(
      color: kLineSoft,
      border: Border(bottom: BorderSide(color: kInk, width: 1.5)),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(12),
      ),
    ),
    child: Row(
      children: [
        Text('${widget.title}...', style: kSilkscreen(9, color: kInkSoft)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: kPinkBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: const [
              BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
            ],
          ),
          child: Text('● WORKING', style: kSilkscreen(8, color: kInk)),
        ),
      ],
    ),
  );

  Widget _buildToolbar() {
    final progress = (widget.progress ?? 0).clamp(0.0, 0.99).toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(top: BorderSide(color: kLineSoft, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '✦',
                style: TextStyle(color: kButter, fontSize: 10, height: 1),
              ),
              const SizedBox(width: 6),
              Text(
                widget.title.toUpperCase(),
                style: kSilkscreen(9, color: kInkSoft),
              ),
              const Spacer(),
              if ((widget.modelLabel ?? '').isNotEmpty)
                Text(
                  widget.modelLabel!,
                  style: kSilkscreen(9, color: kInkMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kInk, width: 1.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (_, value, child) => FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: child,
              ),
              child: const CustomPaint(painter: _StripesPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Viewport ──────────────────────────────────────────────────────────────────

class _Viewport extends StatelessWidget {
  const _Viewport({
    required this.spinCtrl,
    required this.bobCtrl,
    required this.scanCtrl,
    required this.heartCtrl,
    required this.vertCtrls,
    required this.sparkCtrls,
    required this.statusText,
    required this.stageLabel,
    required this.progressStep,
    required this.progressTotalSteps,
  });

  final AnimationController spinCtrl;
  final AnimationController bobCtrl;
  final AnimationController scanCtrl;
  final AnimationController heartCtrl;
  final List<AnimationController> vertCtrls;
  final List<AnimationController> sparkCtrls;
  final String statusText;
  final String? stageLabel;
  final int? progressStep;
  final int? progressTotalSteps;

  static final _sparkData = [
    (xFrac: 0.13, yFrac: 0.14, size: 16.0, color: kPink),
    (xFrac: 0.97, yFrac: 0.21, size: 12.0, color: kButter),
    (xFrac: 0.18, yFrac: 0.77, size: 12.0, color: kMint),
    (xFrac: 0.90, yFrac: 0.84, size: 18.0, color: kLilac),
    (xFrac: 0.50, yFrac: 0.11, size: 10.0, color: kMint),
    (xFrac: 0.57, yFrac: 0.95, size: 10.0, color: kPink),
    (xFrac: 0.08, yFrac: 0.46, size: 10.0, color: kButter),
    (xFrac: 0.97, yFrac: 0.53, size: 10.0, color: kPink),
  ];

  static const _vertColors = [
    kPink,
    kLilac,
    kMint,
    kButter,
    kPink,
    kLilac,
    kMint,
    kButter,
  ];

  static double _sparkScale(double t) {
    if (t < 0.2) return t / 0.2;
    if (t < 0.6) return 1.0 + (t - 0.2) / 0.4 * 0.1;
    if (t < 0.8) return 1.1 * (1.0 - (t - 0.6) / 0.2);
    return 0.0;
  }

  static double _sparkOpacity(double t) {
    if (t < 0.2) return t / 0.2;
    if (t < 0.6) return 1.0 - (t - 0.2) / 0.4 * 0.1;
    if (t < 0.8) return 0.9 * (1.0 - (t - 0.6) / 0.2);
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final headline = (stageLabel ?? '').trim().isNotEmpty
        ? stageLabel!.trim()
        : (statusText.trim().isNotEmpty ? statusText.trim() : 'Starting…');
    final showDetail =
        statusText.trim().isNotEmpty && statusText.trim() != headline;
    final hasStep =
        (progressStep ?? 0) > 0 &&
        (progressTotalSteps ?? 0) >= (progressStep ?? 0);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 1. Gradient background
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [kLilacBg, kPinkBg, kButterBg],
                      stops: [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. Grid floor (perspective lines)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: math.min(110.0, h * 0.42),
                child: Opacity(
                  opacity: 0.4,
                  child: CustomPaint(painter: _GridFloorPainter()),
                ),
              ),

              // 3. Sparkles (static positions, animated scale/opacity)
              ...List.generate(_sparkData.length, (i) {
                final s = _sparkData[i];
                final left = (s.xFrac * w - s.size / 2).clamp(
                  0.0,
                  math.max<double>(0.0, w - s.size),
                );
                final top = (s.yFrac * h - s.size / 2).clamp(
                  0.0,
                  math.max<double>(0.0, h - s.size),
                );
                return Positioned(
                  left: left,
                  top: top,
                  child: AnimatedBuilder(
                    animation: sparkCtrls[i],
                    builder: (_, child) {
                      final t = sparkCtrls[i].value;
                      return Transform.scale(
                        scale: _sparkScale(t),
                        child: Opacity(
                          opacity: _sparkOpacity(t).clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      '✦',
                      style: TextStyle(
                        color: s.color,
                        fontSize: s.size * 0.9,
                        height: 1,
                      ),
                    ),
                  ),
                );
              }),

              // 4. Scan line (sweeps top to bottom)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: scanCtrl,
                  builder: (_, child) {
                    final t = scanCtrl.value;
                    final y = -12.0 + (h + 24) * t;
                    final opacity = t < 0.1
                        ? t / 0.1
                        : (t > 0.9 ? (1.0 - t) / 0.1 : 1.0);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: w * 0.2,
                          right: w * 0.2,
                          top: y,
                          height: 1.5,
                          child: Opacity(
                            opacity: opacity.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                      ],
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.transparent,
                          kLilac,
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: kLilac.withValues(alpha: 0.7),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 5. Wireframe cube (bob + spin + vertex glow)
              Positioned.fill(
                child: Center(
                  child: AnimatedBuilder(
                    animation: bobCtrl,
                    builder: (_, child) {
                      final bobT = CurvedAnimation(
                        parent: bobCtrl,
                        curve: Curves.easeInOut,
                      ).value;
                      return Transform.translate(
                        offset: Offset(0, -6 * bobT),
                        child: child,
                      );
                    },
                    child: AnimatedBuilder(
                      animation: spinCtrl,
                      builder: (_, child) => Transform.rotate(
                        angle: spinCtrl.value * 2 * math.pi,
                        child: child,
                      ),
                      child: SizedBox(
                        width: 180,
                        height: 180,
                        child: AnimatedBuilder(
                          animation: Listenable.merge(vertCtrls),
                          builder: (_, _) => CustomPaint(
                            painter: _CubePainter(
                              vertexValues: vertCtrls
                                  .map((c) => c.value)
                                  .toList(),
                              vertexColors: _vertColors,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 6. REC badge (top-right, pulsing dot)
              Positioned(
                top: 12,
                right: 12,
                child: AnimatedBuilder(
                  animation: heartCtrl,
                  builder: (_, child) {
                    final t = CurvedAnimation(
                      parent: heartCtrl,
                      curve: Curves.easeInOut,
                    ).value;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kInk, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: kInk,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 1.0 + 0.3 * t,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kPink,
                                boxShadow: [
                                  BoxShadow(
                                    color: kPink.withValues(
                                      alpha: 0.4 + 0.4 * t,
                                    ),
                                    blurRadius: 4 + 5 * t,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text('REC', style: kSilkscreen(8, color: kInk)),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // 7. Status pill (bottom)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: kInk,
                        offset: Offset(2, 2),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const NovaCube(size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 360),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position:
                                          Tween<Offset>(
                                            begin: const Offset(0, 0.4),
                                            end: Offset.zero,
                                          ).animate(
                                            CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOut,
                                            ),
                                          ),
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                headline,
                                key: ValueKey('$headline-$progressStep'),
                                style: const TextStyle(
                                  color: kInk,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showDetail) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusText,
                                style: kSilkscreen(9, color: kInkMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasStep
                            ? 'STEP $progressStep/$progressTotalSteps'
                            : 'STARTING',
                        style: kSilkscreen(9, color: kInkSoft),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _GridFloorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final vPaint = Paint()
      ..color = kInk.withValues(alpha: 0.3)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 13; i++) {
      final x1 = i * size.width / 12;
      final x2 = x1 + (i - 6) * 28 * size.width / 600;
      canvas.drawLine(Offset(x1, 0), Offset(x2, size.height), vPaint);
    }

    for (int i = 0; i < 6; i++) {
      final y = i * size.height / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = kInk.withValues(alpha: (0.06 + i * 0.05).clamp(0.0, 1.0))
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_GridFloorPainter _) => false;
}

class _CubePainter extends CustomPainter {
  _CubePainter({required this.vertexValues, required this.vertexColors});

  final List<double> vertexValues;
  final List<Color> vertexColors;

  // Vertices relative to cube center (0,0), design unit scale 1=1px at size 200
  static const _rawVerts = [
    Offset(-30, -50), Offset(50, -50), Offset(50, 30), Offset(-30, 30), // back
    Offset(-50, -30), Offset(30, -30), Offset(30, 50), Offset(-50, 50), // front
  ];

  static const _edges = [
    [0, 1], [1, 2], [2, 3], [3, 0], // back face
    [4, 5], [5, 6], [6, 7], [7, 4], // front face
    [0, 4], [1, 5], [2, 6], [3, 7], // connectors
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final verts = _rawVerts
        .map((v) => Offset(v.dx * scale + cx, v.dy * scale + cy))
        .toList();

    final edgePaint = Paint()
      ..color = kInk.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeCap = StrokeCap.round;

    for (final edge in _edges) {
      canvas.drawLine(verts[edge[0]], verts[edge[1]], edgePaint);
    }

    for (int i = 0; i < verts.length; i++) {
      final t = vertexValues[i];
      final r = (1.2 + 1.2 * t) * scale;

      canvas.drawCircle(
        verts[i],
        r,
        Paint()..color = vertexColors[i].withValues(alpha: 0.25 + 0.75 * t),
      );
      canvas.drawCircle(
        verts[i],
        r,
        Paint()
          ..color = kInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * scale,
      );
    }
  }

  @override
  bool shouldRepaint(_CubePainter _) => true;
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stripeW = 8.0;
    bool pink = true;
    for (double x = 0; x < size.width; x += stripeW) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, math.min(stripeW, size.width - x), size.height),
        Paint()..color = pink ? kPink : kLilac,
      );
      pink = !pink;
    }
  }

  @override
  bool shouldRepaint(_StripesPainter _) => false;
}
