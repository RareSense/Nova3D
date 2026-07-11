import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/generation_image.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/cad/utils/reference_image_processor.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';

/// Collects inputs for a `texture_3d_v2` run: an optional prompt and/or
/// reference image, a target resolution, and the Gemini key the pipeline uses.
///
/// The key is optional: without one the run is hosted and charged in Nova3D
/// credits, so the dialog shows the credit price (from `/credits/estimate`)
/// against the user's balance and blocks submission when it can't be covered.
/// With a key the run is BYOK and free of credits.
///
/// Returns a [TextureRequest] via `Navigator.pop`, or `null` if cancelled.
/// The source geometry is supplied by the caller (the original generation
/// message), not by this dialog.
class MagicTextureDialog extends ConsumerStatefulWidget {
  const MagicTextureDialog({super.key, this.initialGeminiKey = ''});

  /// Pre-filled from the user's saved Gemini key, if any.
  final String initialGeminiKey;

  @override
  ConsumerState<MagicTextureDialog> createState() =>
      _MagicTextureDialogState();
}

class _MagicTextureDialogState extends ConsumerState<MagicTextureDialog> {
  final _promptCtrl = TextEditingController();
  late final TextEditingController _keyCtrl;
  TextureResolution _resolution = TextureResolution.k2;
  GenerationImage? _image;
  bool _obscureKey = true;
  bool _picking = false;
  String? _error;

  /// Hosted (keyless) credit price from `/credits/estimate`; null while
  /// loading or if the estimate failed (the chat provider re-checks
  /// authoritatively at launch, so this stays a UX hint, never the only gate).
  int? _hostedCreditCost;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.initialGeminiKey);
    // The cost hint depends on whether the key field is blank.
    _keyCtrl.addListener(() => setState(() {}));
    Future.microtask(() async {
      // Fresh balance for the hint + gate.
      await ref.read(billingProvider.notifier).refreshWallet();
      try {
        final estimate = await ref
            .read(cadServiceProvider)
            .estimateTextureCredits();
        if (mounted) {
          setState(() => _hostedCreditCost = estimate.authorizedBudget);
        }
      } on CadException {
        // Leave the hint generic; the launch-time preflight still gates.
      }
    });
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

  /// Available credits, when the wallet has loaded.
  int? get _available => ref.read(billingProvider).wallet?.available;

  /// True when a keyless run is priced and the balance is known to fall short.
  bool get _insufficientForHosted {
    final cost = _hostedCreditCost;
    final available = _available;
    return cost != null && available != null && available < cost;
  }

  void _submit() {
    final prompt = _promptCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (prompt.isEmpty && _image == null) {
      setState(() => _error = 'Add a prompt, a reference image, or both.');
      return;
    }
    if (key.isEmpty && _insufficientForHosted) {
      setState(
        () => _error =
            'Texturing without an API key needs $_hostedCreditCost credits, '
            'but you have $_available available. Buy more credits at '
            '/subscription or add your own Gemini key.',
      );
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
                  autofocus: true,
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
              const SizedBox(height: 4),
              Text(
                _resolution.needsProImageTier
                    ? '2K/4K paints natively on the pro image model for higher '
                          'quality. The Nova3D credit price is the same at every '
                          'resolution; only your own Google key is billed more '
                          'per image.'
                    : '1K paints on the fast image model.',
                style: kSilkscreen(8, color: kInkMuted, letterSpacing: 0.3),
              ),
              const SizedBox(height: 16),

              _label('GEMINI API KEY  (optional)'),
              const SizedBox(height: 6),
              _fieldBox(
                child: TextField(
                  controller: _keyCtrl,
                  obscureText: _obscureKey,
                  style: const TextStyle(color: kInk, fontSize: 14),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Google AI (Gemini) key — optional',
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
              const SizedBox(height: 6),
              _creditCostLine(),
              const SizedBox(height: 4),
              Text(
                'No key needed — leave blank and texturing is paid with '
                'Nova3D credits. Add your own Google AI (Gemini) key to skip '
                'credits: it must be a PAID key with billing on and at least '
                '\$5 of credit; free-tier keys are rejected by the image '
                'model.',
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

  /// One-line credit price hint that tracks the key field: BYOK is free of
  /// credits; hosted shows the estimated price against the current balance and
  /// turns warning-red when the balance can't cover it.
  Widget _creditCostLine() {
    final hasKey = _keyCtrl.text.trim().isNotEmpty;
    final wallet = ref.watch(billingProvider).wallet;
    if (hasKey) {
      return Text(
        'Using your key — no Nova3D credits are charged.',
        style: kSilkscreen(8, color: kInkMuted, letterSpacing: 0.3),
      );
    }
    final cost = _hostedCreditCost;
    final available = wallet?.available;
    final short = _insufficientForHosted;
    final text = cost == null
        ? 'Without a key, texturing is charged in Nova3D credits.'
        : available == null
        ? 'Without a key, texturing uses $cost credits.'
        : 'Without a key, texturing uses $cost credits — you have '
              '$available available.';
    return Text(
      text,
      style: kSilkscreen(
        8,
        color: short ? const Color(0xFFD84C6F) : kInkSoft,
        letterSpacing: 0.3,
      ),
    );
  }

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
