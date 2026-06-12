import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/generation_image.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/utils/generation_prompt_limits.dart';
import 'package:nova3d_frontend/features/cad/utils/reference_image_processor.dart';
import 'package:nova3d_frontend/shared/widgets/generation_model_label.dart';
import 'package:nova3d_frontend/shared/widgets/image_attachment_chip.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.modelOptions,
    required this.selectedModel,
    required this.onModelChanged,
    this.disabled = false,
  });

  final FutureOr<bool> Function(GenerationRequest request) onSend;
  final List<GenerationModelOption> modelOptions;
  final GenerationModelOption? selectedModel;
  final ValueChanged<GenerationModelOption?> onModelChanged;
  final bool disabled;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  final List<GenerationImage> _images = [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !widget.disabled &&
      widget.selectedModel != null &&
      (_ctrl.text.trim().isNotEmpty || _images.isNotEmpty);

  Future<void> _pickImages() async {
    final remainingSlots = kMaxReferenceImageCount - _images.length;
    if (remainingSlots <= 0) {
      _showSnack('You can attach up to $kMaxReferenceImageCount images.');
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    try {
      final processed = await processReferenceImageFiles(
        files,
        remainingSlots: remainingSlots,
      );
      if (!mounted || processed.isEmpty) return;
      setState(() => _images.addAll(processed));
      if (files.length > remainingSlots) {
        _showSnack(
          'Only the first $remainingSlots selected image(s) were attached.',
        );
      }
    } on ReferenceImageProcessingException catch (e) {
      _showSnack(e.message);
    }
  }

  void _clearImage(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
  }

  void _clearImages() {
    if (_images.isEmpty) return;
    setState(_images.clear);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    final modelOption = widget.selectedModel;
    if (modelOption == null) return;
    if (!isGenerationPromptWithinWordLimit(text)) {
      _showSnack('Prompt must be $kMaxGenerationPromptWords words or fewer.');
      return;
    }
    final request = GenerationRequest(
      prompt: text,
      modelOption: modelOption,
      images: List.unmodifiable(_images),
    );
    if (!request.hasText && !request.hasImage) return;
    if (widget.disabled) return;

    final accepted = await widget.onSend(request);
    if (accepted) {
      _ctrl.clear();
      _clearImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kInk, width: 1.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kContentMaxWidth),
          child: Container(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInk, width: 1.5),
              boxShadow: const [
                BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: _images.isEmpty ? 'Upload images' : 'Add images',
                      onPressed: widget.disabled ? null : _pickImages,
                      icon: const Icon(Icons.image_outlined),
                      color: kInkSoft,
                    ),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _submit,
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            shift: true,
                          ): () {},
                        },
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focusNode,
                          enabled: !widget.disabled,
                          inputFormatters: const [
                            GenerationPromptWordLimitFormatter(),
                          ],
                          maxLines: 6,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          style: GoogleFonts.inter(color: kInk, fontSize: 14),
                          decoration: InputDecoration(
                            hintText:
                                'Describe the 3D model you want to create...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                            hintStyle: GoogleFonts.inter(
                              color: kInkMuted,
                              fontSize: 14,
                            ),
                            fillColor: Colors.transparent,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ChatModelDropdown(
                      options: widget.modelOptions,
                      selected: widget.selectedModel,
                      disabled: widget.disabled,
                      onChanged: widget.onModelChanged,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _SendButton(
                        enabled: _canSubmit,
                        onTap: _canSubmit ? _submit : null,
                      ),
                    ),
                  ],
                ),
                if (_images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _images.asMap().entries)
                          ImageAttachmentChip(
                            name: entry.value.name,
                            onClear: widget.disabled
                                ? null
                                : () => _clearImage(entry.key),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Send button ────────────────────────────────────────────────────────────────

class _SendButton extends StatefulWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
    onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
    onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: widget.enabled ? kPink : kLineSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: (_pressed || !widget.enabled)
            ? []
            : const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
      ),
      child: const Icon(Icons.send_rounded, size: 18, color: kInk),
    ),
  );
}

// ── Model dropdown ────────────────────────────────────────────────────────────

class _ChatModelDropdown extends StatelessWidget {
  const _ChatModelDropdown({
    required this.options,
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  final List<GenerationModelOption> options;
  final GenerationModelOption? selected;
  final bool disabled;
  final ValueChanged<GenerationModelOption?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 248,
    height: 38,
    child: DropdownButtonFormField<String>(
      key: ValueKey(selected?.id ?? 'no-model'),
      initialValue: selected?.id,
      isExpanded: true,
      dropdownColor: kLilacBg,
      menuMaxHeight: 360,
      itemHeight: 58,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: kInk,
      ),
      icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: kInkSoft),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        filled: true,
        fillColor: kLilacBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kInk, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kInk, width: 1.5),
        ),
      ),
      hint: Text('MODEL', style: kSilkscreen(10, color: kInkSoft)),
      selectedItemBuilder: (context) => options
          .map((o) => GenerationModelLabel(option: o, compact: true))
          .toList(),
      items: options
          .map(
            (o) => DropdownMenuItem<String>(
              value: o.id,
              child: GenerationModelLabel(option: o),
            ),
          )
          .toList(),
      onChanged: disabled || options.isEmpty
          ? null
          : (id) => onChanged(GenerationModelOption.findById(options, id)),
    ),
  );
}
