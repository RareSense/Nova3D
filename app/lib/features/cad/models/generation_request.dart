import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_image.dart';

class GenerationRequest {
  const GenerationRequest({
    required this.prompt,
    required this.modelOption,
    this.images = const [],
  });

  final String prompt;
  final GenerationModelOption modelOption;
  final List<GenerationImage> images;

  bool get hasText => prompt.trim().isNotEmpty;

  List<String> get imageDataUrls =>
      images.map((image) => image.dataUrl).toList(growable: false);

  bool get hasImage => images.isNotEmpty;

  String get conversationTitle {
    if (hasText) {
      final trimmed = prompt.trim();
      return trimmed.length > 50 ? '${trimmed.substring(0, 50)}...' : trimmed;
    }
    final names = images.map((image) => image.name).join(', ');
    return names.isEmpty ? 'Image generation' : 'Image: $names';
  }

  String get messageText {
    final names = images.map((image) => image.name).join(', ');
    if (hasText && hasImage) return '$prompt\n\nAttached images: $names';
    if (hasText) return prompt;
    return 'Attached images: $names';
  }
}
