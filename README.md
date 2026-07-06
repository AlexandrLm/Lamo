# Lamo

A fully on-device AI chat application for iOS. Chat with large language models completely offline -- no API keys, no cloud, no data leaving your device.

> "Ask anything -- I'm running 100% on your device."

## Features

- **100% local inference** -- runs Google Gemma 4 models via LiteRT-LM directly on your device. No internet needed after model download.
- **Multimodal** -- attach images from camera, photo library, or drag-and-drop on iPad. The model understands what it sees.
- **Streaming responses** -- tokens render in real-time with a blinking cursor. Stop generation anytime.
- **Extended thinking** -- toggle chain-of-thought reasoning displayed in a collapsible section with live progress.
- **Semantic memory** -- the model remembers facts about you across conversations (ChatGPT-style `update_memory` tool). Stored locally in SwiftData, never leaves your device.
- **Full markdown rendering** -- headers (h1-h6), `**bold**`, `*italic*`, `` `code` ``, fenced code blocks with language label and copy button, tables with header highlighting, blockquotes, task lists, and horizontal rules.
- **Device benchmarking** -- 5-phase test (device info, CPU single/multi-core, Metal GPU, memory bandwidth) with AI tier rating and model compatibility predictions.
- **Model management** -- download preset models from HuggingFace, import custom `.litertlm` / `.bin` / `.tflite` files from the Files app.
- **Background downloads** -- resume support with persisted resume data, auto-retry on network errors (3 attempts), SHA256 integrity verification.
- **Smart memory management** -- aggressive pre-load cleanup (URL cache release, memory pressure trick to reclaim RAM from other apps), real-time `os_proc_available_memory()` monitoring, adaptive token limits (25-55% safety factor).
- **Chat organization** -- NavigationSplitView with sidebar. Conversations grouped by time (Pinned / Today / Yesterday / Previous 7 Days / Older). Search, rename, pin, delete.
- **Customizable generation** -- temperature, top-k, top-p, KV-cache auto/manual, speculative decoding, visual token budget, custom system prompt.

## Supported Models

| Model | Parameters | Download Size | Min RAM | Speed | Quality | Capabilities |
|---|---|---|---|---|---|---|
| **Gemma 4 E4B** | 4B | 3.65 GB | ~6 GB | Moderate | High | Text, Images, Tool Calling, Thinking |
| **Gemma 4 E2B** | 2B | 2.58 GB | ~3 GB | Fast | Good | Text, Images, Tool Calling |

Models are downloaded from [HuggingFace](https://huggingface.co/litert-community) and verified with SHA256 checksums. Both support vision (image understanding) and tool calling. E4B additionally supports extended thinking mode.

## Requirements

- **Xcode 26+** (iOS 26 SDK)
- **iOS 26.2** deployment target
- Physical iOS device strongly recommended (models require 3-6+ GB RAM)
- Apple Silicon Mac for building
- The app uses the `com.apple.developer.kernel.increased-memory-limit` entitlement for large model loading

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/Lamo.git
   ```

2. Open the Xcode project:
   ```bash
   open Lamo.xcodeproj
   ```

3. Xcode will automatically resolve the local Swift packages (LiteRT-LM and swift-markdown).

4. Select your target device and build with **Cmd+B**.

5. Run with **Cmd+R**. On first launch, go to **Settings > Models** and download a model.

## Project Structure

```
Lamo/
├── LamoApp.swift                  # @main entry point, SwiftData container setup
├── Lamo.entitlements              # Increased memory limit entitlement
├── Design/
│   └── Theme.swift                # LamoTheme: colors (#10a37f accent), spacing, fonts, corner radii
├── Models/                        # SwiftData @Model classes
│   ├── Conversation.swift         # Chat conversation (title, messages, pin, summary, timestamps)
│   ├── Message.swift              # Message (content, role, imagePaths, thinkingContent, isStreaming)
│   ├── MemoryEntry.swift          # Stored user fact (text, usageCount, timestamp)
│   └── DeviceBenchmark.swift      # 5-phase benchmark with AI tier rating
├── Services/
│   ├── LLMProvider.swift          # Protocol: streamResponse(messages:) -> AsyncStream<StreamingToken>
│   ├── ProviderManager.swift      # Engine lifecycle, caching, memory pressure, safe token limits
│   ├── LiteRTLMProvider.swift     # LLMProvider impl via LiteRT-LM with KV-cache reuse
│   ├── DownloadManager.swift      # Background URLSession downloads with resume + SHA256
│   ├── MemoryService.swift        # Semantic memory: store/prune/inject facts via Jaccard dedup
│   ├── UpdateMemoryTool.swift     # Tool the model calls to save facts during inference
│   ├── PresetModels.swift         # Gemma 4 E4B/E2B definitions, URLs, validation
│   ├── LamoError.swift            # Typed error enum with user-friendly descriptions
│   ├── LamoLogger.swift           # Centralized os.Logger instances
│   └── ImageCache.swift           # NSCache-based UIImage cache (100 items, 50 MB)
├── ViewModels/
│   ├── ChatViewModel.swift        # Send, stream, retry, stop, image resize for model
│   └── SettingsViewModel.swift    # Settings state management
├── Views/
│   ├── MainView.swift             # NavigationSplitView: sidebar + detail, conversation grouping
│   └── Chat/
│       ├── ChatView.swift         # Scrollable message list, auto-scroll, Cmd+. to stop
│       ├── ChatInputBar.swift     # Multiline input, image attach, model picker, send/stop
│       ├── MessageBubble.swift    # User/assistant bubbles, actions (copy/retry/share), thinking view
│       ├── MarkdownRenderer.swift # Block parser + native AttributedString for inline formatting
│       ├── CameraView.swift       # UIImagePickerController camera wrapper
│       ├── ImageViewer.swift      # Full-screen image viewer with zoom
│       └── TypingIndicator.swift  # Simple progress indicator
└── Resources/
    └── en.lproj/                  # Localized strings

Packages/
├── LiteRT-LM/                     # Google's LiteRT-LM v0.13.0 (binary XCFramework)
└── swift-markdown/                # Apple's swift-markdown (cmark-gfm based)
```

## Architecture

**MVVM** with SwiftData for persistence. Core inference path:

```
User Input
  -> ChatViewModel.send()
    -> ProviderManager.currentProvider (LiteRTLMProvider)
      -> LiteRT-LM Engine (C++ via XCFramework)
        -> Gemma 4 model (.litertlm)
          -> StreamingToken stream
            -> ChatViewModel updates Message.content in real-time
```

### Engine Lifecycle

`ProviderManager` is a singleton that caches the LiteRT-LM engine (loaded once, reused across conversations):

- **Debounced invalidation** -- settings changes coalesce within 300ms before triggering reload
- **Pre-load cleanup** -- releases URL cache, drains autorelease pools, clears temp files, and uses a memory pressure trick (allocate + touch + release large blocks via `mmap`/`madvise(MADV_DONTNEED)`) to force iOS to evict cached pages from other apps
- **Memory pressure monitoring** -- `DispatchSource.makeMemoryPressureSource` triggers conversation cache invalidation on `.warning` and `.critical` events
- **Auto-retry** -- engine creation retries up to 3 times with 1-second delays
- **Pre-flight checks** -- validates model file existence, minimum size (0.5 GB), magic bytes (corrupt detection), and available RAM before attempting load

### Dynamic Token Limits

Token limits are calculated at runtime using `os_proc_available_memory()`:

| Available RAM | Safety Factor | Effective Budget |
|---|---|---|
| < 1.5 GB | 25% | Critical -- use smallest model |
| < 3 GB | 35% | Tight -- E2B recommended |
| < 5 GB | 45% | Normal -- E4B works |
| >= 5 GB | 55% | Comfortable -- full quality |

Each 1024 tokens of KV-cache uses ~300 MB for Gemma 4-class models. Results are rounded to nearest 256 tokens.

### Semantic Memory

ChatGPT-style memory architecture without embeddings or vector search:

1. During inference, the model calls an `update_memory` tool to extract facts
2. Facts stored as plain text in SwiftData (max 50 facts, 3000 char budget)
3. Before each LLM call, all facts injected into system prompt as `<memory>` XML
4. Duplicate detection via Jaccard similarity (>0.6 threshold)
5. Auto-pruning: oldest/least-used facts removed, entries older than 90 days cleaned on launch

### Markdown Rendering

Hybrid approach for fast, accurate rendering:

- **Block-level parser** -- custom parser handles code blocks, headers (h1-h6), lists (3 indent levels), task lists, blockquotes, tables, and horizontal rules
- **Inline formatting** -- native `AttributedString(markdown:)` for bold, italic, code spans, and links
- **Code blocks** -- monospace font, language label, horizontal scroll, copy-to-clipboard with confirmation
- **Tables** -- `Grid` layout with header highlighting and alternating row backgrounds
- **Streaming** -- blinking cursor animation during token generation

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.0 |
| UI Framework | SwiftUI + UIKit interop |
| Persistence | SwiftData (`@Model` classes) |
| AI Runtime | Google LiteRT-LM v0.13.0 |
| Models | Gemma 4 (E4B/E2B) in `.litertlm` format |
| GPU Acceleration | Metal |
| Package Manager | Swift Package Manager (local packages) |
| Security | CryptoKit (SHA256 model integrity verification) |
| Logging | os.Logger (categories: general, engine, download, memory, ui) |

## Settings

All configuration is persisted via `UserDefaults` and applies without engine restart unless noted:

| Setting | Default | Description |
|---|---|---|
| `litertLMModelPath` | auto-detect | Path to active `.litertlm` model |
| `litertLMUseGPU` | `true` | Metal GPU acceleration |
| `litertLMCpuThreadCount` | `4` | CPU threads (when GPU disabled) |
| `litertLMTemperature` | `0.7` | Sampling temperature (0.0-2.0) |
| `litertLMTopK` | `40` | Top-K sampling |
| `litertLMTopP` | `0.95` | Nucleus sampling |
| `litertLMMaxNumTokens` | `4096` | Max output tokens (manual mode) |
| `litertLMKvCacheAuto` | `true` | Auto KV-cache sizing based on available RAM |
| `litertLMSpeculativeDecoding` | `false` | Up to 3x faster generation (if model supports it) |
| `litertLMVisualTokenBudget` | `560` | Image processing quality (70-1120) |
| `litertLMSystemPrompt` | built-in | Custom system prompt for new conversations |
| `litertLMThinkingMode` | `false` | Extended chain-of-thought reasoning |
| `memoryEnabled` | `true` | Semantic memory across conversations |

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + N` | New chat |
| `Cmd + .` | Stop generation |
| `Cmd + U` | Run tests |

## Error Handling

All errors are typed via `LamoError` with user-friendly descriptions:

- **Model not found** -- file doesn't exist at path
- **Engine init failed** -- LiteRT-LM configuration or initialization error
- **Model corrupted** -- magic bytes validation failed (all zeros)
- **Insufficient memory** -- available RAM below model threshold
- **Insufficient disk space** -- less than 1 GB free
- **Download failed** -- network error with auto-retry
- **SHA256 mismatch** -- file integrity verification failed
- **Model too small** -- downloaded file less than expected size
- **No model available** -- no model downloaded yet

## Privacy

- All processing happens on-device
- No network requests after model download
- No analytics, telemetry, or tracking
- Memory facts stored locally in SwiftData
- Settings stored in UserDefaults

## Acknowledgments

- [Google LiteRT-LM](https://ai.google.dev/edge/litert-lm) -- on-device LLM inference runtime
- [Gemma 4](https://huggingface.co/litert-community) -- open models from Google
- [swift-markdown](https://github.com/apple/swift-markdown) -- Apple's Markdown parsing library

## License

Models are licensed under Apache 2.0. See individual package licenses for LiteRT-LM and swift-markdown.
