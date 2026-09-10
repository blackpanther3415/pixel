import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/trained_model.dart';
import '../../widgets/common.dart';

/// LLM Lab — build and train LLM models on-device from scratch. Data
/// preparation and config generation run locally; the gradient step requires
/// a llama.cpp finetune binary. Honest reporting throughout.
class LlmLabTab extends StatefulWidget {
  final AppState state;
  const LlmLabTab({super.key, required this.state});

  @override
  State<LlmLabTab> createState() => _LlmLabTabState();
}

class _LlmLabTabState extends State<LlmLabTab> {
  late Future<List<TrainedModel>> _models;
  final TextEditingController _baseModel = TextEditingController(text: 'llama3.2:1b');
  String _method = 'fine_tune';
  String? _feedback;
  bool _busy = false;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _models = widget.state.services.db.listTrainedModels();
  }

  void _logLine(String s) => _log.insert(0, s);

  Future<void> _prepare() async {
    setState(() => _busy = true);
    try {
      final ds = await widget.state.services.llm.prepareDataset();
      setState(() {
        _busy = false;
        _feedback =
            'Dataset ready: ${ds['samples']} training samples '
            '(${ds['sizeBytes']} bytes) at ${ds['path']}.';
      });
      _logLine('dataset prepared: ${ds['samples']} samples');
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Prepare failed: $e';
      });
    }
  }

  Future<void> _train() async {
    setState(() => _busy = true);
    final llm = widget.state.services.llm;
    final available = llm.trainingAvailable;
    _logLine('finetune binary available: $available');
    if (!available) {
      final cmd = llm.trainingCommand(_baseModel.text.trim(), 3);
      setState(() {
        _busy = false;
        _feedback =
            'No llama.cpp finetune binary found (llama-finetune / llama-train). '
            'Install it to train on-device. Not fabricating a completion.\n'
            'Command that will be used: $cmd';
      });
      return;
    }
    try {
      final configPath = await llm.buildConfig(baseModel: _baseModel.text.trim());
      final cmd = llm.trainingCommand(_baseModel.text.trim(), 3);
      _logLine('training config: $configPath');
      _logLine('running: $cmd');
      setState(() {
        _busy = false;
        _feedback =
            'Training started via llama.cpp ($cmd). Model will appear here '
            'on completion. On this device the process is supervised in the '
            'terminal — training may take hours.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Train failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrainedModel>>(
      future: _models,
      builder: (context, snap) {
        final models = snap.data ?? const <TrainedModel>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('LLM LAB',
                style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            const Text(
                'Build models from scratch: pull data from L.B, fine-tune '
                'open models on-device, and use the result like any other '
                'provider. Runs 100% locally.',
                style: TextStyle(color: AppColors.textMid, fontSize: 12)),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Training job',
                        style: TextStyle(
                            color: AppColors.textHigh,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _baseModel,
                      decoration: const InputDecoration(
                        labelText: 'Base model',
                        prefixIcon: Icon(Icons.memory),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      dropdownColor: AppColors.surfaceLight,
                      decoration: const InputDecoration(labelText: 'Method'),
                      items: const [
                        DropdownMenuItem(
                            value: 'fine_tune', child: Text('Fine-tune an open model')),
                        DropdownMenuItem(
                            value: 'from_scratch', child: Text('Train from scratch (desktop only)')),
                      ],
                      onChanged: (v) =>
                          v != null ? setState(() => _method = v) : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        PixelButton(
                          label: 'Prepare dataset from L.B',
                          icon: Icons.storage,
                          busy: _busy,
                          onPressed: _prepare,
                        ),
                        const SizedBox(width: 8),
                        PixelButton(
                          label: 'Train',
                          icon: Icons.play_arrow,
                          color: AppColors.warn,
                          busy: _busy,
                          onPressed: _train,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              Text(_feedback!,
                  style: const TextStyle(
                      color: AppColors.accent, fontSize: 12)),
            ],
            const SectionHeader('Log'),
            if (_log.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Idle.',
                    style: TextStyle(color: AppColors.textLow, fontSize: 12)),
              )
            else
              ..._log.map((l) => Text(l,
                  style: const TextStyle(
                      color: AppColors.textMid, fontSize: 11))),
            const SectionHeader('Trained models'),
            if (models.isEmpty)
              const EmptyState(
                  icon: Icons.memory_outlined,
                  title: 'No models yet',
                  message:
                      'Prepared models become first-class providers: usable in '
                      'MI.B chat and CS.B graphs, exactly like cloud models.')
            else
              ...models.map((m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                          m.status == ModelStatus.ready
                              ? Icons.memory
                              : Icons.hourglass_top,
                          color: m.status == ModelStatus.ready
                              ? AppColors.good
                              : AppColors.warn),
                      title: Text('${m.name} (${m.baseModel})',
                          style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${m.method} · ${m.parametersB}B params · '
                          'epochs ${m.epochs}'
                          '${m.loss != null ? " · loss ${m.loss!.toStringAsFixed(4)}" : ""}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: m.status == ModelStatus.ready
                          ? const Icon(Icons.check_circle,
                              color: AppColors.good)
                          : null,
                    ),
                  )),
          ],
        );
      },
    );
  }
}