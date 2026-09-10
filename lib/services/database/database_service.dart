import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/chat_message.dart';
import '../../models/feature.dart';
import '../../models/graph_node.dart';
import '../../models/kb_document.dart';
import '../../models/provider.dart';
import '../../models/security_event.dart';
import '../../models/skill.dart';
import '../../models/trained_model.dart';

class AppSettings {
  final String securityLevel; // low | medium | high | custom
  final String routingMode; // cheapest | fastest
  final double monthlyBudgetUsd;
  final bool voiceEnabled;
  final String defaultProviderId;
  final String defaultModel;

  const AppSettings({
    this.securityLevel = 'medium',
    this.routingMode = 'cheapest',
    this.monthlyBudgetUsd = 10,
    this.voiceEnabled = true,
    this.defaultProviderId = '',
    this.defaultModel = '',
  });

  AppSettings copyWith({
    String? securityLevel,
    String? routingMode,
    double? monthlyBudgetUsd,
    bool? voiceEnabled,
    String? defaultProviderId,
    String? defaultModel,
  }) =>
      AppSettings(
        securityLevel: securityLevel ?? this.securityLevel,
        routingMode: routingMode ?? this.routingMode,
        monthlyBudgetUsd: monthlyBudgetUsd ?? this.monthlyBudgetUsd,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        defaultProviderId: defaultProviderId ?? this.defaultProviderId,
        defaultModel: defaultModel ?? this.defaultModel,
      );

  Map<String, Object?> toDb() => {
        'key': 'app_settings',
        'value': jsonEncode({
          'security_level': securityLevel,
          'routing_mode': routingMode,
          'budget': monthlyBudgetUsd,
          'voice': voiceEnabled,
          'provider': defaultProviderId,
          'model': defaultModel,
        }),
      };

  static AppSettings fromDb(Map<String, Object?> m) {
    try {
      final Map<String, dynamic> v =
          jsonDecode(m['value'] as String) as Map<String, dynamic>;
      return AppSettings(
        securityLevel: (v['security_level'] as String?) ?? 'medium',
        routingMode: (v['routing_mode'] as String?) ?? 'cheapest',
        monthlyBudgetUsd: ((v['budget'] as num?) ?? 10).toDouble(),
        voiceEnabled: (v['voice'] as bool?) ?? true,
        defaultProviderId: (v['provider'] as String?) ?? '',
        defaultModel: (v['model'] as String?) ?? '',
      );
    } catch (_) {
      return const AppSettings();
    }
  }
}

class DatabaseService {
  Database? _db;
  String? _lastPath;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('DatabaseService not initialized. Call init() first.');
    }
    return d;
  }

  Future<void> init({String? vaultPassphrase, String? testPath}) async {
    if (_db != null) return;
    sqfliteFfiInit();
    if (testPath != null) {
      _lastPath = testPath;
    } else {
      try {
        // prefer real device path when available
        final dir = await getApplicationSupportDirectory();
        _lastPath = p.join(dir.path, 'pixel.db');
      } catch (_) {
        _lastPath = p.join(Directory.systemTemp.path, 'pixel.db');
      }
    }
    _db = await openDatabase(
      _lastPath!,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) => _createSchema(db),
    );
    await _seedDefaults();
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        provider_id TEXT,
        model TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        provider_id TEXT,
        model TEXT,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        created_at TEXT NOT NULL,
        blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        name TEXT NOT NULL,
        api_key TEXT,
        base_url TEXT,
        enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE models (
        provider_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        name TEXT NOT NULL,
        in_per_m REAL NOT NULL DEFAULT 0,
        out_per_m REAL NOT NULL DEFAULT 0,
        latency REAL NOT NULL DEFAULT 1,
        context INTEGER NOT NULL DEFAULT 8192,
        streaming INTEGER NOT NULL DEFAULT 1,
        embeddings INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (provider_id, model_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE security_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        verdict TEXT NOT NULL,
        level TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0,
        summary TEXT NOT NULL DEFAULT '',
        detail TEXT NOT NULL DEFAULT '',
        direction TEXT NOT NULL DEFAULT 'inbound',
        route TEXT,
        suggestion TEXT,
        resolved INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE quarantine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER,
        original TEXT NOT NULL,
        sanitized TEXT,
        source TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE kb_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        title TEXT NOT NULL,
        uri TEXT,
        raw_path TEXT,
        mime TEXT NOT NULL DEFAULT 'text/plain',
        status TEXT NOT NULL DEFAULT 'processing',
        error TEXT,
        chunks INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE kb_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id INTEGER NOT NULL REFERENCES kb_documents(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        text TEXT NOT NULL,
        embedding TEXT,
        source_ref TEXT
      )
    ''');
    await db.execute('''
      CREATE VIRTUAL TABLE kb_fts USING fts5(text, content='kb_chunks', content_rowid='id')
    ''');
    await db.execute('''
      CREATE TRIGGER kb_chunks_ai AFTER INSERT ON kb_chunks BEGIN
        INSERT INTO kb_fts(rowid, text) VALUES (new.id, new.text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER kb_chunks_ad AFTER DELETE ON kb_chunks BEGIN
        INSERT INTO kb_fts(kb_fts, rowid, text) VALUES('delete', old.id, old.text);
      END
    ''');
    await db.execute('''
      CREATE TABLE skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'noCode',
        status TEXT NOT NULL DEFAULT 'draft',
        code TEXT,
        graph_json TEXT,
        version TEXT,
        safety INTEGER NOT NULL DEFAULT 100,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE skill_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        skill_id TEXT NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
        status TEXT NOT NULL DEFAULT 'running',
        input TEXT,
        output TEXT,
        error TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE features (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'builtin',
        enabled INTEGER NOT NULL DEFAULT 1,
        favorite INTEGER NOT NULL DEFAULT 0,
        safety INTEGER NOT NULL DEFAULT 100,
        usage INTEGER NOT NULL DEFAULT 0,
        dependencies TEXT,
        shortcut TEXT,
        created_at TEXT NOT NULL,
        last_used TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE trained_models (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'fine_tune',
        status TEXT NOT NULL DEFAULT 'training',
        params_b REAL NOT NULL DEFAULT 1,
        data_ref TEXT,
        loss REAL,
        epochs INTEGER NOT NULL DEFAULT 0,
        model_path TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE graph_nodes (
        flow_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        type TEXT NOT NULL,
        label TEXT NOT NULL,
        x REAL NOT NULL DEFAULT 0,
        y REAL NOT NULL DEFAULT 0,
        config TEXT,
        PRIMARY KEY (flow_id, node_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE graph_edges (
        flow_id TEXT NOT NULL,
        edge_id TEXT NOT NULL,
        from_node TEXT NOT NULL,
        to_node TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (flow_id, edge_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedDefaults() async {
    await db.insert('providers', {
      'id': 'openai',
      'kind': 'openai',
      'name': 'OpenAI',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('providers', {
      'id': 'anthropic',
      'kind': 'anthropic',
      'name': 'Anthropic',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('providers', {
      'id': 'google',
      'kind': 'google',
      'name': 'Google Gemini',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('providers', {
      'id': 'mistral',
      'kind': 'mistral',
      'name': 'Mistral',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('providers', {
      'id': 'ollama',
      'kind': 'ollama',
      'name': 'Ollama (Local)',
      'base_url': 'http://localhost:11434',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    const defaults = {
      'openai': [
        ProviderModel(id: 'gpt-4o-mini', name: 'GPT-4o mini', inputCostPerM: 0.15, outputCostPerM: 0.60, latencyScore: 0.6, contextWindow: 128000),
        ProviderModel(id: 'gpt-4o', name: 'GPT-4o', inputCostPerM: 2.5, outputCostPerM: 10.0, latencyScore: 1.0, contextWindow: 128000),
        ProviderModel(id: 'gpt-4.1-mini', name: 'GPT-4.1 mini', inputCostPerM: 0.4, outputCostPerM: 1.6, latencyScore: 0.7, contextWindow: 1000000),
      ],
      'anthropic': [
        ProviderModel(id: 'claude-3-5-haiku-latest', name: 'Claude 3.5 Haiku', inputCostPerM: 0.8, outputCostPerM: 4.0, latencyScore: 0.7, contextWindow: 200000),
        ProviderModel(id: 'claude-3-5-sonnet-latest', name: 'Claude 3.5 Sonnet', inputCostPerM: 3.0, outputCostPerM: 15.0, latencyScore: 1.0, contextWindow: 200000),
      ],
      'google': [
        ProviderModel(id: 'gemini-2.0-flash', name: 'Gemini 2.0 Flash', inputCostPerM: 0.1, outputCostPerM: 0.4, latencyScore: 0.5, contextWindow: 1000000),
        ProviderModel(id: 'gemini-2.0-pro', name: 'Gemini 2.0 Pro', inputCostPerM: 1.25, outputCostPerM: 5.0, latencyScore: 1.1, contextWindow: 2000000),
      ],
      'mistral': [
        ProviderModel(id: 'mistral-large-latest', name: 'Mistral Large', inputCostPerM: 2.0, outputCostPerM: 6.0, latencyScore: 1.0, contextWindow: 128000),
        ProviderModel(id: 'open-mistral-nemo', name: 'Mistral Nemo', inputCostPerM: 0.15, outputCostPerM: 0.15, latencyScore: 0.8, contextWindow: 128000),
      ],
      'ollama': [
        ProviderModel(id: 'llama3.2', name: 'Llama 3.2 (local)', inputCostPerM: 0, outputCostPerM: 0, latencyScore: 2.0, contextWindow: 8192),
        ProviderModel(id: 'mistral', name: 'Mistral (local)', inputCostPerM: 0, outputCostPerM: 0, latencyScore: 2.2, contextWindow: 8192),
      ],
    };
    final batch = db.batch();
    defaults.forEach((prov, models) {
      for (final m in models) {
        batch.insert('models', m.toDb(prov),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await batch.commit(noResult: true);

    await db.insert('settings', const AppSettings().toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- settings ----------
  Future<AppSettings> getSettings() async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: ['app_settings']);
    return rows.isEmpty
        ? const AppSettings()
        : AppSettings.fromDb(rows.first);
  }

  Future<void> saveSettings(AppSettings s) async {
    await db.insert('settings', s.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- chats / messages ----------
  Future<int> createChat(String title, {String? providerId, String? model}) async {
    return db.insert('chats', {
      'title': title,
      'provider_id': providerId,
      'model': model,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> listChats() async {
    final rows = await db.query('chats', orderBy: 'created_at DESC');
    return [
      for (final r in rows)
        {
          ...r,
          'count': Sqflite.firstIntValue(
                  await db.rawQuery(
                      'SELECT COUNT(*) FROM messages WHERE chat_id = ?', [r['id']])) ??
              0,
        }
    ].cast<Map<String, Object?>>();
  }

  Future<void> deleteChat(int id) async {
    await db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> listMessages(int chatId) async {
    final rows = await db.query('messages',
        where: 'chat_id = ?', whereArgs: [chatId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromDb).toList();
  }

  Future<int> insertMessage(ChatMessage m) =>
      db.insert('messages', m.toDb());

  Future<void> updateMessage(ChatMessage m) async {
    await db.update('messages', m.toDb(),
        where: 'id = ?',
        whereArgs: [m.id],
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- providers ----------
  Future<List<ProviderConfig>> listProviders() async {
    final rows = await db.query('providers', orderBy: 'enabled DESC, name');
    final out = <ProviderConfig>[];
    for (final r in rows) {
      final models = (await db.query('models',
              where: 'provider_id = ?',
              whereArgs: [r['id']]))
          .map(ProviderModel.fromDb)
          .toList();
      out.add(ProviderConfig.fromDb(r).copyWith(models: models));
    }
    return out;
  }

  Future<void> upsertProvider(ProviderConfig p) async {
    await db.insert('providers', p.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    final batch = db.batch();
    for (final m in p.models) {
      batch.insert('models', m.toDb(p.id),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteProvider(String id) async {
    await db.delete('providers', where: 'id = ?', whereArgs: [id]);
    await db.delete('models', where: 'provider_id = ?', whereArgs: [id]);
  }

  // ---------- security ----------
  Future<int> insertSecurityEvent(SecurityEvent e) =>
      db.insert('security_events', e.toDb());

  Future<void> insertQuarantine({
    required int eventId,
    required String original,
    String? sanitized,
    String? source,
  }) =>
      db.insert('quarantine', {
        'event_id': eventId,
        'original': original,
        'sanitized': sanitized,
        'source': source,
        'created_at': DateTime.now().toIso8601String(),
      });

  Future<List<SecurityEvent>> listSecurityEvents({int limit = 200}) async {
    final rows = await db.query('security_events',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(SecurityEvent.fromDb).toList();
  }

  Future<List<SecurityEvent>> listSecurityEventsByVerdict(
      String verdict, {int limit = 200}) async {
    final rows = await db.query('security_events',
        where: 'verdict = ?',
        whereArgs: [verdict],
        orderBy: 'created_at DESC',
        limit: limit);
    return rows.map(SecurityEvent.fromDb).toList();
  }

  Future<Map<String, int>> securityStats() async {
    final rows = await db.rawQuery(
        'SELECT verdict, COUNT(*) c FROM security_events GROUP BY verdict');
    return {
      for (final r in rows) r['verdict'] as String: r['c'] as int,
    };
  }

  Future<List<Map<String, Object?>>> listQuarantine({int limit = 100}) async {
    return db.query('quarantine', orderBy: 'created_at DESC', limit: limit);
  }

  // ---------- knowledge base ----------
  Future<int> insertKbDocument(KbDocument d) =>
      db.insert('kb_documents', d.toDb());

  Future<void> updateKbDocument(KbDocument d) async {
    await db.update('kb_documents', d.toDb(),
        where: 'id = ?', whereArgs: [d.id]);
  }

  Future<List<KbDocument>> listKbDocuments() async {
    final rows = await db.query('kb_documents', orderBy: 'created_at DESC');
    return rows.map(KbDocument.fromDb).toList();
  }

  Future<void> insertKbChunks(List<KbChunk> chunks) async {
    final batch = db.batch();
    for (final c in chunks) {
      batch.insert('kb_chunks', c.toDb());
    }
    await batch.commit(noResult: true);
  }

  Future<List<KbChunk>> kbChunksForDoc(int docId) async {
    final rows = await db.query('kb_chunks',
        where: 'doc_id = ?', whereArgs: [docId], orderBy: 'idx ASC');
    return rows.map(KbChunk.fromDb).toList();
  }

  Future<List<KbChunk>> kbSearch(String query, {int limit = 20}) async {
    final safe = query.replaceAll('"', ' ').replaceAll("'", ' ');
    try {
      final rows = await db.rawQuery('''
        SELECT kb_chunks.*, kb_documents.title AS doc_title
        FROM kb_fts
        JOIN kb_chunks ON kb_chunks.id = kb_fts.rowid
        JOIN kb_documents ON kb_documents.id = kb_chunks.doc_id
        WHERE kb_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      ''', ['"$safe"', limit]);
      return rows.map(KbChunk.fromDb).toList();
    } catch (_) {
      // fallback: LIKE scan for simple queries
      final rows = await db.rawQuery(
          'SELECT * FROM kb_chunks WHERE text LIKE ? LIMIT ?',
          ['%$query%', limit]);
      return rows.map(KbChunk.fromDb).toList();
    }
  }

  Future<List<KbChunk>> allKbChunks({int limit = 1000}) async {
    final rows =
        await db.query('kb_chunks', orderBy: 'idx ASC', limit: limit);
    return rows.map(KbChunk.fromDb).toList();
  }

  Future<void> deleteKbDocument(int docId) async {
    await db.delete('kb_documents', where: 'id = ?', whereArgs: [docId]);
  }

  // ---------- skills ----------
  Future<void> upsertSkill(Skill s) => db.insert('skills', s.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Skill>> listSkills() async {
    final rows = await db.query('skills', orderBy: 'updated_at DESC');
    return rows.map(Skill.fromDb).toList();
  }

  Future<void> deleteSkill(String id) =>
      db.delete('skills', where: 'id = ?', whereArgs: [id]);

  Future<int> insertSkillRun(SkillRun r) => db.insert('skill_runs', r.toDb());

  Future<List<SkillRun>> skillRuns(String skillId) async {
    final rows = await db.query('skill_runs',
        where: 'skill_id = ?', whereArgs: [skillId], orderBy: 'created_at DESC');
    return rows.map(SkillRun.fromDb).toList();
  }

  // ---------- features ----------
  Future<void> upsertFeature(Feature f) => db.insert('features', f.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Feature>> listFeatures() async {
    final rows = await db.query('features', orderBy: 'favorite DESC, name');
    return rows.map(Feature.fromDb).toList();
  }

  Future<void> deleteFeature(String id) =>
      db.delete('features', where: 'id = ?', whereArgs: [id]);

  // ---------- trained models ----------
  Future<void> upsertTrainedModel(TrainedModel m) =>
      db.insert('trained_models', m.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<TrainedModel>> listTrainedModels() async {
    final rows = await db.query('trained_models', orderBy: 'created_at DESC');
    return rows.map(TrainedModel.fromDb).toList();
  }

  // ---------- graph ----------
  Future<Map<String, Object?>?> graphFlowMeta(String flowId) async {
    final rows = await db.query('graph_nodes',
        where: 'flow_id = ?', whereArgs: [flowId], limit: 1);
    return rows.isEmpty ? null : {'flow_id': flowId};
  }

  Future<Map<String, Object?>> saveGraphFlow(
      String flowId, String name, List<GraphNode> nodes, List<GraphEdge> edges) async {
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: ['flow_meta_$flowId']);
    if (rows.isEmpty) {
      await db.insert('settings', {
        'key': 'flow_meta_$flowId',
        'value': jsonEncode({'name': name}),
      });
    } else {
      await db.update('settings', {
        'value': jsonEncode({'name': name}),
      }, where: 'key = ?', whereArgs: ['flow_meta_$flowId']);
    }
    await db.delete('graph_nodes', where: 'flow_id = ?', whereArgs: [flowId]);
    await db.delete('graph_edges', where: 'flow_id = ?', whereArgs: [flowId]);
    final batch = db.batch();
    for (final n in nodes) {
      batch.insert('graph_nodes', {...n.toDb(), 'flow_id': flowId});
    }
    for (final e in edges) {
      batch.insert('graph_edges', {...e.toDb(), 'flow_id': flowId});
    }
    await batch.commit(noResult: true);
    return {'flow_id': flowId};
  }

  Future<String> graphFlowName(String flowId) async {
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: ['flow_meta_$flowId']);
    try {
      final v = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
      return (v['name'] as String?) ?? flowId;
    } catch (_) {
      return flowId;
    }
  }

  Future<List<GraphNode>> graphNodes(String flowId) async {
    final rows = await db.query('graph_nodes',
        where: 'flow_id = ?', whereArgs: [flowId], orderBy: 'x, y');
    return rows.map(GraphNode.fromDb).toList();
  }

  Future<List<GraphEdge>> graphEdges(String flowId) async {
    final rows = await db.query('graph_edges',
        where: 'flow_id = ?', whereArgs: [flowId]);
    return rows.map(GraphEdge.fromDb).toList();
  }

  Future<List<String>> graphFlowIds() async {
    final rows = await db.query('settings',
        where: "key LIKE 'flow_meta_%'", orderBy: 'key');
    return [
      for (final r in rows) (r['key'] as String).substring('flow_meta_'.length)
    ];
  }

  // ---------- usage ----------
  Future<Map<String, Object?>> usageStats() async {
    final r = await db.rawQuery('''
      SELECT COUNT(*) msgs,
             COALESCE(SUM(prompt_tokens), 0) prompts,
             COALESCE(SUM(completion_tokens), 0) completions
      FROM messages
    ''');
    final tokens = await db.rawQuery(
        "SELECT COALESCE(SUM(prompt_tokens),0) + COALESCE(SUM(completion_tokens),0) t, COUNT(*) c FROM messages GROUP BY provider_id");
    return {
      'messages': (r.first['msgs'] as num?)?.toInt() ?? 0,
      'promptTokens': (r.first['prompts'] as num?)?.toInt() ?? 0,
      'completionTokens': (r.first['completions'] as num?)?.toInt() ?? 0,
      'byProvider': tokens,
    };
  }

  Future<void> close() async => _db?.close();
}