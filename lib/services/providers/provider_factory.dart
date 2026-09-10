import 'dart:async';

import '../../models/provider.dart';
import 'anthropic_provider.dart';
import 'google_provider.dart';
import 'mistral_provider.dart';
import 'ollama_provider.dart';
import 'openai_provider.dart';
import 'provider_client.dart';

/// Factory that instantiates the correct adapter for a provider config.
class ProviderFactory {
  static ProviderClient create(ProviderConfig c) => switch (c.kind) {
        ProviderKind.openai => OpenAIProvider(config: c),
        ProviderKind.anthropic => AnthropicProvider(config: c),
        ProviderKind.google => GoogleProvider(config: c),
        ProviderKind.mistral => MistralProvider(config: c),
        ProviderKind.ollama ||
        ProviderKind.local =>
          OllamaProvider(config: c),
      };
}

class RoutedTarget {
  final ProviderConfig provider;
  final ProviderModel model;

  RoutedTarget({required this.provider, required this.model});

  /// Estimated USD cost for this round trip.
  double estimateCost(int inputTokens, int outputTokens) =>
      (inputTokens / 1e6) * model.inputCostPerM +
      (outputTokens / 1e6) * model.outputCostPerM;

  @override
  String toString() => '${provider.name}/${model.id}';
}

/// The Smart Router: picks the best provider+model for a request based on
/// RoutingMode (cheapest | fastest) with an optional budget cap.
class SmartRouter {
  final Future<List<ProviderConfig>> Function() _providers;
  final RoutingMode _mode;
  final double _budgetUsd;
  final String? _overrideProviderId;
  final String? _overrideModel;

  SmartRouter(
    this._providers, {
    RoutingMode mode = RoutingMode.cheapest,
    double budgetUsd = 100,
    String? overrideProviderId,
    String? overrideModel,
  })  : _mode = mode,
        _budgetUsd = budgetUsd,
        _overrideProviderId = overrideProviderId,
        _overrideModel = overrideModel;

  bool get hasManualOverride =>
      _overrideProviderId != null && _overrideProviderId.isNotEmpty;

  Future<RoutedTarget?> route({
    int inputTokens = 100,
    int outputTokens = 200,
  }) async {
    // 1) explicit override (manual selection in MI.B)
    if (hasManualOverride) {
      final provs = await _providers();
      final p = provs.where((p) => p.id == _overrideProviderId).firstOrNull;
      if (p != null) {
        final model =
            (_overrideModel != null && _overrideModel.isNotEmpty)
                ? p.models.where((m) => m.id == _overrideModel).firstOrNull
                : p.models.firstOrNull;
        if (model != null) return RoutedTarget(provider: p, model: model);
      }
    }

    final provs = (await _providers()).where((p) => p.enabled).toList();
    final candidates = <RoutedTarget>[];
    for (final p in provs) {
      final hasKey = p.kind == ProviderKind.ollama ||
          p.kind == ProviderKind.local ||
          (p.apiKey?.isNotEmpty ?? false);
      if (!hasKey) continue;
      for (final m in p.models) {
        candidates.add(RoutedTarget(provider: p, model: m));
      }
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ca = a.estimateCost(inputTokens, outputTokens);
      final cb = b.estimateCost(inputTokens, outputTokens);
      return switch (_mode) {
        RoutingMode.cheapest => ca.compareTo(cb),
        RoutingMode.fastest => a.model.latencyScore.compareTo(b.model.latencyScore),
      };
    });

    // Respect budget: cheapest acceptable, otherwise fastest within plan.
    if (_mode == RoutingMode.cheapest) {
      final best = candidates.first;
      return best.estimateCost(inputTokens, outputTokens) <= _budgetUsd
          ? best
          : null;
    }
    return candidates.first;
  }
}