# Lamo

A fully on-device AI assistant for iOS. Chat with large language models completely offline — no API keys, no cloud, no data leaving your device. The model runs directly on your iPhone or iPad, and it can use tools: search the web, check your calendar, get the weather, create reminders, take notes, read your files, and remember facts about you across conversations.

> "Ask anything — I'm running 100% on your device."

## Features

### Core AI
- **100% local inference** — runs Google Gemma 4 models via LiteRT-LM directly on your device. No internet needed after model download.
- **Streaming responses** — tokens render in real-time with a blinking cursor. Stop generation anytime with `Cmd+.` or the stop button.
- **Extended thinking** — toggle chain-of-thought reasoning displayed in a collapsible section with live progress indicator.
- **Multimodal input** — attach images from camera, photo library, or drag-and-drop on iPad. The model understands what it sees.
- **File understanding** — attach PDF, DOCX, XLSX, PPTX, CSV, JSON, or plain text files. Content is extracted on-device and fed to the model; PDFs are also rendered as images for visual understanding.
- **Repetition detection** — three-strategy streaming monitor (substring repeats, n-gram flooding, line repetition) catches and stops model loops automatically.

### Agentic Tools
The model can autonomously call tools mid-conversation to accomplish tasks:

| Tool | Capability |
|---|---|
| **Web Search** | Multi-provider search (SearXNG pool → Brave API → DuckDuckGo fallback), smart auto-fetch for thin snippets, time-range filtering |
| **Web Fetch** | Fetches and cleans URLs: strips nav/ads/cookie banners, extracts article content, truncates at sentence boundaries |
| **Calendar** | List events in date ranges, create events with alarms via EventKit |
| **Reminders** | Create reminders with titles, due dates, and notes |
| **Notes** | Full CRUD for Apple Notes: list, search, read, create, delete |
| **Weather** | Current conditions + multi-day forecast via Open-Meteo API, WMO weather codes, sunrise/sunset |
| **Location** | GPS via CoreLocation with 120s cache, IP geolocation fallback, reverse geocoding |
| **Device Info** | Device model, OS version, battery, storage, RAM, uptime |
| **Time** | Current time with weekday, ISO date, timezone |
| **Open URL** | Opens URLs in Safari |
| **Code Sandbox** | Executes code and renders output as text or HTML |
| **Memory** | Stores/retrieves/forgets facts about the user across conversations |

Tools produce rich inline cards — not raw JSON. Each has a dedicated SwiftUI view (weather card with forecast, calendar card with timeline bars, search cards with domain avatars, etc.). Tools can be individually enabled/disabled in Settings. A token budget manager divides remaining context across agentic loop iterations to prevent KV-cache overflow.

### Semantic Memory
ChatGPT-style persistent memory, entirely on-device:

1. Model calls `update_memory` tool during inference to extract facts
2. Facts stored as plain text in SwiftData (max 50, 3000 char budget)
3. **Semantic deduplication** via Apple NLEmbedding (on-device BERT sentence embeddings): cosine similarity > 0.85 rejects duplicates
4. **Contradiction detection** — new facts that contradict existing ones replace the old
5. All facts injected into system prompt as `<memory>` XML before each LLM call
6. Auto-pruning: 30-day age decay half-life, oldest/least-used removed
7. Entries older than 90 days cleaned on launch

### Context Management
- **ContextTracker** — computes KV-cache fill ratio using real token counts, walking history most-recent-first. Detects dropped messages. Triggers summarization at >80% fill.
- **Context compression** — automatic conversation summarization when context fills; old messages condensed into a summary string. Compression events shown as expandable notification cards.
- **Context bar** — compact chip in the chat toolbar; tap for a detailed sheet with donut chart, token breakdown, system metrics (CPU/memory/battery/thermal), and per-message token counts.

### Markdown & Rich Content
- **Block-level custom parser** + native `AttributedString(markdown:)` for inline formatting
- Headers (h1–h6), **bold**, *italic*, `code`, fenced code blocks with language label and copy button
- Tables with `Grid` layout, header highlighting, alternating row backgrounds
- Blockquotes, task lists, horizontal rules, nested lists (3 indent levels)
- **HTML preview** — embedded HTML rendered in WKWebView with source/rendered toggle, full-screen mode, dark style injection, auto-height via ResizeObserver

### Model Management
- **Preset catalog** — Gemma 4 E4B (4B) and E2B (2B) with download progress, speed, ETA
- **Background downloads** — URLSession with resume support, SHA256 integrity verification, auto-retry (3 attempts)
- **Import custom models** — `.litertlm`, `.bin`, `.tflite` from the Files app
- **Cellular awareness** — prompts before large cellular downloads

### Chat Organization
- NavigationSplitView with sidebar
- Conversations grouped by time: Pinned / Today / Yesterday / Previous 7 Days / Older
- Search, rename, pin, delete via context menu and swipe actions

### Generation Settings
- Temperature, top-K, top-P (with auto mode)
- KV-cache: auto (RAM-based) or manual token count
- Speculative decoding (up to 3× faster, if model supports)
- Visual token budget (image quality control: 70–1120)
- Custom system prompt
- Compression threshold

## Supported Models

| Model | Parameters | Download Size | Min RAM | Speed | Quality | Capabilities |
|---|---|---|---|---|---|---|
| **Gemma 4 E4B** | 4B | 3.65 GB | ~6 GB | Moderate | High | Text, Images, Tool Calling, Thinking |
| **Gemma 4 E2B** | 2B | 2.58 GB | ~3 GB | Fast | Good | Text, Images, Tool Calling |

Models are downloaded from [HuggingFace](https://huggingface.co/litert-community) and verified with SHA256 checksums. Both support vision (image understanding) and tool calling. E4B additionally supports extended thinking mode.

## Requirements

- **Xcode 16.2+** (iOS 26 SDK)
- **iOS 26.2** deployment target
- Physical iOS device strongly recommended (models require 3–6+ GB RAM)
- Apple Silicon Mac for building
- `com.apple.developer.kernel.increased-memory-limit` entitlement for large model loading

## Getting Started

```bash
git clone https://github.com/your-username/Lamo.git
open Lamo.xcodeproj
```

Xcode will automatically resolve the local Swift packages (LiteRT-LM and swift-markdown). Select your target device, build with **Cmd+B**, run with **Cmd+R**. On first launch, go to **Settings → Models** and download a model.

## Architecture

**MVVM** with SwiftData for persistence and a **singleton service layer** coordinated by `ProviderManager`.

### Inference Pipeline

```
User Input
  → ChatViewModel.send()
    → MemoryService.injectFacts()        (injects <memory> XML into system prompt)
    → ContextTracker.fitMessages()       (fits history into KV-cache budget)
    → ProviderManager.currentProvider    (LiteRTLMProvider)
      → TokenBudget.tokenCount()         (real tokenizer for budget calculation)
      → LiteRT-LM Engine                 (C++ via XCFramework, Metal GPU)
        → Gemma 4 model (.litertlm)
          → StreamingToken stream        (delta | thinkingDelta | toolCall | toolResult | benchmark)
            → RepetitionDetector         (checks for output loops)
            → ChatViewModel              (updates Message.content in real-time)
            → ToolCallReporter           (bridges tool events to UI)
```

### Agentic Loop

When the model decides to use tools, an agentic loop runs:

```
Model output → toolCall token
  → LiteRTLMProvider invokes tool (e.g., WebSearchTool)
    → Tool executes (e.g., SearchProvider → SearXNG → Brave → DDG)
    → AgenticLoopBudget allocates token budget for this iteration
    → ToolCallReporter yields toolCall + toolResult to UI
    → AgenticLoopState advances plan step
  → Tool result injected into conversation
  → Model continues generating with tool output in context
  → Repeat until model produces final text response
```

Each tool is a class conforming to LiteRT-LM's `Tool` protocol, registered with the engine at init time. Results are rendered as rich SwiftUI cards, not raw JSON.

### Engine Lifecycle

`ProviderManager` caches the LiteRT-LM engine (loaded once, reused across conversations):

- **Debounced invalidation** — settings changes coalesce within 300ms before reload
- **Pre-load cleanup** — releases URL cache, drains autorelease pools, clears temp files, uses `mmap`/`madvise(MADV_DONTNEED)` memory pressure trick to evict cached pages from other apps
- **Memory pressure monitoring** — `DispatchSource.makeMemoryPressureSource` triggers conversation cache invalidation on `.warning`/`.critical`
- **Auto-retry** — engine creation retries up to 3 times with 1-second delays
- **Pre-flight checks** — validates model file existence, minimum size (0.5 GB), magic bytes (corrupt detection), available RAM, and free disk space (≥1 GB)

### Dynamic Token Limits

Token limits are calculated at runtime from `os_proc_available_memory()`:

| Available RAM | Safety Factor | Effective Budget |
|---|---|---|
| < 1.5 GB | 25% | Critical — use smallest model |
| < 3 GB | 35% | Tight — E2B recommended |
| < 5 GB | 45% | Normal — E4B works |
| ≥ 5 GB | 55% | Comfortable — full quality |

Each 1024 tokens of KV-cache uses ~300 MB for Gemma 4-class models. Results rounded to nearest 256 tokens.

### Semantic Memory

Fully on-device memory architecture with semantic deduplication:

1. Model calls `update_memory` tool → `MemoryService.store()` via `UpdateMemoryTool`
2. `EmbeddingService` computes NLEmbedding (on-device BERT) sentence embedding for the new fact
3. Cosine similarity computed against all cached embeddings (200-item LRU cache)
4. Similarity > 0.85 → duplicate rejected; < 0.4 but same key entity → contradiction replaced
5. Facts injected into system prompt as structured `<memory>` XML before each inference
6. Age-based decay (30-day half-life) + usage-count weighting for relevance
7. Auto-cleanup: >50 facts prunes lowest-score, >90 days deleted on launch

### Dependency Injection

`ServiceContainer` provides `MemoryService` and `DownloadManager` behind protocols for testability. Static `.live` and `.mock` instances, plus no-op test doubles, allow `ChatViewModel` and `SettingsViewModel` to be tested without real engines or network.

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI Framework | SwiftUI + UIKit interop |
| Persistence | SwiftData (`@Model` classes) |
| AI Runtime | Google LiteRT-LM v0.13.0 |
| Models | Gemma 4 (E4B/E2B) in `.litertlm` format |
| GPU Acceleration | Metal |
| Embeddings | Apple NLEmbedding (on-device BERT) |
| Package Manager | Swift Package Manager (local packages) |
| Security | CryptoKit (SHA256) + Keychain Services |
| Logging | os.Logger (categories: general, engine, download, memory, ui) |
| Testing | Swift Testing (`@Test`/`@Suite`) |
| CI | GitHub Actions (macOS 15, Xcode 16.2, iPhone 16 simulator) |

## Settings

All configuration persisted via `UserDefaults` (`AppDefaults`). Most apply without engine restart unless noted.

### Model & Compute

| Setting | Default | Description |
|---|---|---|
| `litertLMModelPath` | auto-detect | Path to active `.litertlm` model |
| `litertLMUseGPU` | `true` | Metal GPU acceleration |
| `litertLMCpuThreadCount` | `4` | CPU threads (when GPU disabled) |
| `litertLMSpeculativeDecoding` | `false` | Up to 3× faster generation (if model supports) |

### Sampling

| Setting | Default | Description |
|---|---|---|
| `litertLMTemperature` | `0.7` | Sampling temperature (0.0–2.0) |
| `litertLMTopK` | `40` | Top-K sampling |
| `litertLMTopP` | `0.95` | Nucleus sampling |

### Context

| Setting | Default | Description |
|---|---|---|
| `litertLMMaxNumTokens` | `4096` | Max output tokens (manual mode) |
| `litertLMKvCacheAuto` | `true` | Auto KV-cache sizing based on available RAM |
| `litertLMVisualTokenBudget` | `560` | Image processing quality (70–1120) |

### Behavior

| Setting | Default | Description |
|---|---|---|
| `litertLMSystemPrompt` | built-in | Custom system prompt for new conversations |
| `litertLMThinkingMode` | `false` | Extended chain-of-thought reasoning |
| `memoryEnabled` | `true` | Semantic memory across conversations |
| Per-tool toggles | all on | Enable/disable individual tools |

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + N` | New chat |
| `Cmd + .` | Stop generation |

## Error Handling

All errors typed via `LamoError` (`LocalizedError`) with user-facing descriptions:

- **Model not found** — file doesn't exist at path
- **Engine init failed** — LiteRT-LM configuration or initialization error
- **Model corrupted** — magic bytes validation failed (all zeros)
- **Insufficient memory** — available RAM below model threshold
- **Insufficient disk space** — less than 1 GB free
- **Download failed** — network error with auto-retry
- **SHA256 mismatch** — file integrity verification failed
- **Model too small** — downloaded file less than expected size
- **No model available** — no model downloaded yet
- **Model stuck in loop** — repetition detector triggered, generation stopped

## Testing

67 KB test suite using Swift Testing (`@Test`/`@Suite`):

- **Model tests** — Message encoding/decoding, Conversation properties, MemoryEntry lifecycle
- **Service tests** — TokenBudget calculations, ModelDiscovery path resolution, PresetModels validation, RepetitionDetector strategies
- **ChatViewModel tests** — send/stream/retry/stop/edit flows with `MockLLMProvider`, tool call handling, image attachments, loop detection recovery, conversation title generation, summary generation
- **MemoryService tests** — serialized suite covering store/dedup/contradiction/forget/prune/inject cycles

Run locally: `Cmd+U` in Xcode. CI runs on every push and PR to `main`.

## Privacy

- All processing happens on-device
- No network requests after model download (except user-initiated tool use: web search, weather, location)
- No analytics, telemetry, or tracking
- Memory facts stored locally in SwiftData
- Settings stored in UserDefaults
- API keys (Brave Search) stored in iOS Keychain

## Acknowledgments

- [Google LiteRT-LM](https://ai.google.dev/edge/litert-lm) — on-device LLM inference runtime
- [Gemma 4](https://huggingface.co/litert-community) — open models from Google
- [swift-markdown](https://github.com/apple/swift-markdown) — Apple's Markdown parsing library
- [Open-Meteo](https://open-meteo.com) — free weather API
- [SearXNG](https://searxng.org) — privacy-respecting metasearch engine

## License

Models are licensed under Apache 2.0. See individual package licenses for LiteRT-LM and swift-markdown.
