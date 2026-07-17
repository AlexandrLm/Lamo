import Foundation

/// Known Gemma 4 models available for download via LiteRT-LM.
enum PresetModel: String, CaseIterable, Identifiable {
    case gemma4E4B = "gemma-4-E4B-it"
    case gemma4E2B = "gemma-4-E2B-it"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma4E4B: return "Gemma 4 E4B"
        case .gemma4E2B: return "Gemma 4 E2B"
        }
    }

    var huggingFaceRepo: String {
        switch self {
        case .gemma4E4B: return "litert-community/gemma-4-E4B-it-litert-lm"
        case .gemma4E2B: return "litert-community/gemma-4-E2B-it-litert-lm"
        }
    }

    var filename: String {
        switch self {
        case .gemma4E4B: return "gemma-4-E4B-it.litertlm"
        case .gemma4E2B: return "gemma-4-E2B-it.litertlm"
        }
    }

    var downloadURL: URL? {
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(filename)")
    }

    var fileSizeGB: Double {
        switch self {
        case .gemma4E4B: return 3.65
        case .gemma4E2B: return 2.58
        }
    }

    var fileSizeString: String {
        let gb = fileSizeGB
        return String(format: "%.1f GB", gb)
    }

    var parameterCount: String {
        switch self {
        case .gemma4E4B: return "4B"
        case .gemma4E2B: return "2B"
        }
    }

    var description: String {
        switch self {
        case .gemma4E4B:
            return "Larger multimodal model with vision and tool calling support."
        case .gemma4E2B:
            return "Compact multimodal model. Fast inference, supports images."
        }
    }
    var highlights: [String] {
        switch self {
        case .gemma4E4B:
            return [
                "Text decoder: 2.24 GB weights",
                "Embeddings: 0.67 GB (memory-mapped)",
                "Vision + tool calling support",
                "Best quality on-device"
            ]
        case .gemma4E2B:
            return [
                "Optimized mobile quantization",
                "Vision + tool calling support",
                "Lowest memory footprint",
                "Ideal for older devices"
            ]
        }
    }

    var minRAM: String {
        switch self {
        case .gemma4E4B: return "~6 GB"
        case .gemma4E2B: return "~3 GB"
        }
    }

    var speedTier: String {
        switch self {
        case .gemma4E4B: return "⚡⚡⚡ Moderate"
        case .gemma4E2B: return "⚡⚡⚡⚡⚡ Fast"
        }
    }

    var qualityTier: String {
        switch self {
        case .gemma4E4B: return "🏆🏆🏆🏆 High"
        case .gemma4E2B: return "🏆🏆🏆 Good"
        }
    }

    var accentColor: String {
        switch self {
        case .gemma4E4B: return "blue"
        case .gemma4E2B: return "green"
        }
    }

    var systemImage: String {
        switch self {
        case .gemma4E4B: return "brain.head.profile"
        case .gemma4E2B: return "bolt.fill"
        }
    }

    var license: String {
        "Apache 2.0"
    }

    var capabilities: [String] {
        switch self {
        case .gemma4E4B:
            return ["Text", "Images", "Tool Calling", "Thinking"]
        case .gemma4E2B:
            return ["Text", "Images", "Tool Calling"]
        }
    }

    var isDownloaded: Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        let fileURL = modelsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// File exists but may be incomplete/corrupted (size < 80% of expected).
    var isPartialDownload: Bool {
        isDownloaded && !isFileValid
    }

    var isFileValid: Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        let fileURL = modelsDir.appendingPathComponent(filename)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return false }
        let expectedBytes = Int64(fileSizeGB * 1_073_741_824)
        // File is valid if it's at least 80% of expected size — allows for
        // minor size differences between HuggingFace revisions.
        return size > expectedBytes * 4 / 5
    }

    /// Human-readable file size on disk
    var actualFileSizeString: String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        let fileURL = modelsDir.appendingPathComponent(filename)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Local path after download
    var localPath: String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("models").appendingPathComponent(filename).path
    }
}
