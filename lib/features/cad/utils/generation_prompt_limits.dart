import 'package:flutter/services.dart';
import 'package:nova3d_frontend/core/constants.dart';

int generationPromptWordCount(String value) =>
    RegExp(r'\S+').allMatches(value.trim()).length;

bool isGenerationPromptWithinWordLimit(String value) =>
    generationPromptWordCount(value) <= kMaxGenerationPromptWords;

class GenerationPromptWordLimitFormatter extends TextInputFormatter {
  const GenerationPromptWordLimitFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return isGenerationPromptWithinWordLimit(newValue.text)
        ? newValue
        : oldValue;
  }
}
