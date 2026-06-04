import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:web/web.dart' as web;

/// Code preview panel for a generation's Python code artifact.
///
/// Fetches the `.py` file at [codeArtifact]`['url']`, syntax-highlights it,
/// and renders it with line numbers, a "live edit coming soon" banner, and a
/// bottom toolbar (copy, download, metadata) — matching the design.
class CodePreview extends StatefulWidget {
  const CodePreview({super.key, required this.codeArtifact, this.filename});

  final Map<String, dynamic> codeArtifact;
  final String? filename;

  @override
  State<CodePreview> createState() => _CodePreviewState();
}

class _CodePreviewState extends State<CodePreview> {
  String? _code;
  Object? _error;
  bool _loading = true;
  CancelToken? _cancelToken;

  String get _url => (widget.codeArtifact['url'] as String?) ?? '';
  String get _filename =>
      widget.filename ??
      (widget.codeArtifact['filename'] as String?) ??
      _filenameFromUrl(_url) ??
      'model.py';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant CodePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codeArtifact['url'] != widget.codeArtifact['url']) {
      _fetch();
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final url = _url;
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No code URL provided';
      });
      return;
    }
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Dio().get<String>(
        url,
        cancelToken: token,
        options: Options(responseType: ResponseType.plain),
      );
      if (!mounted) return;
      setState(() {
        _code = response.data ?? '';
        _loading = false;
      });
    } catch (e) {
      if (token.isCancelled || !mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ComingSoonBanner(),
          Expanded(child: _body()),
          _BottomToolbar(
            filename: _filename,
            code: _code,
            url: _url,
            lineCount: _code == null ? null : _countLines(_code!),
            byteCount: _code == null ? null : _utf8ByteLength(_code!),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: kLilac),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: kErrorRed, size: 24),
              const SizedBox(height: 8),
              Text(
                "Couldn't load the code artifact.",
                style: GoogleFonts.inter(color: kInkSoft, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _GhostButton(
                label: 'Retry',
                icon: Icons.refresh,
                onTap: _fetch,
              ),
            ],
          ),
        ),
      );
    }
    return _CodeBody(code: _code ?? '');
  }
}

// ── Coming-soon banner ────────────────────────────────────────────────────────
class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: kButterBg,
        border: Border(bottom: BorderSide(color: kLineSoft, width: 1.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: kButter),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE EDIT · COMING SOON',
                  style: kSilkscreen(10, color: kInk, letterSpacing: 0.5),
                ),
                const SizedBox(height: 1),
                Text(
                  'Tweak the code and watch the model rebuild — landing soon. For now, view & copy.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: kInkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kLilacBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: kInk, width: 1),
            ),
            child: Text(
              'SOON',
              style: kSilkscreen(8, color: kInk, letterSpacing: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Code body (line numbers + syntax-highlighted source) ──────────────────────
class _CodeBody extends StatelessWidget {
  const _CodeBody({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    final lineNumberWidth = (lines.length.toString().length * 8.0).clamp(28, 56)
        + 16;
    const mono = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 12,
      height: 1.55,
      color: kInk,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        primary: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width * 0.4,
            ),
            child: IntrinsicWidth(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line-number gutter
                  Container(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 8,
                      left: 8,
                      right: 8,
                    ),
                    decoration: const BoxDecoration(
                      color: kCream,
                      border: Border(
                        right: BorderSide(color: kLineSoft, width: 1.5),
                      ),
                    ),
                    child: SizedBox(
                      width: lineNumberWidth.toDouble(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < lines.length; i++)
                            Text(
                              (i + 1).toString().padLeft(2, '0'),
                              style: kSilkscreen(
                                10,
                                color: kInkMuted,
                                letterSpacing: 0.3,
                              ).copyWith(height: 1.55 * 12 / 10),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Source
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in lines)
                            Text.rich(
                              TextSpan(
                                children: line.isEmpty
                                    ? const [TextSpan(text: ' ')]
                                    : _highlightPython(line, mono),
                              ),
                              softWrap: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom toolbar ────────────────────────────────────────────────────────────
class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.filename,
    required this.code,
    required this.url,
    required this.lineCount,
    required this.byteCount,
  });

  final String filename;
  final String? code;
  final String url;
  final int? lineCount;
  final int? byteCount;

  Future<void> _copy(BuildContext context) async {
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code!));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $filename', style: kSilkscreen(11, color: kSurface)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _download() {
    if (code == null || url.isEmpty) return;
    _downloadFile(url, filename);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = code == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(top: BorderSide(color: kLineSoft, width: 1.5)),
      ),
      child: Row(
        children: [
          _SecondaryButton(
            label: 'Copy',
            leading: const Icon(Icons.copy_rounded, size: 12, color: kInk),
            onTap: disabled ? null : () => _copy(context),
          ),
          const SizedBox(width: 8),
          _SecondaryButton(
            label: 'Download .py',
            onTap: disabled ? null : _download,
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: kLineSoft),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _metaLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kSilkscreen(10, color: kInkMuted, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          const _EditLockedButton(),
        ],
      ),
    );
  }

  String _metaLabel() {
    final lineLabel = lineCount == null ? '— lines' : '$lineCount lines';
    final sizeLabel = byteCount == null
        ? ''
        : ' · ${_formatBytes(byteCount!)}';
    return 'cadquery · $lineLabel$sizeLabel';
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, this.leading, this.onTap});
  final String label;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: const [
              BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(label, style: kSilkscreen(11, color: kInk, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kInk, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: kInk),
            const SizedBox(width: 6),
            Text(label, style: kSilkscreen(11, color: kInk)),
          ],
        ),
      ),
    );
  }
}

class _EditLockedButton extends StatelessWidget {
  const _EditLockedButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Live editing is coming soon',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kLineSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kLineSoft, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 12, color: kInkMuted),
            const SizedBox(width: 6),
            Text(
              'EDIT LIVE',
              style: kSilkscreen(11, color: kInkMuted, letterSpacing: 0.5),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: kButter,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: kInk, width: 1),
              ),
              child: Text(
                'SOON',
                style: kSilkscreen(8, color: kInk, letterSpacing: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Python syntax highlighter (port of design's highlightPython) ─────────────
// Pattern-based, not a real tokenizer — enough to read pleasantly. Order matters.
const Set<String> _kPythonKeywords = {
  'def', 'import', 'from', 'as', 'return', 'if', 'else', 'elif', 'for', 'in',
  'while', 'with', 'class', 'pass', 'None', 'True', 'False', 'and', 'or',
  'not', 'lambda', 'yield',
};
const Set<String> _kPythonBuiltins = {
  'cq', 'cadquery', 'Workplane', 'show', 'show_object', 'extrude', 'fillet',
  'chamfer', 'translate', 'rotate', 'union', 'cut', 'shell', 'edges', 'faces',
};

final RegExp _indentRe = RegExp(r'^[ \t]+');
final RegExp _stringRe = RegExp(
  r'''^("""[\s\S]*?"""|'''
  r"'''[\s\S]*?'''"
  r'''|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')''',
);
final RegExp _numberRe = RegExp(r'^\d+(\.\d+)?');
final RegExp _decoratorRe = RegExp(r'^@[A-Za-z_][\w.]*');
final RegExp _identRe = RegExp(r'^[A-Za-z_]\w*');
final RegExp _opRe = RegExp(r'^(==|!=|<=|>=|->|=|[+\-*/%<>])');

List<InlineSpan> _highlightPython(String line, TextStyle base) {
  final spans = <InlineSpan>[];
  var rest = line;

  final indent = _indentRe.firstMatch(rest);
  if (indent != null) {
    spans.add(TextSpan(text: indent.group(0), style: base));
    rest = rest.substring(indent.end);
  }

  while (rest.isNotEmpty) {
    // Comment — rest of line
    if (rest.startsWith('#')) {
      spans.add(TextSpan(
        text: rest,
        style: base.copyWith(
          color: kInkMuted,
          fontStyle: FontStyle.italic,
        ),
      ));
      break;
    }

    final stringMatch = _stringRe.firstMatch(rest);
    if (stringMatch != null) {
      spans.add(TextSpan(
        text: stringMatch.group(0),
        style: base.copyWith(color: kSuccessGreen),
      ));
      rest = rest.substring(stringMatch.end);
      continue;
    }

    final numMatch = _numberRe.firstMatch(rest);
    if (numMatch != null) {
      spans.add(TextSpan(
        text: numMatch.group(0),
        style: base.copyWith(color: const Color(0xFFB97A2A)),
      ));
      rest = rest.substring(numMatch.end);
      continue;
    }

    final decMatch = _decoratorRe.firstMatch(rest);
    if (decMatch != null) {
      spans.add(TextSpan(
        text: decMatch.group(0),
        style: base.copyWith(color: kButter, fontWeight: FontWeight.w600),
      ));
      rest = rest.substring(decMatch.end);
      continue;
    }

    final identMatch = _identRe.firstMatch(rest);
    if (identMatch != null) {
      final word = identMatch.group(0)!;
      TextStyle style;
      if (_kPythonKeywords.contains(word)) {
        style = base.copyWith(color: kPink, fontWeight: FontWeight.w600);
      } else if (_kPythonBuiltins.contains(word)) {
        style = base.copyWith(color: kLilac);
      } else {
        style = base;
      }
      spans.add(TextSpan(text: word, style: style));
      rest = rest.substring(identMatch.end);
      continue;
    }

    final opMatch = _opRe.firstMatch(rest);
    if (opMatch != null) {
      spans.add(TextSpan(
        text: opMatch.group(0),
        style: base.copyWith(color: kInkSoft),
      ));
      rest = rest.substring(opMatch.end);
      continue;
    }

    spans.add(TextSpan(text: rest[0], style: base));
    rest = rest.substring(1);
  }

  return spans;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
int _countLines(String code) {
  if (code.isEmpty) return 0;
  return code.split('\n').length;
}

int _utf8ByteLength(String code) => utf8.encode(code).length;

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}b';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} kb';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} mb';
}

String? _filenameFromUrl(String url) {
  if (url.isEmpty) return null;
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last;
    return last.isEmpty ? null : last;
  } catch (_) {
    return null;
  }
}

// Trigger a browser download via a hidden anchor with the download attribute.
// Chat / model viewer only runs on web.
void _downloadFile(String url, String filename) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..rel = 'noopener'
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
