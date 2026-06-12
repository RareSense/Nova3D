import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/utils.dart';
import 'package:nova3d_frontend/features/cad/models/generation_image.dart';

class ReferenceImageProcessingException implements Exception {
  const ReferenceImageProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}

Future<List<GenerationImage>> processReferenceImageFiles(
  List<PlatformFile> files, {
  required int remainingSlots,
}) async {
  if (remainingSlots <= 0) {
    throw const ReferenceImageProcessingException(
      'You can attach up to 3 images.',
    );
  }
  if (files.isEmpty) return const [];

  final selected = files.take(remainingSlots).toList(growable: false);
  final processed = <GenerationImage>[];
  for (final file in selected) {
    final bytes = file.bytes;
    if (bytes == null) continue;
    if (bytes.length > kMaxReferenceImageBytes) {
      throw ReferenceImageProcessingException(
        '${file.name} is too large. Images must be 8 MB or smaller.',
      );
    }

    final resized = await _resizeIfNeeded(bytes);
    final extension = resized.wasResized
        ? 'png'
        : (file.extension ?? 'png').toLowerCase();
    final dataUrl =
        'data:${mimeTypeForExtension(extension)};base64,${base64Encode(resized.bytes)}';
    processed.add(GenerationImage(name: file.name, dataUrl: dataUrl));
  }
  return processed;
}

Future<_ProcessedImageBytes> _resizeIfNeeded(Uint8List bytes) async {
  final original = await _decodeImage(bytes);
  final width = original.width;
  final height = original.height;
  original.dispose();

  final longestSide = math.max(width, height);
  if (longestSide <= kMaxReferenceImageDimension) {
    return _ProcessedImageBytes(bytes: bytes, wasResized: false);
  }

  final scale = kMaxReferenceImageDimension / longestSide;
  final targetWidth = math.max(1, (width * scale).round());
  final targetHeight = math.max(1, (height * scale).round());
  final resized = await _decodeImage(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
  resized.dispose();
  if (byteData == null) {
    throw const ReferenceImageProcessingException(
      'Could not prepare this image. Try another file.',
    );
  }
  return _ProcessedImageBytes(
    bytes: Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ),
    wasResized: true,
  );
}

Future<ui.Image> _decodeImage(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    throw const ReferenceImageProcessingException(
      'Could not read this image. Try another PNG, JPEG, or WebP file.',
    );
  }
}

class _ProcessedImageBytes {
  const _ProcessedImageBytes({required this.bytes, required this.wasResized});

  final Uint8List bytes;
  final bool wasResized;
}
