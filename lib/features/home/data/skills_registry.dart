import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/home/models/skill_def.dart';

/// Master catalog of generation skills.
///
/// To ship a skill:
///   1. Set available: true
///   2. Confirm the backend endpoint POST /run/state/{id} exists
///   3. Pass onSkillSelected to SkillsCarousel in home_page.dart
///
/// To add a skill: append a new SkillDef entry below.
const kSkills = <SkillDef>[
  SkillDef(
    id: 'jewelry_to_3d',
    name: 'Jewelry',
    tagline: 'Rings, pendants & gems',
    emoji: '💍',
    cardColor: kLilacBg,
  ),
  SkillDef(
    id: 'mech_to_3d',
    name: 'Mech',
    tagline: 'Robots & hard-surface',
    emoji: '⚙️',
    cardColor: kMintBg,
  ),
  SkillDef(
    id: 'furniture_to_3d',
    name: 'Furniture',
    tagline: 'Chairs, tables & decor',
    emoji: '🪑',
    cardColor: kButterBg,
  ),
  SkillDef(
    id: 'architecture_to_3d',
    name: 'Architecture',
    tagline: 'Buildings & structures',
    emoji: '🏛️',
    cardColor: kMintBg,
  ),
  SkillDef(
    id: 'character_to_3d',
    name: 'Character',
    tagline: 'Creatures & avatars',
    emoji: '🧸',
    cardColor: kPinkBg,
  ),
  SkillDef(
    id: 'vehicle_to_3d',
    name: 'Vehicle',
    tagline: 'Cars, ships & more',
    emoji: '🚗',
    cardColor: kLilacBg,
  ),
  SkillDef(
    id: 'weapons_to_3d',
    name: 'Weapons',
    tagline: 'Swords, guns & tools',
    emoji: '⚔️',
    cardColor: kButterBg,
  ),
  SkillDef(
    id: 'nature_to_3d',
    name: 'Nature',
    tagline: 'Plants, rocks & terrain',
    emoji: '🌿',
    cardColor: kMintBg,
  ),
  SkillDef(
    id: 'gadget_to_3d',
    name: 'Gadgets',
    tagline: 'Electronics & devices',
    emoji: '📱',
    cardColor: kLilacBg,
  ),
  SkillDef(
    id: 'food_to_3d',
    name: 'Food & Props',
    tagline: 'Assets for scenes & games',
    emoji: '🍄',
    cardColor: kPinkBg,
  ),
  SkillDef(
    id: 'custom_skill',
    name: 'Custom',
    tagline: 'Build your own skill',
    emoji: '✦',
    cardColor: kLineSoft,
  ),
];
