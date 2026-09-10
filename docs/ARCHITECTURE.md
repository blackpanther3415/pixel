# Pixel Architecture

## 1. High-level data flow

All UI / provider / skill / KB ingest input-output transits the G.B security
gateway (mandatory choke point). Services sit above local storage (D.B).

  Layers:
  - Shell (10-tab scaffold, theme, navigation)
  - G.B Security Gateway (scan, verdict, quarantine, audit log)
  - Services: providers / smart router / scraper / graph engine /
    skills / cloner / builder / trainer / sandbox / voice
  - D.B storage (SQLite + FTS5; encrypted vault pending)

## 2. Security gateway (G.B)

Every request, response, and L.B data source transits G.B. Engines are pure Dart and local.

  - Prompt injection: heuristic patterns + structural checks
  - Sensitive data: PII / secret patterns (API keys, emails, cards, phones)
  - Harmful content: curated term / rule sets
  - Code inspection: embedded script detection (eval, base64, exec)
  - File signatures: magic-byte scan of uploads / downloads

For L.B ingest, byte payloads are scanned first (malware containers), then
extracted text is scanned (injection / sensitive / harmful) before chunking.
On a hit: block + quarantine + audit log. The document is marked failed and
the ingest is aborted; nothing suspicious reaches the knowledge base.

Verdicts: pass | block | quarantine. Levels: low / medium / high / custom.

## 3. Provider layer

ProviderClient interface: send(messages, model, opts) -> stream, embed(text).
Implementations for OpenAI, Anthropic, Google (Gemini), Mistral, and local
Ollama. All use the official REST APIs over dio. Each provider exposes its
models with real pricing + speed metadata consumed by the Smart Router.

Smart Router picks the best provider/model per request: mode = fastest or
cheapest, honoring a user budget cap and per-provider min/max temperature.

## 4. Storage (D.B)

SQLite via sqflite_common_ffi (desktop) / sqflite (mobile). WAL + FTS5.

  Tables: chats, messages, providers, models, security_events,
          kb_documents, kb_chunks, skills, skill_runs, features,
          models_trained, graph_nodes, graph_edges, settings, quarantine.

Sensitive keys currently stored in the providers table; encrypted vault is planned.

## 5. CS.B graph engine

Node types: provider, skill, prompt, condition, script, router,
data-source (L.B), model (LLM), security (G.B policy node), output.
Graph executes topologically in real time via a runner that sends each node's
computed input to the next. Graphs persist as graph_nodes/graph_edges rows and
can bind any tab to a node ("a node is a feature binding").

## 6. Skills

  - No-code: a JSON spec (nodes + edges) created by the builder UI, compiled
    into the graph engine.
  - Code plugins: Dart files under lib/plugins with a Plugin contract
    (metadata + execute), discovered at startup, sandboxed in T.B before
    integration.

## 7. Build progress

  A. Shell + D.B + MI.B chat + routing + G.B core              ✅ done
  B. L.B scraper + knowledge base + G.B ingest gating           ✅ done
  C. CS.B graph + T.B sandbox                                   ✅ done
  D. Skills (no-code) + F.B library                             ✅ done
  E. B/P.B builder + C.B clone engine                           ✅ done
  F. LLM lab (honest binary check; actual finetune needs binary)✅ done
  Next: code-plugin skills, encrypted vault, unified search