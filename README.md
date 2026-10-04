# Lamo

A fully on-device AI assistant for iOS. Chat with large language models completely offline — no API keys, no cloud, no data leaving your device. The model runs directly on your iPhone or iPad, and it can use tools: search the web, read pages, check your calendar, get the weather, detect your location, and remember facts about you across conversations.

> "Ask anything — I'm running 100% on your device."

![Swift 5](https://img.shields.io/badge/Swift-5-orange) ![iOS 26.2+](https://img.shields.io/badge/iOS-26.2%2B-blue) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue) ![LiteRT-LM](https://img.shields.io/badge/Inference-LiteRT--LM-green) ![License](https://img.shields.io/badge/Models-Apache_2.0-lightgrey)

## Table of Contents

- [Features](#features)
- [Agentic Tools](#agentic-tools)
- [Memory](#memory)
- [Models](#models)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Settings](#settings)
- [Privacy & Permissions](#privacy--permissions)
- [Testing & CI](#testing--ci)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Errors](#errors)
- [Acknowledgments](#acknowledgments)
- [License](#license)

## Features

### Core

- **100% local inference** — Google Gemma 4 models via LiteRT-LM, directly on-device. No internet needed after the model download (except for tools that inherently need it: web search, weather).
- **Streaming responses** — tokens render in real time with a blinking cursor. Stop generation anytime with the stop button or `Cmd+.`.
- **Thinking mode** — opt-in chain-of-thought reasoning in a collapsible section with a live indicator (supported by E4B, and by Apple Intelligence on iOS 27+).
- **Multimodal input** — images from camera, photo library, or drag-and-drop on iPad. The model sees attached images.
- **File understanding** — PDF, DOCX, XLSX, PPTX, CSV, JSON, and plain text. Content is extracted on-device and fed to the model; PDFs are additionally rendered as images for visual understanding.
- **Loop detection** — a three-strategy streaming monitor (substring repeats, n-gram flooding, line repetition) automatically stops degenerate generations.
- **Two engines** — LiteRT-LM (Gemma) or built-in Apple Intelligence via Foundation Models. Switch in **Settings**.

### Context & Compression

- **ContextTracker** — computes real KV-cache fill from the actual tokenizer, walking history most-recent-first. Detects dropped messages.
- **Auto-compression** — when the fill ratio exceeds the threshold (default 60% of KV-cache), old messages are condensed into a summary. Compression events appear as expandable cards in the chat.
- **Context panel** — a compact chip in the chat toolbar; tap for a detail sheet with a donut chart, token breakdown, system metrics (CPU/memory/battery/thermal), and per-message token counts.

### Markdown & Rich Content

- Block-level custom parser + native `AttributedString(markdown:)` for inline formatting.
- Headings h1–h6, **bold**, *italic*, `code`, fenced code blocks with language label and copy button.
- `Grid`-based tables (header highlight, zebra rows), blockquotes, task lists, `<hr>`, nested lists up to 3 levels.
- **HTML preview** — embedded HTML rendered in `WKWebView` with source/rendered toggle, fullscreen mode, dark-theme injection, and auto-height via `ResizeObserver`.

### Chat Organization

- `NavigationSplitView` with sidebar.
- Grouping: Pinned / Today / Yesterday / Previous 7 Days / Older.
- Search, rename, pin, delete via context menu and swipe actions.

## Agentic Tools

The model calls tools autonomously mid-generation. Calls are native (constrained decoding → valid JSON), not prompt hacks.

| Tool (`name`) | Capability |
|---|---|
| `web_search` | Multi-provider search: SearXNG pool → Brave API → DuckDuckGo fallback. Smart auto-fetch for thin snippets, native time-range filtering |
| `fetch_url` | Page reading: strips nav/ads/cookie banners, extracts article body, truncates at sentence boundaries |
| `calendar` | EventKit events: list/search in date ranges, create with a 15-min alarm. Strict date validation — the model gets an actionable error, never a silently wrong-day booking |
| `weather` | Open-Meteo: current conditions + up to 7-day forecast, WMO codes, sunrise/sunset, compass wind direction, auto-location |
| `get_location` | GPS via CoreLocation with a 120s cache, IP-geolocation fallback, reverse geocoding. Has an `ipOnly` mode without GPS |
| `update_memory` | Stores/reads/deletes user facts across conversations, with per-fact feedback (stored / duplicate / not-found) |

Key properties:

- **Fail-safe**: ordinary failures (city not found, malformed URL, providers down) come back as structured `error` + `hint` dicts the model can act on and retry. A tool error never aborts the response.
- **Agentic-loop budget** (`AgenticLoopBudget`): splits remaining context across iterations to avoid KV-cache overflow; results are truncated aggregate-aware (item-count caps, not just per-field).
- **Rich cards**: each tool has a dedicated SwiftUI view (weather with forecast, calendar with timeline, search with domain avatars, etc.). Tools can be toggled individually in Settings.

## Memory

ChatGPT-style semantic memory, entirely on-device:

1. The model calls `update_memory` during inference to extract facts.
2. Facts are stored as plain text in SwiftData (max 50 entries, 3000-char budget).
3. **Semantic deduplication** via Apple `NLEmbedding` (on-device BERT sentence embeddings): cosine similarity > 0.85 rejects duplicates.
4. **Contradiction detection** — a new fact contradicting an old one replaces it.
5. All facts are injected into the system prompt as `<memory>` XML before each LLM call.
6. Auto-pruning: age decay (30-day half-life) + usage-frequency weighting.
7. Entries older than 90 days are cleaned up on launch.

## Models

| Model | Parameters | Download Size | Min RAM | Speed | Capabilities |
|---|---|---|---|---|---|
| **Gemma 4 E4B** | 4B | 3.65 GB | ~6 GB | Moderate | Text, Images, Tool Calling, Thinking |
| **Gemma 4 E2B** | 2B | 2.58 GB | ~3 GB | Fast | Text, Images, Tool Calling |
| **Apple Intelligence** | ~3B (system) | 0 (built-in) | system-managed | Fast | Text, Tools, Images (iOS 27+) |

Sources — [HuggingFace `litert-community`](https://huggingface.co/litert-community), `.litertlm` files with SHA256 integrity verification. Both Gemma models are multimodal (vision) + tool calling; Thinking is E4B-only.

### Apple Intelligence (Foundation Models)

Switch engine in **Settings → Apple Intelligence**. Nothing to download:

- **Requirements:** iOS 26+, Apple Intelligence-capable device (A17 Pro / M1+), Apple Intelligence enabled in system Settings.
- **iOS 26:** text-only prompts, native tool calling (all 6 tools). Attached images are not visible to the model — it is told so, so it won't hallucinate descriptions.
- **iOS 27+:** adds image understanding (up to 4 per turn via `Attachment`), `toolCallingMode`, and thinking via `ContextOptions(reasoningLevel: .moderate)`.
- **Context window:** ~4096 tokens (`SystemLanguageModel.contextSize`). History is capped at ~800 tokens, file text at 4000 chars. The context bar and auto-compression use the FM window (summarization runs on the system model itself).
- **Sampling:** only temperature applies (clamped 0–1); Top-K / Top-P are LiteRT-only.
- Unavailability reasons are actionable: device not eligible / Apple Intelligence off / model still downloading.

### Model Management

- Preset catalog (E4B/E2B) with progress, speed, and ETA.
- Background downloads via `URLSession` with resume, SHA256 verification, and auto-retry (3 attempts). A file counts as valid only at ≥95% of expected size.
- Import custom models (`.litertlm`, `.bin`, `.tflite`) from Files.
- Cellular warning before heavy downloads over mobile data.

## Requirements

- **Xcode 26+** (iOS 26.2 SDK, Swift 5) on an Apple Silicon Mac.
- **iOS 26.2 deployment target** (runs on iOS 26–27; Apple Intelligence needs iOS 26+ and an A17 Pro / M1+ device; images in Foundation Models need iOS 27+).
- A physical device is strongly recommended (models need 3–6+ GB RAM).
- The `com.apple.developer.kernel.increased-memory-limit` entitlement (already in `Lamo.entitlements`) for loading large models.

## Quick Start

### For Users

1. Build and run on a device.
2. Open **Settings → Models** and download Gemma 4 E2B (fast) or E4B (higher quality) — or pick Apple Intelligence if your device supports it.
3. Create a chat (`Cmd+N`) and type. Attach images and files from the input bar.

### For Developers

```bash
git clone <this-repo-url>
open Lamo.xcodeproj
```

Xcode resolves the local Swift packages automatically (`Packages/LiteRT-LM`, `Packages/swift-markdown`). Select a physical device, build with `Cmd+B`, run with `Cmd+R`. On first launch, download a model in **Settings → Models**.

> Note: this repo currently has no git remote configured (`git remote -v` is empty), so substitute your own URL after publishing.

## Architecture

**MVVM** + SwiftData persistence (`Conversation`, `Message`, `MemoryEntry`) + a singleton service layer coordinated by `ProviderManager`. DI via `ServiceContainer` (protocols + `.live` / `.mock`) keeps `ChatViewModel` / `SettingsViewModel` testable.

### Inference Pipeline

```
User Input
  → ChatViewModel.send()
    → MemoryService.injectFacts()      (injects <memory> XML into the system prompt)
    → ContextTracker.fitMessages()     (fits history into the KV-cache budget)
    → ProviderManager.currentProvider  (LiteRTLMProvider / FoundationModelsProvider)
      → TokenBudget.tokenCount()       (real tokenizer for budget math)
      → LiteRT-LM Engine               (C++ via XCFramework, Metal GPU)
        → Gemma 4 model (.litertlm)
          → StreamingToken stream      (delta | thinkingDelta | toolCall | toolResult | benchmark)
            → RepetitionDetector       (stream loop check)
            → ChatViewModel            (updates Message.content in real time)
            → ToolCallReporter         (bridges tool events to the UI)
```

### Agentic Loop

Tool schemas are compiled from `@ToolParam` descriptions and registered with the engine at init (LiteRT-LM, or Foundation Models via thin adapters + `ToolRegistry`):

```
Model emits a tool call (constrained decoding → valid JSON)
  → engine runs the Swift tool (e.g. WebSearchTool → SearchProvider → SearXNG → Brave → DDG)
    → AgenticLoopBudget grants one iteration + a per-result token limit
    → TokenTruncator fits the result into the budget
    → ToolCallReporter yields toolCall + toolResult to the UI
  → Result injected into the conversation (KV-cache)
  → Model continues generating with the result in context
  → Repeat until final text or a soft budget stop
```

### Engine Lifecycle

`ProviderManager` caches the LiteRT-LM engine (loaded once, reused across conversations):

- **Debounced invalidation** — settings changes coalesce within 300ms before reload.
- **Pre-load cleanup** — URL-cache purge, autorelease-pool drain, tmp cleanup, `mmap`/`madvise(MADV_DONTNEED)` trick against memory pressure.
- **Memory-pressure monitoring** — `DispatchSource.makeMemoryPressureSource` invalidates conversation caches on `.warning` / `.critical`.
- **Auto-retry** — up to 3 engine-creation attempts with 1s delays.
- **Pre-flight checks** — model file exists, size ≥0.5 GB, magic bytes (corrupt-file detection), enough RAM and ≥1 GB free disk.

### Dynamic Token Limits

Limits are computed at runtime from `os_proc_available_memory()`:

| Available RAM | Safety Factor | Effective Budget |
|---|---|---|
| < 1.5 GB | 25% | Critical — smallest model only |
| < 3 GB | 35% | Tight — E2B recommended |
| < 5 GB | 45% | Normal — E4B works |
| ≥ 5 GB | 55% | Comfortable — full quality |

Each 1024 tokens of KV-cache costs ~300 MB for Gemma 4-class models. Rounded to the nearest 256 tokens.

## Project Structure

```
Lamo/
  LamoApp.swift            # entry point, ModelContainer + corrupt-DB recovery, engine warm-up
  Models/                  # Conversation, Message, MemoryEntry, PendingImage/File, PromptPreset (SwiftData @Model)
  ViewModels/              # ChatViewModel (send/stream/retry/stop/edit), SettingsViewModel, StreamBuffer
  Views/
    Chat/                  # ChatView, MessageBubble, MarkdownRenderer, ToolCallBlock + ToolBlocks/*, ContextBarView, HTMLPreviewView, …
    Settings/              # SettingsView + sections: Models, Generation/Compute, Tools, Memory, WebSearch
    MainView.swift SidebarView.swift
  Services/
    LiteRTLMProvider.swift FoundationModelsProvider.swift ProviderManager.swift LLMProvider.swift
    EngineLifecycle.swift ContextTracker.swift TokenBudget.swift RepetitionDetector.swift
    MemoryService.swift EmbeddingService.swift MemoryDeduplicator.swift MemoryContextBuilder.swift UpdateMemoryTool.swift
    DownloadManager.swift ModelDiscovery.swift PresetModels.swift ModelSettings.swift
    AttachmentProcessor.swift FileContentExtractor.swift ImageCache.swift ConversationBuilder.swift
    ToolCallReporter.swift ProviderStreaming.swift GenerationGuardrails.swift LamoError.swift LamoLogger.swift KeychainHelper.swift
    Tools/                 # ToolDefinitions, ToolRegistry, ToolRouter, SearchProvider/SearchTools/WebFetcher,
                           # CalendarTool, SystemTools (location+weather), AgenticLoopBudget, truncation helpers, …
  Utilities/               # AppDefaults (UserDefaults), TokenEstimation/TokenTruncator, TextFormat, UIImage+Resize
  Design/                  # Theme, Components
  Resources/ Assets.xcassets/
Packages/
  LiteRT-LM/               # local inference-runtime package (XCFramework)
  swift-markdown/          # local Markdown parsing package
LamoTests/                 # Swift Testing: models, services, ChatViewModel (mock provider), MemoryService
```

## Settings

Everything persists in `UserDefaults` (`AppDefaults`). Most settings apply without an engine restart unless noted.

### Model & Compute

| Key | Default | Description |
|---|---|---|
| `litertLMModelPath` | auto-detect | Path to the active `.litertlm` model |
| `litertLMUseGPU` | `true` | Metal GPU acceleration |
| `litertLMCpuThreadCount` | `4` | CPU threads (when GPU is off) |
| `litertLMSpeculativeDecoding` | `true` | Up to ~3× faster generation (if the model supports it) |

### Sampling

| Key | Default | Description |
|---|---|---|
| `litertLMTemperature` | `0.7` | Temperature (0.0–2.0; clamped 0–1 for FM) |
| `litertLMTopK` | `64` | Top-K (LiteRT only) |
| `litertLMTopP` | `0.95` | Nucleus sampling (LiteRT only) |

### Context

| Key | Default | Description |
|---|---|---|
| `litertLMMaxNumTokens` | `4096` | Max output tokens (manual mode) |
| `litertLMKvCacheAuto` | `true` | Auto KV-cache sizing from available RAM |
| `litertLMVisualTokenBudget` | `560` | Image processing quality (70–1120) |
| `compressionThreshold` | `0.6` | Auto-compression threshold (KV-cache fraction) |

### Behavior

| Key | Default | Description |
|---|---|---|
| `litertLMSystemPrompt` | built-in | Custom system prompt for new conversations |
| `litertLMThinkingMode` | `false` | Extended reasoning (E4B / FM on iOS 27+) |
| `memoryEnabled` | `true` | Semantic memory across conversations |
| `web_auto_fetch` | `true` | Auto-fetch pages for thin snippets |
| Tool toggles | all on | `tool_web_search`, `tool_fetch_url`, `tool_get_location`, `tool_weather`, `tool_calendar` |

## Privacy & Permissions

- All inference, embeddings, and memory stay on-device. No analytics, telemetry, or tracking.
- Network access after the model download happens only when the user's tools need it: web search, page fetch, weather/geocoding (Open-Meteo), IP geolocation as fallback.
- Memory facts live in local SwiftData; settings in UserDefaults; the Brave Search key in Keychain.
- Declared system permissions (see `INFOPLIST_KEY_*` in `Lamo.xcodeproj`):
  - Calendar — read events and find free slots;
  - Location (when-in-use) — weather and location-aware answers;
  - Camera / Photos — attach images to chats;
  - Contacts, Reminders, Health — declared in InfoPlist (accessed only for matching user requests; all data stays on-device).

## Testing & CI

Suite built on Swift Testing (`@Test`/`@Suite`):

- **Models** — `Message` encoding/decoding, `Conversation` properties, `MemoryEntry` lifecycle.
- **Services** — `TokenBudget` math, `ModelDiscovery` path resolution, `PresetModels` validation, `RepetitionDetector` strategies.
- **ChatViewModel** — send/stream/retry/stop/edit flows on `MockLLMProvider`, tool-call handling, image attachments, loop-detection recovery, title and summary generation.
- **MemoryService** — serialized suite: store/dedup/contradiction/forget/prune/inject.

Run locally with `Cmd+U` in Xcode. CI (`./.github/workflows/ci.yml`) runs on every push/PR to `main`:

1. `SwiftLint --strict` (config: `.swiftlint.yml`; excludes `Packages`, `.build`, `DerivedData`, `LamoTests`);
2. `xcodebuild build` + `xcodebuild test` on an iPhone simulator with `CODE_SIGNING_ALLOWED=NO`.

> Known mismatch worth fixing: the workflow currently pins `macos-15` + `Xcode 16.2`, while the project needs the iOS 26.2 SDK (Xcode 26+). The runner/image needs an update for green CI.

Lint: `swiftlint --strict`.

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + N` | New chat |
| `Cmd + .` | Stop generation |

## Errors

All errors are typed via `LamoError` (`LocalizedError`) with user-facing messages:

- Model not found / no downloaded model
- Engine initialization failed
- Corrupt model (magic-bytes / smaller-than-expected size check)
- Insufficient RAM / free disk (< 1 GB)
- Download failure (with auto-retry) / SHA256 mismatch
- Model stuck in a loop — repetition detector stopped generation

Plus SwiftData recovery: if an old store can't be opened (e.g. a new non-optional attribute), the unreadable `default.store` is archived aside (`default.store.corrupt-<stamp>`), the DB is recreated, and the app keeps running instead of crashing.

## Acknowledgments

- [Google LiteRT-LM](https://ai.google.dev/edge/litert-lm) — on-device LLM inference runtime.
- [Gemma 4](https://huggingface.co/litert-community) — open models from Google.
- [swift-markdown](https://github.com/apple/swift-markdown) — Apple's Markdown parsing library.
- [Open-Meteo](https://open-meteo.com) — free weather API.
- [SearXNG](https://searxng.org) — privacy-respecting metasearch engine.

## License

App code — see repo files (add a `LICENSE` when publishing). Gemma models are Apache 2.0. Local packages (`Packages/LiteRT-LM`, `Packages/swift-markdown`) carry their own licenses — see inside the packages.
