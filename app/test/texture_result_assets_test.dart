import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

Map<String, dynamic> _artifact(String name) => {
  'uri': 'azure://test/$name',
  'url': 'https://blob.test/$name?sig=x',
};

Map<String, dynamic> _successJson() => {
  'final_textured': [
    {
      'result': {
        'glb_artifact': _artifact('model.glb'),
        'map_artifacts': {
          'albedo': _artifact('albedo.png'),
          'normal': _artifact('normal.png'),
          'roughness': _artifact('roughness.png'),
          'metallic': _artifact('metallic.png'),
          'ao': _artifact('ao.png'),
          'height': _artifact('height.png'),
        },
        'tile_artifacts': {
          'Body': _artifact('tile_body.png'),
          'Shell#2': _artifact('tile_shell.png'),
        },
        'relief_tile_artifacts': {'Body': _artifact('relief_body.png')},
        'painted_atlas_artifact': _artifact('painted.png'),
        'relief_atlas_artifact': _artifact('relief.png'),
        'layout_png_artifact': _artifact('layout.png'),
        'layout_labeled_png_artifact': _artifact('layout_labeled.png'),
        'layout_svg_artifact': _artifact('layout.svg'),
        'uv_wireframe_artifact': _artifact('uv_wireframe.png'),
        // Internal pipeline artifacts that must NOT become user assets.
        'materials_artifact': _artifact('materials.json'),
        'material_spec_artifact': _artifact('material_spec.json'),
        'batch_map_artifact': _artifact('batch_map.json'),
        'seam_diagnostics': {'repeat_m': 0.15, 'margin_px': 24},
        'pbr_diagnostics': {'texture_size': 2048, 'ao_mode_used': 'baked'},
        'assemble_diagnostics': {'tile_count': 2},
        'batch_count': 1,
      },
    },
  ],
};

void main() {
  group('TextureResult asset extraction', () {
    test('packs everything a 3D artist needs, grouped by folder', () {
      final result = TextureResult.fromResultJson(_successJson());
      expect(result.failed, isFalse);

      final paths = result.assets.map((a) => a.zipPath).toList();
      expect(paths, contains('model.glb'));
      for (final map in [
        'albedo',
        'normal',
        'roughness',
        'metallic',
        'ao',
        'height',
      ]) {
        expect(paths, contains('maps/$map.png'));
      }
      expect(paths, contains('tiles/albedo/Body.png'));
      // Cell ids are sanitised into safe file names.
      expect(paths, contains('tiles/albedo/Shell_2.png'));
      expect(paths, contains('tiles/relief/Body.png'));
      expect(paths, contains('atlases/painted_atlas.png'));
      expect(paths, contains('atlases/relief_atlas.png'));
      expect(paths, contains('uv/layout.png'));
      expect(paths, contains('uv/layout_labeled.png'));
      expect(paths, contains('uv/layout.svg'));
      expect(paths, contains('uv/uv_wireframe.png'));
      expect(paths, contains('settings.json'));
    });

    test('never exposes internal pipeline artifacts', () {
      final result = TextureResult.fromResultJson(_successJson());
      final paths = result.assets.map((a) => a.zipPath).join(' ');
      expect(paths, isNot(contains('materials.json')));
      expect(paths, isNot(contains('material_spec')));
      expect(paths, isNot(contains('batch_map')));
    });

    test('settings.json carries the run diagnostics inline', () {
      final result = TextureResult.fromResultJson(_successJson());
      final settings = result.assets.firstWhere(
        (a) => a.name == 'settings.json',
      );
      expect(settings.isInline, isTrue);
      final parsed = jsonDecode(settings.content!) as Map<String, dynamic>;
      expect(parsed['seam_bake'], {'repeat_m': 0.15, 'margin_px': 24});
      expect(parsed['pbr_derive'], containsPair('texture_size', 2048));
      expect(parsed['paint_batch_count'], 1);
    });

    test('assets survive the message JSON round trip', () {
      final result = TextureResult.fromResultJson(_successJson());
      final roundTripped = result.assets
          .map((a) => TextureAsset.fromJson(a.toJson()))
          .toList();
      expect(
        roundTripped.map((a) => a.zipPath),
        result.assets.map((a) => a.zipPath),
      );
      final settings = roundTripped.firstWhere(
        (a) => a.name == 'settings.json',
      );
      expect(settings.content, isNotEmpty);
    });
  });

  group('Message soft delete', () {
    MessageModel message() => MessageModel(
      id: 'm1',
      role: MessageRole.assistant,
      text: 'hi',
      createdAt: DateTime.utc(2026, 7, 9),
    );

    test('deleted_at persists through the content JSON round trip', () {
      final deleted = message().copyWith(deletedAt: DateTime.utc(2026, 7, 10));
      final restored = MessageModel.fromLocalJson(deleted.toContentJson());
      expect(restored.isDeleted, isTrue);
      expect(restored.deletedAt, DateTime.utc(2026, 7, 10));
    });

    test('deletion is monotonic through copyWith', () {
      final deleted = message().copyWith(deletedAt: DateTime.utc(2026, 7, 10));
      // Later updates without deletedAt must not resurrect the message.
      expect(deleted.copyWith(text: 'updated').isDeleted, isTrue);
    });

    test('undeleted messages omit the field entirely', () {
      expect(message().toContentJson().containsKey('deleted_at'), isFalse);
    });
  });
}
