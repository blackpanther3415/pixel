import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// C.B — Clone Builder. Clone any app, skill, project or tool into a
/// functional equivalent adapted to the Pixel ecosystem.
class CloneTab extends StatefulWidget {
  final AppState state;
  const CloneTab({super.key, required this.state});

  @override
  State<CloneTab> createState() => _CloneTabState();
}

class _CloneTabState extends State<CloneTab> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _url = TextEditingController();
  bool _busy = false;
  String? _feedback;

  @override
  void dispose() {
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _cloneText() async {
    await _runClone(
      input: _description.text.trim(),
      url: _url.text.trim().isEmpty ? null : _url.text.trim(),
    );
  }

  Future<void> _cloneFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final f = result?.files.firstOrNull;
    if (f == null) return;
    final content = f.bytes == null
        ? '[binary file ${f.name}]'
        : String.fromCharCodes(f.bytes!);
    await _runClone(fileName: f.name, fileContent: content);
  }

  Future<void> _runClone({
    String input = '',
    String? url,
    String? fileName,
    String? fileContent,
  }) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final skill = await widget.state.services.clone.clone(
        input: input,
        url: url,
        fileName: fileName,
        fileContent: fileContent,
      );
      setState(() {
        _busy = false;
        _feedback =
            'Cloned "${skill.name}" as a Pixel skill. Test it in T.B, then '
            'approve it into F.B.';
      });
      await widget.state.refresh();
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Clone failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('C.B · CLONE BUILDER',
            style: TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5)),
        const SizedBox(height: 4),
        const Text(
            'Clone any app, skill, project or tool. Pixel analyzes it and '
            'produces a functional equivalent inside its own ecosystem — '
            'not a byte-copy of third-party assets.',
            style: TextStyle(color: AppColors.textMid, fontSize: 12)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What do you want to clone?',
                    style: TextStyle(
                        color: AppColors.textHigh,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe the app / skill / tool…\n'
                        'e.g. "A tool that turns a meeting transcript into '
                        'action items and sends a summary."',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    hintText: 'Or paste a source URL to analyze (optional)',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    PixelButton(
                      label: 'Clone from description',
                      icon: Icons.copy_all,
                      busy: _busy,
                      onPressed: _cloneText,
                    ),
                    PixelButton(
                      label: 'Clone from file',
                      icon: Icons.upload_file,
                      color: AppColors.accent,
                      busy: _busy,
                      onPressed: _cloneFile,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_feedback != null) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                      _feedback!.startsWith('Clone failed')
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _feedback!.startsWith('Clone failed')
                          ? AppColors.bad
                          : AppColors.good),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_feedback!,
                        style: const TextStyle(
                            color: AppColors.textHigh, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SectionHeader('How clones are made'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HowRow('1',
                    'Analyze — Pixel reads the description, URL or file with '
                    'your configured AI provider.'),
                _HowRow('2',
                    'Adapt — it generates a Pixel no-code skill (JSON step '
                    'graph) as a functional equivalent, not a copy.'),
                _HowRow('3',
                    'Verify — the clone lands in T.B sandbox for pass/fail '
                    'tests before you approve it.'),
                _HowRow('4',
                    'Install — approved clones appear in F.B with a shortcut '
                    'and a G.B safety rating.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HowRow extends StatelessWidget {
  final String n;
  final String text;
  const _HowRow(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: AppColors.textMid, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}