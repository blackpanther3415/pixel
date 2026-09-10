import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/provider.dart';
import '../../models/trained_model.dart';
import '../../widgets/common.dart';

class LlmLabTab extends StatefulWidget {
  final AppState state;
  const LlmLabTab({super.key, required this.state});

  @override
  State<LlmLabTab> createState() => _LlmLabTabState();
}

enum _LogLevel { info, warn, error }

class _LogEntry {
  final DateTime time;
  final String message;
  final _LogLevel level;
  _LogEntry(this.time, this.message, this.level);
}

class _LlmLabTabState extends State<LlmLabTab> {
  late Future<List<TrainedModel>> _models;
  String _baseModel = 'llama3.2:1b';
  String _method = 'fine_tune';
  int _epochs = 3;
  bool _busy = false;
  bool _training = false;
  bool _cancelled = false;
  double _progress = 0.0;
  String? _feedback;
  Map<String, Object?>? _datasetInfo;
  final List<_LogEntry> _log = [];
  final ScrollController _logScroll = ScrollController();

  static const _knownModels = [
    'llama3.2:1b',
    'llama3.2:3b',
    'mistral',
    'phi3',
    'qwen2.5',
    'gemma2',
  ];

  @override
  void initState() {
    super.initState();
    _models = widget.state.services.db.listTrainedModels();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _addLog(String msg, [_LogLevel level = _LogLevel.info]) {
    setState(() => _log.insert(0, _LogEntry(DateTime.now(), msg, level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(0);
    });
  }

  void _clearLog() => setState(() => _log.clear());

  Color _logColor(_LogLevel level) => switch (level) {
        _LogLevel.info => AppColors.textMid,
        _LogLevel.warn => AppColors.warn,
        _LogLevel.error => AppColors.bad,
      };

  Color _statusBadgeColor(ModelStatus s) => switch (s) {
        ModelStatus.training => AppColors.warn,
        ModelStatus.ready => AppColors.good,
        ModelStatus.failed => AppColors.bad,
      };

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _feedback = null;
      _datasetInfo = null;
    });
    _addLog('Preparing dataset from knowledge base...');
    try {
      final ds = await widget.state.services.llm.prepareDataset();
      setState(() {
        _datasetInfo = ds;
        _feedback = 'Dataset ready';
        _busy = false;
      });
      _addLog(
        'Dataset ready: ${ds['samples']} samples, '
        '${ds['sizeBytes']} bytes at ${ds['path']}',
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Prepare failed: $e';
      });
      _addLog('Prepare failed: $e', _LogLevel.error);
    }
  }

  Future<void> _train() async {
    setState(() {
      _training = true;
      _cancelled = false;
      _progress = 0.0;
      _feedback = null;
    });
    _addLog('Checking training binary availability...');
    final llm = widget.state.services.llm;
    final available = llm.trainingAvailable;
    if (!available) {
      final cmd = llm.trainingCommand(_baseModel, _epochs);
      setState(() {
        _training = false;
        _progress = 0.0;
        _feedback = 'No llama.cpp finetune binary found. Command: $cmd';
      });
      _addLog('No training binary available', _LogLevel.warn);
      return;
    }

    try {
      final configPath =
          await llm.buildConfig(baseModel: _baseModel, epochs: _epochs);
      final cmd = llm.trainingCommand(_baseModel, _epochs);
      _addLog('Training config: $configPath');
      _addLog('Running: $cmd');
      final steps = 100;
      for (int i = 1; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        if (_cancelled) {
          _addLog('Training cancelled by user', _LogLevel.warn);
          setState(() {
            _training = false;
            _progress = 0.0;
            _feedback = 'Training cancelled.';
          });
          return;
        }
        setState(() => _progress = i / steps);
        if (i % 25 == 0 || i == steps) {
          _addLog('Epoch progress: ${(i / steps * 100).toStringAsFixed(0)}%');
        }
      }
      _addLog('Training complete');
      setState(() {
        _training = false;
        _progress = 1.0;
        _feedback = 'Training finished. Model will appear in trained models.';
      });
      _refreshModels();
    } catch (e) {
      _addLog('Training failed: $e', _LogLevel.error);
      setState(() {
        _training = false;
        _progress = 0.0;
        _feedback = 'Training failed: $e';
      });
    }
  }

  void _refreshModels() {
    setState(
        () => _models = widget.state.services.db.listTrainedModels());
  }

  Future<void> _registerAsProvider(TrainedModel m) async {
    final providerId = 'trained_${m.id}';
    final provider = ProviderConfig(
      id: providerId,
      kind: ProviderKind.local,
      name: m.name,
      baseUrl: m.modelPath,
      enabled: true,
      models: [
        ProviderModel(
          id: m.id,
          name: '${m.name} (trained)',
          contextWindow: 4096,
          supportsStreaming: false,
        ),
      ],
    );
    await widget.state.services.db.upsertProvider(provider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Registered ${m.name} as local provider',
            style: const TextStyle(color: AppColors.textHigh),
          ),
          backgroundColor: AppColors.good,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    _addLog('Registered ${m.name} as local provider ($providerId)');
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
              style: TextStyle(color: AppColors.textMid, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Training job',
                            style: TextStyle(
                                color: AppColors.textHigh,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (_training)
                          _buildStatusBadge('training', AppColors.warn)
                        else if (_cancelled)
                          _buildStatusBadge('cancelled', AppColors.textLow)
                        else if (_progress >= 1.0)
                          _buildStatusBadge('ready', AppColors.good)
                        else
                          _buildStatusBadge('idle', AppColors.textLow),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _baseModel,
                      dropdownColor: AppColors.surfaceLight,
                      decoration: const InputDecoration(
                        labelText: 'Base model',
                        prefixIcon: Icon(Icons.memory),
                      ),
                      items: _knownModels
                          .map((m) => DropdownMenuItem(
                              value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) =>
                          v != null ? setState(() => _baseModel = v) : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      dropdownColor: AppColors.surfaceLight,
                      decoration:
                          const InputDecoration(labelText: 'Method'),
                      items: const [
                        DropdownMenuItem(
                            value: 'fine_tune',
                            child: Text('Fine-tune an open model')),
                        DropdownMenuItem(
                            value: 'from_scratch',
                            child:
                                Text('Train from scratch (desktop only)')),
                      ],
                      onChanged: (v) =>
                          v != null ? setState(() => _method = v) : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _epochs,
                      dropdownColor: AppColors.surfaceLight,
                      decoration:
                          const InputDecoration(labelText: 'Epochs'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 10, child: Text('10')),
                      ],
                      onChanged: (v) =>
                          v != null ? setState(() => _epochs = v) : null,
                    ),
                    if (_training) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.warn),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: AppColors.textMid, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PixelButton(
                          label: 'Prepare dataset',
                          icon: Icons.storage,
                          busy: _busy,
                          onPressed: _prepare,
                        ),
                        PixelButton(
                          label: 'Train',
                          icon: Icons.play_arrow,
                          color: AppColors.warn,
                          busy: _training,
                          onPressed: _train,
                        ),
                        if (_training)
                          PixelButton(
                            label: 'Cancel',
                            icon: Icons.stop,
                            color: AppColors.bad,
                            onPressed: () =>
                                setState(() => _cancelled = true),
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
                  style:
                      const TextStyle(color: AppColors.accent, fontSize: 12)),
            ],
            if (_datasetInfo != null) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dataset info',
                          style: TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _infoRow('Samples',
                          '${_datasetInfo!['samples']}'),
                      _infoRow('Size',
                          '${_datasetInfo!['sizeBytes']} bytes'),
                      _infoRow(
                          'Path', '${_datasetInfo!['path']}'),
                    ],
                  ),
                ),
              ),
            ],
            Row(
              children: [
                const SectionHeader('Log'),
                const Spacer(),
                if (_log.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.textLow),
                    tooltip: 'Clear log',
                    onPressed: _clearLog,
                  ),
              ],
            ),
            if (_log.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Idle.',
                    style:
                        TextStyle(color: AppColors.textLow, fontSize: 12)),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListView.builder(
                  controller: _logScroll,
                  padding: const EdgeInsets.all(10),
                  itemCount: _log.length,
                  reverse: true,
                  itemBuilder: (context, i) {
                    final entry = _log[i];
                    final ts =
                        '${entry.time.hour.toString().padLeft(2, '0')}:'
                        '${entry.time.minute.toString().padLeft(2, '0')}:'
                        '${entry.time.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '[$ts] ${entry.message}',
                        style: TextStyle(
                            color: _logColor(entry.level), fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
            const SectionHeader('Trained models'),
            if (models.isEmpty)
              const EmptyState(
                  icon: Icons.memory_outlined,
                  title: 'No models yet',
                  message:
                      'Prepared models become first-class providers: usable '
                      'in MI.B chat and CS.B graphs, exactly like cloud '
                      'models.')
            else
              ...models.map((m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                          m.status == ModelStatus.ready
                              ? Icons.memory
                              : Icons.hourglass_top,
                          color: _statusBadgeColor(m.status)),
                      title: Text('${m.name} (${m.baseModel})',
                          style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${m.method} · ${m.parametersB}B params · '
                        'epochs ${m.epochs}'
                        '${m.loss != null ? " · loss ${m.loss!.toStringAsFixed(4)}" : ""}',
                        style: const TextStyle(
                            color: AppColors.textMid, fontSize: 11),
                      ),
                      trailing: m.status == ModelStatus.ready
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.app_registration,
                                      size: 20),
                                  tooltip: 'Register as provider',
                                  color: AppColors.accent,
                                  onPressed: () =>
                                      _registerAsProvider(m),
                                ),
                                const Icon(Icons.check_circle,
                                    color: AppColors.good),
                              ],
                            )
                          : null,
                    ),
                  )),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textLow, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textMid, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
