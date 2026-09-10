import 'package:flutter/foundation.dart';

import '../models/provider.dart';
import '../services/builder/plan_build_service.dart';
import '../services/chat/chat_service.dart';
import '../services/cloner/clone_service.dart';
import '../services/database/database_service.dart';
import '../services/graph/graph_runtime.dart';
import '../services/knowledge/kb_service.dart';
import '../services/llm/llm_lab_service.dart';
import '../services/providers/provider_factory.dart';
import '../services/sandbox/sandbox_service.dart';
import '../services/security/security_engine.dart';
import '../services/security/security_gateway.dart';
import '../services/skills/skill_executor.dart';

/// The composition root. Constructed once at app start; passed down via
/// ChangeNotifierProvider so every tab shares one set of live services.
class AppServices {
  final DatabaseService db;
  final SecurityGateway gateway;
  late final ChatService chat;
  late final KbService kb;
  late final SkillExecutor skills;
  late final GraphRuntime graph;
  late final SandboxService sandbox;
  late final CloneService clone;
  late final PlanBuildService builder;
  late final LlmLabService llm;

  AppServices({required this.db, required this.gateway}) {
    chat = ChatService(
      db: db,
      gateway: gateway,
      routerFactory: (prov, m) => SmartRouter(
        () async => db.listProviders(),
        mode: RoutingMode.cheapest,
        budgetUsd: 10,
        overrideProviderId: prov.isEmpty ? null : prov,
        overrideModel: m.isEmpty ? null : m,
      ),
    );
    kb = KbService(db: db, gateway: gateway);
    skills = SkillExecutor(db: db, gateway: gateway);
    graph = GraphRuntime(db: db, gateway: gateway, kb: kb, skills: skills);
    sandbox = SandboxService(db: db, skills: skills, graph: graph, gateway: gateway);
    clone = CloneService(db: db);
    builder = PlanBuildService(db: db);
    llm = LlmLabService(db: db, kb: kb);
  }

  Future<void> init() async {
    await db.init();
    final settings = await db.getSettings();
    gateway.loadLevel(settings);
    await chat.loadFromSettings(settings);
  }

  Future<void> dispose() async {
    await db.close();
  }

  static Future<AppServices> create() async {
    final db = DatabaseService();
    final gateway = SecurityGateway(db: db, engine: const SecurityEngine());
    final services = AppServices(db: db, gateway: gateway);
    await services.init();
    return services;
  }
}

class AppState extends ChangeNotifier {
  final AppServices services;

  AppState(this.services);

  Future<void> refresh() async {
    notifyListeners();
  }
}