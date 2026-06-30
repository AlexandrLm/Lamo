# Memory System for Lamo — Implementation Plan

> **Goal:** Implement on-device semantic memory using EmbeddingGemma-300M so Lamo remembers context across conversations.

**Architecture:** RAG (Retrieval-Augmented Generation) on-device. EmbeddingGemma-300M vectorizes messages → SwiftData stores vectors → cosine similarity retrieves relevant context → injected into system prompt before LLM inference.

**Tech Stack:** SwiftData (storage), TensorFlowLite (embedding inference), SentencePiece (tokenization)

---

## Task 1: MemoryEntry.swift — SwiftData model
- Create: `Lamo/Models/MemoryEntry.swift`
- @Model with vector storage as Data

## Task 2: TextChunker.swift
- Create: `Lamo/Services/TextChunker.swift`
- Split text into sentence-based chunks ≤200 chars

## Task 3: EmbeddingEngine.swift
- Create: `Lamo/Services/EmbeddingEngine.swift`
- Load .tflite model, tokenize with SentencePiece, run inference, return [Float]

## Task 4: MemoryService.swift
- Create: `Lamo/Services/MemoryService.swift`
- Store embeddings, cosine search, build context string

## Task 5: Integration — LamoApp.swift
- Modify: `Lamo/LamoApp.swift` — add MemoryEntry to modelContainer

## Task 6: Integration — ChatViewModel.swift
- Modify: `Lamo/ViewModels/ChatViewModel.swift` — auto-store messages

## Task 7: Integration — LiteRTLMProvider.swift
- Modify: `Lamo/Services/LiteRTLMProvider.swift` — inject memory context

## Task 8: Settings — memory toggle
- Modify: `Lamo/ViewModels/SettingsViewModel.swift` + `Lamo/Views/Settings/SettingsView.swift`

## Task 9: ProviderManager — memory service + cleanup
- Modify: `Lamo/Services/ProviderManager.swift`

## Dependencies
- TensorFlowLite SPM: https://github.com/tensorflow/tensorflow — `tensorflow/lite/swift`
- SentencePiece: already in LiteRT-LM Package.swift
