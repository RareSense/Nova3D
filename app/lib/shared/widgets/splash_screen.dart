import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late List<AnimationController> _starControllers;
  late AnimationController _textController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _textController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _starControllers = List.generate(
      8,
      (index) =>
          AnimationController(
            duration: const Duration(milliseconds: 2600),
            vsync: this,
          )
            ..forward()
            ..repeat(),
    );

    for (int i = 0; i < _starControllers.length; i++) {
      _starControllers[i].forward();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController.dispose();
    for (var controller in _starControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                // Animated stars background
                ..._buildAnimatedStars(),

                // Main content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Nova branding
                    Text(
                      'nova',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFF8E76C9),
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Main title with pulse animation
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.98, end: 1.02).animate(
                        CurvedAnimation(
                          parent: _pulseController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Text(
                        'App splash',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF2A2440),
                              fontWeight: FontWeight.w700,
                              fontSize: 48,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Loading indicator with animated text
                    Column(
                      children: [
                        // Animated dots
                        SizedBox(
                          height: 60,
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _textController,
                              builder: (context, child) {
                                final value = _textController.value;
                                final dots = (value * 3).toInt();
                                return Text(
                                  'Polishing pixels${'.' * (dots + 1)}',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: const Color(0xFF6B6391),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 18,
                                        letterSpacing: 0.5,
                                      ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Custom progress indicator
                        _buildCustomProgressBar(),
                      ],
                    ),
                    const SizedBox(height: 48),

                    // Help text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Tip: drop a reference image to guide the generation',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB69CE8),
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAnimatedStars() {
    final positions = [
      (0.15, 0.2),
      (0.85, 0.25),
      (0.25, 0.75),
      (0.75, 0.8),
      (0.1, 0.5),
      (0.9, 0.45),
      (0.5, 0.15),
      (0.5, 0.85),
    ];

    return List.generate(positions.length, (index) {
      final (relX, relY) = positions[index];
      return Positioned(
        left: MediaQuery.of(context).size.width * relX,
        top: MediaQuery.of(context).size.height * relY,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.3, end: 1.0).animate(
            CurvedAnimation(
              parent: _starControllers[index],
              curve: Curves.easeInOut,
            ),
          ),
          child: Opacity(
            opacity: 0.6,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CustomPaint(
                painter: _StarPainter(
                  color: [
                    const Color(0xFFB69CE8),
                    const Color(0xFFFFA8C5),
                    const Color(0xFF8AD0DA),
                    const Color(0xFFFFD96B),
                  ][index % 4],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCustomProgressBar() {
    return SizedBox(
      width: 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          backgroundColor: const Color(0xFFE8DEFA),
          valueColor: AlwaysStoppedAnimation<Color>(
            Color.lerp(
              const Color(0xFF8E76C9),
              const Color(0xFFFFA8C5),
              (_pulseController.value).abs(),
            )!,
          ),
          minHeight: 6,
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final Color color;

  _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    const radius = 8.0;
    const points = 5;

    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * pi) / points - pi / 2;
      final distance = i.isEven ? radius : radius / 2;
      final x = center.dx + distance * cos(angle);
      final y = center.dy + distance * sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => oldDelegate.color != color;
}
