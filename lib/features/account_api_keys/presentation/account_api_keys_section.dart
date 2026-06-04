import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/account_api_keys/models/account_api_key_models.dart';
import 'package:nova3d_frontend/features/account_api_keys/state/account_api_key_provider.dart';

class AccountApiKeysSection extends ConsumerWidget {
  const AccountApiKeysSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountApiKeysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nova3D API Keys',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      color: kInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Long-lived n3d_ tokens for nova3d-mcp and direct API access.',
                    style: GoogleFonts.inter(fontSize: 13, color: kInkSoft),
                  ),
                ],
              ),
            ),
            _CreateButton(
              enabled: !state.creating,
              onTap: () => _openCreateDialog(context, ref),
            ),
          ],
        ),
        if (state.me != null) ...[
          const SizedBox(height: 16),
          _AccountSummary(me: state.me!),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 14),
          _MessageBanner(message: state.error!, isGood: false),
        ],
        if (state.notice != null) ...[
          const SizedBox(height: 14),
          _MessageBanner(message: state.notice!, isGood: true),
        ],
        const SizedBox(height: 18),
        if (state.loading)
          const _LoadingRows()
        else if (state.keys.isEmpty)
          _EmptyApiKeysState(onCreate: () => _openCreateDialog(context, ref))
        else
          Column(
            children: [
              for (final key in state.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ApiKeyRow(
                    keyModel: key,
                    revoking: state.revokingIds.contains(key.id),
                    onRevoke: () => _confirmRevoke(context, ref, key),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    ref.read(accountApiKeysProvider.notifier).clearMessages();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateApiKeyDialog(),
    );
    if (name == null) return;

    final created = await ref
        .read(accountApiKeysProvider.notifier)
        .createKey(name);
    if (created == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreatedApiKeyDialog(created: created),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    AccountApiKey key,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RevokeApiKeySheet(keyModel: key),
    );
    if (confirmed != true) return;
    await ref.read(accountApiKeysProvider.notifier).revokeKey(key);
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.me});

  final AccountMe me;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kMintBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kMint),
    ),
    child: Row(
      children: [
        const Icon(Icons.account_circle_outlined, color: kInk, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            me.email.isEmpty ? me.userId : me.email,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: kInk,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _CreditPill(credits: me.availableCredits),
      ],
    ),
  );
}

class _CreditPill extends StatelessWidget {
  const _CreditPill({required this.credits});

  final int credits;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: kInk, width: 1.5),
    ),
    child: Text(
      '$credits credits',
      style: kSilkscreen(9, color: kInk, letterSpacing: 0.4),
    ),
  );
}

class _ApiKeyRow extends StatelessWidget {
  const _ApiKeyRow({
    required this.keyModel,
    required this.revoking,
    required this.onRevoke,
  });

  final AccountApiKey keyModel;
  final bool revoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kLineSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keyModel.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: kInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  SelectableText(
                    keyModel.maskedKey,
                    style: GoogleFonts.inter(
                      color: kInkSoft,
                      fontSize: 12,
                      fontFeatures: const [],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Revoke key',
              child: IconButton(
                onPressed: revoking ? null : onRevoke,
                icon: revoking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: kErrorRed,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                color: kErrorRed,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaPill(
              icon: Icons.calendar_today_outlined,
              label: 'Created ${_formatDate(keyModel.createdAt)}',
            ),
            _MetaPill(
              icon: Icons.access_time,
              label: keyModel.lastUsedAt == null
                  ? 'Never used'
                  : 'Last used ${_relativeTime(keyModel.lastUsedAt!)}',
            ),
          ],
        ),
      ],
    ),
  );
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: kCream,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: kLineSoft),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: kInkMuted),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(color: kInkSoft, fontSize: 11)),
      ],
    ),
  );
}

class _EmptyApiKeysState extends StatelessWidget {
  const _EmptyApiKeysState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: kButterBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kButter),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.vpn_key_outlined, color: kInk, size: 24),
        const SizedBox(height: 10),
        Text(
          'No API keys yet',
          style: GoogleFonts.inter(
            color: kInk,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Create one to connect nova3d-mcp with NOVA3D_TOKEN.',
          style: GoogleFonts.inter(color: kInkSoft, fontSize: 13),
        ),
        const SizedBox(height: 14),
        _CreateButton(enabled: true, onTap: onCreate),
      ],
    ),
  );
}

class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
    onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
    onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
    onTap: widget.enabled ? widget.onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        color: widget.enabled ? kPink : kLineSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: _pressed || !widget.enabled
            ? []
            : const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add, size: 16, color: kInk),
          const SizedBox(width: 7),
          Text('Create API Key', style: kSilkscreen(10, color: kInk)),
        ],
      ),
    ),
  );
}

class _CreateApiKeyDialog extends StatefulWidget {
  const _CreateApiKeyDialog();

  @override
  State<_CreateApiKeyDialog> createState() => _CreateApiKeyDialogState();
}

class _CreateApiKeyDialogState extends State<_CreateApiKeyDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: kSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: kInk, width: 1.5),
    ),
    title: Text('Create API key', style: kVt323(28, color: kInk)),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 64,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Work laptop, Claude Code, CI',
          errorText: _error,
          counterText: '',
        ),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          'Cancel',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
        ),
      ),
      ElevatedButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.vpn_key_outlined, size: 16),
        label: const Text('Create'),
      ),
    ],
  );

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    Navigator.pop(context, name);
  }
}

class _CreatedApiKeyDialog extends StatefulWidget {
  const _CreatedApiKeyDialog({required this.created});

  final CreatedAccountApiKey created;

  @override
  State<_CreatedApiKeyDialog> createState() => _CreatedApiKeyDialogState();
}

class _CreatedApiKeyDialogState extends State<_CreatedApiKeyDialog> {
  late final TextEditingController _controller;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.created.key);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: kSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: kInk, width: 1.5),
    ),
    title: Text('Copy this key now', style: kVt323(30, color: kInk)),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kButterBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kButter),
            ),
            child: Text(
              'This key will not be shown again. Copy it now.',
              style: GoogleFonts.inter(
                color: kInk,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            readOnly: true,
            style: GoogleFonts.inter(
              color: kInk,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(labelText: 'NOVA3D_TOKEN'),
            onTap: () => _controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controller.text.length,
            ),
          ),
        ],
      ),
    ),
    actions: [
      OutlinedButton.icon(
        onPressed: _copy,
        icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
        label: Text(_copied ? 'Copied!' : 'Copy'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('I copied it'),
      ),
    ],
  );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.created.key));
    if (mounted) setState(() => _copied = true);
  }
}

class _RevokeApiKeySheet extends StatelessWidget {
  const _RevokeApiKeySheet({required this.keyModel});

  final AccountApiKey keyModel;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: kChunkyCard(bg: kSurface, borderColor: kErrorRed),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_outlined, color: kErrorRed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Revoke key?',
                  style: GoogleFonts.inter(
                    color: kInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            keyModel.name,
            style: GoogleFonts.inter(
              color: kInk,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            keyModel.maskedKey,
            style: GoogleFonts.inter(color: kInkSoft, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            'This cannot be undone. MCP servers using this key will stop authenticating.',
            style: GoogleFonts.inter(color: kInkSoft, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Revoke'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kErrorRed,
                  foregroundColor: kInk,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) => Column(
    children: const [_LoadingRow(), SizedBox(height: 10), _LoadingRow()],
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => Container(
    height: 88,
    decoration: BoxDecoration(
      color: kLineSoft.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
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
      color: (isGood ? kSuccessGreen : kErrorRed).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: (isGood ? kSuccessGreen : kErrorRed).withValues(alpha: 0.35),
      ),
    ),
    child: Text(
      message,
      style: GoogleFonts.inter(
        color: isGood ? const Color(0xFF1F7A3E) : kErrorRed,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _formatDate(DateTime date) => DateFormat.yMMMd().format(date);

String _relativeTime(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  }
  return _formatDate(date);
}
