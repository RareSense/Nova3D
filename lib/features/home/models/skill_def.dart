import 'package:flutter/material.dart';

/// Describes a single generation skill (style-specialised workflow).
///
/// [id] maps directly to the backend endpoint: POST /run/state/{id}
/// [available] gates interactivity — false renders a "COMING SOON" badge.
/// When a skill ships, flip [available] to true and wire [SkillsCarousel.onSkillSelected].
class SkillDef {
  const SkillDef({
    required this.id,
    required this.name,
    required this.tagline,
    required this.emoji,
    required this.cardColor,
    this.available = false,
  });

  final String id;
  final String name;
  final String tagline;
  final String emoji;
  final Color cardColor;
  final bool available;
}
