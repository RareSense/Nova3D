import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/generation_image.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/cad/utils/reference_image_processor.dart';

/// Collects inputs for a `texture_3d_v2` run: an optional prompt and/or
/// reference image, a target resolution, and the Gemini key the pipeline uses.
///
/// Returns a [TextureRequest] via `Navigator.pop`, or `null` if cancelled.
/// The source geometry is supplied by the caller (the original generation
/// message), not by this dialog.
class MagicTextureDialog extends StatefulWidget {
  const MagicTextureDialog({super.key, this.initialGeminiKey = ''});

  /// Pre-filled from the user's saved Gemini key, if any.
  final String initialGeminiKey;

  @override
  State<MagicTextureDialog> createState() => _MagicTextureDialogState();
}

class _MagicTextureDialogState extends State<MagicTextureDialog> {
  final _promptCtrl = TextEditingController();
  late final TextEditingController _keyCtrl;
  TextureResolution _resolution = TextureResolution.k2;
  GenerationImage? _image;
  bool _obscureKey = true;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.initialGeminiKey);
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;
      final processed = await processReferenceImageFiles(
        files,
        remainingSlots: 1,
      );
      if (!mounted || processed.isEmpty) return;
      setState(() {
        _image = processed.first;
        _error = null;
      });
    } on ReferenceImageProcessingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    final prompt = _promptCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'A Gemini API key is required to texture.');
      return;
    }
    if (prompt.isEmpty && _image == null) {
      setState(() => _error = 'Add a prompt, a reference image, or both.');
      return;
    }
    Navigator.of(context).pop(
      TextureRequest(
        prompt: prompt,
        referenceImageDataUrl: _image?.dataUrl,
        resolution: _resolution,
        geminiApiKey: key,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCream,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kInk, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16, height: 1)),
                  const SizedBox(width: 8),
                  Text(
                    'MAGIC TEXTURE',
                    style: kSilkscreen(12, color: kInk, letterSpacing: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'PBR-texture this model with a prompt and/or a reference image.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: kInkSoft, fontSize: 12),
              ),
              const SizedBox(height: 18),

              _label('DESCRIBE THE LOOK  (optional)'),
              const SizedBox(height: 6),
              _fieldBox(
                child: TextField(
                  controller: _promptCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(color: kInk, fontSize: 14),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'e.g. glossy ceramic, pastel pink shell…',
                    hintStyle: TextStyle(color: kInkMuted, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _label('REFERENCE IMAGE  (optional)'),
              const SizedBox(height: 6),
              _imageRow(),
              const SizedBox(height: 16),

              _label('RESOLUTION'),
              const SizedBox(height: 6),
              _resolutionRow(),
              const SizedBox(height: 16),

              _label('GEMINI API KEY'),
              const SizedBox(height: 6),
              _fieldBox(
                child: TextField(
                  controller: _keyCtrl,
                  obscureText: _obscureKey,
                  style: const TextStyle(color: kInk, fontSize: 14),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Google AI (Gemini) key',
                    hintStyle: const TextStyle(color: kInkMuted, fontSize: 14),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kInkMuted,
                      ),
                      splashRadius: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Texturing runs on Gemini. Saved keys prefill here.',
                style: kSilkscreen(8, color: kInkMuted, letterSpacing: 0.3),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFD84C6F), fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCEL',
                      style: kSilkscreen(10, color: kInkSoft),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _primaryButton(label: 'TEXTURE', onTap: _submit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: kSilkscreen(9, color: kInkSoft, letterSpacing: 0.5));

  Widget _fieldBox({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kInk, width: 1.5),
    ),
    child: child,
  );

  Widget _imageRow() {
    if (_image != null) {
      return Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kInk, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              _image!.dataUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _image!.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kInkSoft, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _image = null),
            icon: const Icon(Icons.close, size: 18, color: kInkMuted),
            splashRadius: 18,
            tooltip: 'Remove image',
          ),
        ],
      );
    }
    return InkWell(
      onTap: _picking ? null : _pickImage,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kInk, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined,
                size: 18, color: kInkSoft),
            const SizedBox(width: 8),
            Text(
              _picking ? 'Loading…' : 'Attach a reference photo',
              style: const TextStyle(color: kInkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolutionRow() => Row(
    children: [
      for (final option in TextureResolution.values) ...[
        Expanded(child: _resolutionChip(option)),
        if (option != TextureResolution.values.last)
          const SizedBox(width: 8),
      ],
    ],
  );

  Widget _resolutionChip(TextureResolution option) {
    final selected = option == _resolution;
    return InkWell(
      onTap: () => setState(() => _resolution = option),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kLilacBg : kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: selected
              ? const [
                  BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
                ]
              : const [],
        ),
        child: Text(
          option.label,
          style: kSilkscreen(11, color: kInk, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: kLilac,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: const [
              BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          child: Text(label, style: kSilkscreen(10, color: kInk)),
        ),
      );
}
