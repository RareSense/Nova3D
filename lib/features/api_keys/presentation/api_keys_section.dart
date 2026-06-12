import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/api_keys/models/api_key_models.dart';
import 'package:nova3d_frontend/features/api_keys/state/api_key_provider.dart';

class ApiKeysSection extends ConsumerWidget {
  const ApiKeysSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apiKeysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bring Your Own Provider Key',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: kTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use your own OpenRouter, OpenAI, Anthropic, or Gemini key instead of Nova3D credits. These are third-party provider keys, not Nova3D n3d_ API tokens.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (state.message != null) ...[
          const SizedBox(height: 14),
          _MessageBanner(message: state.message!, isGood: state.hasValidKey),
        ],
        const SizedBox(height: 18),
        ...AiProvider.values.map(
          (provider) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProviderKeyTile(provider: provider),
          ),
        ),
      ],
    );
  }
}

class _ProviderKeyTile extends ConsumerStatefulWidget {
  const _ProviderKeyTile({required this.provider});
  final AiProvider provider;

  @override
  ConsumerState<_ProviderKeyTile> createState() => _ProviderKeyTileState();
}

class _ProviderKeyTileState extends ConsumerState<_ProviderKeyTile> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeysProvider);
    final keyState = state.keyFor(widget.provider);
    final isValidating = state.validating == widget.provider;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBgTertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: keyState.isValid
              ? kSuccessGreen.withValues(alpha: 0.45)
              : kBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.provider.label,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusPill(isValid: keyState.isValid),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !keyState.hasKey,
                  obscureText: keyState.hasKey || _obscure,
                  style: const TextStyle(color: kTextPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: keyState.hasKey
                        ? 'Key saved securely in this browser'
                        : 'Paste ${widget.provider.label} key',
                    suffixIcon: keyState.hasKey
                        ? const Icon(
                            Icons.lock_outline,
                            color: kTextMuted,
                            size: 18,
                          )
                        : IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: kTextMuted,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: kBorderColor),
                    ),
                    fillColor: kBgSecondary,
                    filled: true,
                    hintStyle: TextStyle(
                      color: keyState.hasKey ? kTextSecondary : kTextMuted,
                      fontSize: 13,
                    ),
                  ),
                  onSubmitted: keyState.hasKey ? null : (_) => _save(),
                ),
              ),
              const SizedBox(width: 10),
              if (!keyState.hasKey)
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isValidating ? null : _save,
                    child: isValidating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kInk,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              if (keyState.hasKey) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: IconButton(
                    tooltip: 'Remove key',
                    onPressed: isValidating
                        ? null
                        : () => ref
                              .read(apiKeysProvider.notifier)
                              .clear(widget.provider),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: kTextMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    await ref.read(apiKeysProvider.notifier).save(widget.provider, value);
    _controller.clear();
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isValid});
  final bool isValid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: (isValid ? kSuccessGreen : kTextMuted).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      isValid ? 'Key added' : 'Not set',
      style: TextStyle(
        color: isValid ? kSuccessGreen : kTextMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isGood});
  final String message;
  final bool isGood;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (isGood ? kSuccessGreen : kErrorRed).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: (isGood ? kSuccessGreen : kErrorRed).withValues(alpha: 0.3),
      ),
    ),
    child: Text(
      message,
      style: TextStyle(color: isGood ? kSuccessGreen : kErrorRed, fontSize: 13),
    ),
  );
}
