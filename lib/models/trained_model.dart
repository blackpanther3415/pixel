enum ModelStatus { training, ready, failed }

class TrainedModel {
  final String id;
  final String name;
  final String baseModel; // e.g. 'llama-3.2-1b'
  final String method; // 'fine_tune' | 'from_scratch'
  final ModelStatus status;
  final double parametersB; // billions
  final String? dataSourceRef; // kb doc ids used
  final double? loss;
  final int epochs;
  final String? modelPath; // local gguf path
  final DateTime createdAt;
  final DateTime? completedAt;

  const TrainedModel({
    required this.id,
    required this.name,
    required this.baseModel,
    required this.method,
    this.status = ModelStatus.training,
    this.parametersB = 1,
    this.dataSourceRef,
    this.loss,
    this.epochs = 0,
    this.modelPath,
    required this.createdAt,
    this.completedAt,
  });

  TrainedModel copyWith({
    ModelStatus? status,
    double? loss,
    int? epochs,
    String? modelPath,
    DateTime? completedAt,
  }) =>
      TrainedModel(
        id: id,
        name: name,
        baseModel: baseModel,
        method: method,
        status: status ?? this.status,
        parametersB: parametersB,
        dataSourceRef: dataSourceRef,
        loss: loss ?? this.loss,
        epochs: epochs ?? this.epochs,
        modelPath: modelPath ?? this.modelPath,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
        'base': baseModel,
        'method': method,
        'status': status.name,
        'params_b': parametersB,
        'data_ref': dataSourceRef,
        'loss': loss,
        'epochs': epochs,
        'model_path': modelPath,
        'created_at': createdAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory TrainedModel.fromDb(Map<String, Object?> m) => TrainedModel(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Model',
        baseModel: (m['base'] as String?) ?? 'unknown',
        method: (m['method'] as String?) ?? 'fine_tune',
        status: ModelStatus.values.firstWhere(
            (s) => s.name == m['status'],
            orElse: () => ModelStatus.ready),
        parametersB: (m['params_b'] as num?)?.toDouble() ?? 1,
        dataSourceRef: m['data_ref'] as String?,
        loss: (m['loss'] as num?)?.toDouble(),
        epochs: (m['epochs'] as int?) ?? 0,
        modelPath: m['model_path'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
        completedAt: m['completed_at'] == null
            ? null
            : DateTime.tryParse(m['completed_at'] as String),
      );
}