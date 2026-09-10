enum ProviderKind { openai, anthropic, google, mistral, ollama, local }

enum RoutingMode { cheapest, fastest }

class ProviderModel {
  final String id;
  final String name;
  final double inputCostPerM; // USD per 1M input tokens (approx, editable)
  final double outputCostPerM; // USD per 1M output tokens
  final double latencyScore; // lower = faster (relative units)
  final int contextWindow;
  final bool supportsStreaming;
  final bool supportsEmbeddings;

  const ProviderModel({
    required this.id,
    required this.name,
    this.inputCostPerM = 0,
    this.outputCostPerM = 0,
    this.latencyScore = 1,
    this.contextWindow = 8192,
    this.supportsStreaming = true,
    this.supportsEmbeddings = false,
  });

  Map<String, Object?> toDb(String providerId) => {
        'provider_id': providerId,
        'model_id': id,
        'name': name,
        'in_per_m': inputCostPerM,
        'out_per_m': outputCostPerM,
        'latency': latencyScore,
        'context': contextWindow,
        'streaming': supportsStreaming ? 1 : 0,
        'embeddings': supportsEmbeddings ? 1 : 0,
      };

  factory ProviderModel.fromDb(Map<String, Object?> m) => ProviderModel(
        id: m['model_id'] as String,
        name: (m['name'] as String?) ?? m['model_id'] as String,
        inputCostPerM: (m['in_per_m'] as num?)?.toDouble() ?? 0,
        outputCostPerM: (m['out_per_m'] as num?)?.toDouble() ?? 0,
        latencyScore: (m['latency'] as num?)?.toDouble() ?? 1,
        contextWindow: (m['context'] as int?) ?? 8192,
        supportsStreaming: (m['streaming'] as int? ?? 1) == 1,
        supportsEmbeddings: (m['embeddings'] as int? ?? 0) == 1,
      );
}

class ProviderConfig {
  final String id;
  final ProviderKind kind;
  final String name;
  final String? apiKey;
  final String? baseUrl; // for Ollama / custom endpoints
  final bool enabled;
  final List<ProviderModel> models;

  const ProviderConfig({
    required this.id,
    required this.kind,
    required this.name,
    this.apiKey,
    this.baseUrl,
    this.enabled = true,
    this.models = const [],
  });

  Map<String, Object?> toDb() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'api_key': apiKey,
        'base_url': baseUrl,
        'enabled': enabled ? 1 : 0,
      };

  factory ProviderConfig.fromDb(Map<String, Object?> m) => ProviderConfig(
        id: m['id'] as String,
        kind: ProviderKind.values.firstWhere(
            (k) => k.name == m['kind'],
            orElse: () => ProviderKind.openai),
        name: (m['name'] as String?) ?? m['id'] as String,
        apiKey: m['api_key'] as String?,
        baseUrl: m['base_url'] as String?,
        enabled: (m['enabled'] as int? ?? 1) == 1,
      );

  ProviderConfig copyWith({
    String? id,
    ProviderKind? kind,
    String? name,
    String? apiKey,
    String? baseUrl,
    bool? enabled,
    List<ProviderModel>? models,
  }) =>
      ProviderConfig(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        enabled: enabled ?? this.enabled,
        models: models ?? this.models,
      );
}