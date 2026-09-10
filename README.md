# PIXEL

**AI Harness Dashboard** — a cross-platform (Android, iOS, macOS, Windows, Linux) personal AI workspace.

Pixel is a local-first, proprietary AI harness that funnels all input/output through a security gateway (G.B) and is fully customizable through a visual node-graph (CS.B). It ships ten tabs:

| # | Tab      | Name                    | Role |
|---|----------|-------------------------|------|
| 1 | **G.B**  | Security Gateway        | Gate + monitor all input/output data; block, quarantine, alert. 4 security levels. |
| 2 | **CS.B** | Structure Builder       | n8n-style visual node graph that customizes the whole app in real time. |
| 3 | **L.B**  | Live Brain              | Raw data scraper (URL, PDF, image, audio, video, RSS) → searchable local knowledge base. Every source is scanned by G.B on the way in before it is chunked or stored. |
| 4 | **C.B**  | Clone Builder           | Clone any app/skill/project into a functional equivalent adapted to Pixel. |
| 5 | **B/P.B**| Build / Plan            | AI-assisted plan → approve → build → test workflow. |
| 6 | **T.B**  | Test Box                | Sandbox to test features (pass/fail) before manual approval to integrate. |
| 7 | **D.B**  | Data Bank               | Browse/edit/delete/export knowledge, chat history, skills, models; full-text search (FTS5). |
| 8 | **F.B**  | Feature Bank            | Library of features; enable/disable, favorites, stats, security ratings. |
| 9 | **LLM**  | LLM Lab                 | Train / fine-tune models on-device; trained models become providers (when llama.cpp binary present). |
| 10 | **MI.B** | Main Interface          | Primary chat + voice interface; multi-provider, smart routing, cross-tab. |

## Rules

- **All data (in and out) passes through G.B.** Nothing reaches a provider or the user un-scanned. L.B ingest includes both byte-level (malware container detection) and text-level (prompt injection, sensitive data, harmful content) gating. Flagged payloads are quarantined automatically.
- **Everything is customizable through CS.B** in real time.
- **Local-first:** all data stays on device. No cloud backend.
- **No fake assumptions:** the app answers truthfully and gives realistic opinions.
- **Trained LLMs are first-class providers**, interchangeable with cloud models.

## Tech Stack

- **Flutter** (Dart) — single codebase, native apps on all five platforms.
- **sqflite + sqflite_common_ffi** — SQLite with FTS5 full-text search.
- **dio** — provider API transport (OpenAI, Anthropic, Google, Mistral, Ollama).
- **provider** — lightweight state management.
- **llama.cpp** — on-device inference / fine-tuning (LLM tab).
- **whisper.cpp / OCR** — offline audio transcription + OCR when available.

## Directory Layout

```
lib/
  main.dart              Entry point
  app.dart               App widget
  core/                  Constants, theme, app state, services composition
  models/                Domain models (providers, security events, KB, skills, graph, features)
  shell/                 Main 10-tab scaffold
  tabs/<tab>/            One folder per tab (ui + controller)
  services/
    security/            G.B engine + gateway
    providers/           Provider adapters (OpenAI, Anthropic, Google, Mistral, Ollama) + router
    knowledge/           L.B — ingest + semantic search
    database/            SQLite schema, migrations, settings
    skills/              Skill executor (no-code graphs)
    graph/               CS.B runtime (provider, prompt, condition, router, KB, script nodes)
    builder/             B/P.B — plan + build workflow
    cloner/              C.B — clone service
    sandbox/             T.B — sandbox runner
    llm/                 LLM Lab — dataset prep + training orchestration
  widgets/               Shared widgets
```

## Verification

- `flutter analyze` — **No issues found.**
- `flutter test` — **9 / 9 pass** (security engine, chunker, G.B KB gating).
- `flutter build linux --release` — **Succeeds** (`build/linux/arm64/release/bundle/pixel`).

## Build

```bash
flutter pub get
flutter run -d linux       # Linux desktop
flutter build linux --release
flutter build apk          # Android (requires Android SDK + JDK)
flutter build ios          # iOS (requires macOS + Xcode)
```

## Architecture

See `docs/ARCHITECTURE.md` for the full design.
