import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';
import 'package:nova3d_frontend/core/utils.dart';
import 'package:nova3d_frontend/features/api_keys/state/api_key_provider.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:nova3d_frontend/features/home/presentation/widgets/suggestion_pills.dart';
import 'package:nova3d_frontend/features/home/presentation/widgets/skills_carousel.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/widgets/image_attachment_chip.dart';

const _genericReadinessError =
    'The generation service is unavailable right now. Please try again shortly.';

String _readinessErrorMessage(Object error) =>
    error is CadException ? error.message : _genericReadinessError;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _ctrl = TextEditingController();
  bool _creating = false;
  String? _imageDataUrl;
  String? _imageName;
  String? _selectedModelId;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.length > kMaxReferenceImageBytes) {
      _showInlineMessage('Images must be 8 MB or smaller.');
      return;
    }

    final extension = (file.extension ?? 'png').toLowerCase();
    setState(() {
      _imageName = file.name;
      _imageDataUrl =
          'data:${mimeTypeForExtension(extension)};base64,${base64Encode(bytes)}';
    });
  }

  void _clearImage() {
    setState(() {
      _imageName = null;
      _imageDataUrl = null;
    });
  }

  Future<void> _startConversation(String text) async {
    if (_creating) return;
    final keys = await ref.read(apiKeyServiceProvider).loadValidKeys();
    final options = GenerationModelOption.forKeys(keys);
    final modelOption = GenerationModelOption.findById(
      options,
      _selectedModelId,
    );
    if (modelOption == null) {
      _showKeyRequiredDialog();
      return;
    }

    final request = GenerationRequest(
      prompt: text.trim(),
      modelOption: modelOption,
      imageDataUrl: _imageDataUrl,
      imageName: _imageName,
    );
    if (!request.hasText && !request.hasImage) return;

    setState(() => _creating = true);
    try {
      final readiness = await ref.read(cadServiceProvider).checkReadiness();
      if (!readiness.ready) {
        _showInlineMessage(readiness.userMessage);
        return;
      }

      final user = ref.read(authProvider).valueOrNull;
      final id = 'conv_${DateTime.now().millisecondsSinceEpoch}';
      final conv = ConversationModel(
        id: id,
        title: request.conversationTitle,
        userId: user?.id ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      ref.read(conversationsProvider.notifier).prepend(conv);
      ref.read(generationDraftsProvider.notifier).put(id, request);
      ref.read(messagesProvider(id).notifier).seed(request);
      if (mounted) context.go('/chat/$id');
    } on CadException catch (e) {
      _showInlineMessage(e.message);
    } catch (_) {
      _showInlineMessage(_genericReadinessError);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _showInlineMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showKeyRequiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kInk, width: 1.5),
        ),
        title: Text('Add a provider key', style: kVt323(28, color: kInk)),
        content: Text(
          'Add and validate at least one Gemini, Anthropic, or OpenAI key in Settings before generating. Make sure the provider account has at least \$10 in available credit.',
          style: GoogleFonts.inter(color: kInkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go('/settings');
            },
            child: Text(
              'Open Settings',
              style: GoogleFonts.inter(
                color: kInk,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelOptions = ref.watch(generationModelOptionsProvider);
    final readiness = ref.watch(generationReadinessProvider);

    // No inner Scaffold — AppLayout provides it with the grid background
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NovaCube(size: 80),
              const SizedBox(height: 24),
              // VT323 heading
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: kVt323(54, color: kInk),
                  children: [
                    const TextSpan(text: 'what do you want to make'),
                    TextSpan(
                      text: '?',
                      style: TextStyle(color: kPink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Describe an object, drop a reference image, or do both.\nWe\'ll turn it into a 3D model you can rotate, tweak, and export.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: kInkSoft,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Readiness banner
              readiness.when(
                data: (state) => state.ready
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _StatusBanner(message: state.userMessage),
                      ),
                loading: () => SizedBox(),
                // const Padding(
                //   padding: EdgeInsets.only(bottom: 14),
                //   child: _StatusBanner(
                //     message: 'Checking generation service...',
                //   ),
                // ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _StatusBanner(message: _readinessErrorMessage(error)),
                ),
              ),

              // Prompt card
              _PromptCard(
                ctrl: _ctrl,
                creating: _creating,
                imageName: _imageName,
                modelOptions: modelOptions,
                selectedModelId: _selectedModelId,
                readiness: readiness,
                onPickImage: _pickImage,
                onClearImage: _clearImage,
                onModelChanged: (id) => setState(() => _selectedModelId = id),
                onModelSynced: (id) =>
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedModelId = id);
                    }),
                onGenerate: () => _startConversation(_ctrl.text),
              ),
              const SizedBox(height: 28),

              // Suggestion pills label
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('✦', style: TextStyle(color: kButter, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    'TRY ONE OF THESE',
                    style: kSilkscreen(
                      10,
                      color: kInkMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('✦', style: TextStyle(color: kButter, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 12),
              SuggestionPills(onSelect: _startConversation),
              const SizedBox(height: 32),

              // Skills section
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('✦', style: TextStyle(color: kLilac, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    'SKILLS',
                    style: kSilkscreen(10, color: kInkMuted, letterSpacing: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text('✦', style: TextStyle(color: kLilac, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 12),
              const SkillsCarousel(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Prompt card ───────────────────────────────────────────────────────────────

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.ctrl,
    required this.creating,
    required this.imageName,
    required this.modelOptions,
    required this.selectedModelId,
    required this.readiness,
    required this.onPickImage,
    required this.onClearImage,
    required this.onModelChanged,
    required this.onModelSynced,
    required this.onGenerate,
  });

  final TextEditingController ctrl;
  final bool creating;
  final String? imageName;
  final AsyncValue<List<GenerationModelOption>> modelOptions;
  final String? selectedModelId;
  final AsyncValue<dynamic> readiness;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onModelSynced;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: kChunkyCard(shadow: true),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Pink title strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: kPinkBg,
              border: Border(bottom: BorderSide(color: kInk, width: 1.5)),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Text('✦', style: TextStyle(color: kLilac, fontSize: 11)),
                const SizedBox(width: 8),
                Text(
                  'new creation',
                  style: kSilkscreen(10, color: kInk, letterSpacing: 0.7),
                ),
                const Spacer(),
                Text(
                  'untitled · just now',
                  style: kSilkscreen(9, color: kInkSoft),
                ),
              ],
            ),
          ),

          // Input area
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: ctrl,
                  maxLines: 4,
                  minLines: 2,
                  style: GoogleFonts.inter(
                    color: kInk,
                    fontSize: 15,
                    height: 1.55,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe what to create, or upload an image...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                    filled: false,
                    hintStyle: GoogleFonts.inter(
                      color: kInkMuted,
                      fontSize: 15,
                    ),
                  ),
                  onSubmitted: (_) => onGenerate(),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < kInputCompactBreakpoint;

                    final modelWidget = modelOptions.when(
                      data: (options) {
                        final selected = GenerationModelOption.findById(
                          options,
                          selectedModelId,
                        );
                        if (selected != null &&
                            selected.id != selectedModelId) {
                          onModelSynced(selected.id);
                        }
                        return _ModelChip(
                          options: options,
                          selected: selected,
                          onChanged: (o) => onModelChanged(o?.id),
                        );
                      },
                      loading: () => const SizedBox(
                        width: 140,
                        height: 34,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kLilac,
                          ),
                        ),
                      ),
                      error: (_, _) => const SizedBox(width: 140, height: 34),
                    );

                    final uploadBtn = _SmallButton(
                      label: imageName == null
                          ? 'Upload image'
                          : 'Change image',
                      onTap: creating ? null : onPickImage,
                    );

                    final generateBtn = _GenerateButton(
                      creating: creating,
                      disabled:
                          readiness.isLoading ||
                          readiness.valueOrNull?.ready == false,
                      onTap: onGenerate,
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          uploadBtn,
                          const SizedBox(height: 8),
                          modelWidget,
                          if (imageName != null) ...[
                            const SizedBox(height: 8),
                            ImageAttachmentChip(
                              name: imageName!,
                              onClear: onClearImage,
                            ),
                          ],
                          const SizedBox(height: 8),
                          generateBtn,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        uploadBtn,
                        const SizedBox(width: 8),
                        modelWidget,
                        const SizedBox(width: 8),
                        if (imageName != null)
                          Expanded(
                            child: ImageAttachmentChip(
                              name: imageName!,
                              onClear: onClearImage,
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()),
                        const SizedBox(width: 8),
                        generateBtn,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small chunky button ────────────────────────────────────────────────────────

class _SmallButton extends StatefulWidget {
  const _SmallButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: (_pressed || widget.onTap == null)
            ? []
            : const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
      ),
      child: Text(
        widget.label.toUpperCase(),
        style: kSilkscreen(11, color: kInk),
      ),
    ),
  );
}

// ── Model chip ────────────────────────────────────────────────────────────────

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<GenerationModelOption> options;
  final GenerationModelOption? selected;
  final ValueChanged<GenerationModelOption?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 34,
    child: DropdownButtonFormField<String>(
      key: ValueKey(selected?.id ?? 'no-model'),
      initialValue: selected?.id,
      isExpanded: true,
      dropdownColor: kLilacBg,
      style: kSilkscreen(11, color: kInk),
      icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: kInkSoft),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        filled: true,
        fillColor: kLilacBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kInk, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kInk, width: 1.5),
        ),
      ),
      hint: Text('MODEL', style: kSilkscreen(10, color: kInkSoft)),
      items: options
          .map(
            (o) => DropdownMenuItem<String>(
              value: o.id,
              child: Text(
                o.label,
                overflow: TextOverflow.ellipsis,
                style: kSilkscreen(10, color: kInk),
              ),
            ),
          )
          .toList(),
      onChanged: options.isEmpty
          ? null
          : (id) => onChanged(GenerationModelOption.findById(options, id)),
    ),
  );
}

// ── Generate button ────────────────────────────────────────────────────────────

class _GenerateButton extends StatefulWidget {
  const _GenerateButton({
    required this.creating,
    required this.disabled,
    required this.onTap,
  });
  final bool creating;
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<_GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends State<_GenerateButton> {
  bool _pressed = false;

  bool get _enabled => !widget.creating && !widget.disabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
    onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
    onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
    onTap: _enabled ? widget.onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
      decoration: BoxDecoration(
        color: _enabled ? kPink : kLineSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: (_pressed || !_enabled)
            ? []
            : const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
      ),
      child: widget.creating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Generate', style: kSilkscreen(12, color: kInk)),
                const SizedBox(width: 6),
                Text('→', style: kSilkscreen(14, color: kInk)),
              ],
            ),
    ),
  );
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kButterBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kButter, width: 1.5),
    ),
    child: Text(
      message,
      style: GoogleFonts.inter(color: kInkSoft, fontSize: 13),
    ),
  );
}
