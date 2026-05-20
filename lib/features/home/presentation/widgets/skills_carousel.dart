import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/home/data/skills_registry.dart';
import 'package:nova3d_frontend/features/home/models/skill_def.dart';

/// Horizontally scrollable row of generation skill cards.
///
/// [onSkillSelected] is null until a skill is marked available: true in
/// skills_registry.dart. Coming-soon cards are rendered inert automatically.
class SkillsCarousel extends StatelessWidget {
  const SkillsCarousel({super.key, this.onSkillSelected});

  final void Function(SkillDef skill)? onSkillSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: kSkills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final skill = kSkills[i];
          return _SkillCard(
            skill: skill,
            onTap: (skill.available && onSkillSelected != null)
                ? () => onSkillSelected!(skill)
                : null,
          );
        },
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _SkillCard extends StatefulWidget {
  const _SkillCard({required this.skill, required this.onTap});
  final SkillDef skill;
  final VoidCallback? onTap;

  @override
  State<_SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends State<_SkillCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  void _down(TapDownDetails details) {
    if (_interactive) setState(() => _pressed = true);
  }

  void _up(TapUpDetails details) {
    if (_interactive) setState(() => _pressed = false);
  }

  void _cancel() {
    if (_interactive) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _cancel,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 124,
          transform: Matrix4.translationValues(
            _pressed ? 2 : 0,
            _pressed ? 2 : 0,
            0,
          ),
          decoration: kChunkyCard(
            shadow: !_pressed,
            borderColor: widget.skill.available ? kInk : kInkMuted,
            shadowColor: widget.skill.available ? kInk : kInkMuted,
          ),
          clipBehavior: Clip.antiAlias,
          child: Opacity(
            opacity: widget.skill.available ? 1.0 : 0.45,
            child: Column(
              children: [
                Expanded(child: _Thumbnail(skill: widget.skill)),
                _Label(skill: widget.skill),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail area ────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.skill});
  final SkillDef skill;

  @override
  Widget build(BuildContext context) {
    return Stack(
        children: [
          Container(
            width: double.infinity,
            color: skill.cardColor,
            alignment: Alignment.center,
            child: Text(skill.emoji, style: const TextStyle(fontSize: 38)),
          ),
          if (!skill.available) const _ComingSoonBadge(),
        ],
      );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 7,
      right: 7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: kPink,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: kInk, width: 1),
          boxShadow: const [
            BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
          ],
        ),
        child: Text(
          'SOON',
          style: kSilkscreen(7, color: kInk, letterSpacing: 0.4),
        ),
      ),
    );
  }
}

// ── Label area ────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label({required this.skill});
  final SkillDef skill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kInk, width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            skill.name,
            style: kSilkscreen(9, color: kInk),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            skill.tagline,
            style: GoogleFonts.inter(fontSize: 9, color: kInkSoft, height: 1.3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
