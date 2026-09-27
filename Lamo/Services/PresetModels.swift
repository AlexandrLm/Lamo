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

    var filename: String {
        switch self {
        case .gemma4E4B: return "gemma-4-E4B-it.litertlm"
        case .gemma4E2B: return "gemma-4-E2B-it.litertlm"
        }
    }

    var downloadURL: URL? {
        switch self {
        case .gemma4E4B: return URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/\(filename)")
        case .gemma4E2B: return URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/\(filename)")
        }
    }

    var fileSizeGB: Double {
        switch self {
        case .gemma4E4B: return 3.65
        case .gemma4E2B: return 2.58
        }
    }

    /// Hardcoded size as fallback string (used when remote size is unknown).
    var fileSizeString: String {
        String(format: "%.1f GB", fileSizeGB)
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
            return String(localized: "Larger multimodal model with vision and tool calling support.")
        case .gemma4E2B:
            return String(localized: "Compact multimodal model. Fast inference, supports images.")
        }
    }

    var minRAM: String {
        switch self {
        case .gemma4E4B: return "~6 GB"
        case .gemma4E2B: return "~3 GB"
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

    /// Location of this model inside the app's models directory.
    var localFileURL: URL {
        ModelDiscovery.modelsDirectory.appendingPathComponent(filename)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localFileURL.path)
    }

    /// True only when the file is close to its expected size. A 50% threshold
    /// treated a half-finished download as complete, so the downloader skipped
    /// the resume and the engine later failed to load a truncated file.
    var isFileValid: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localFileURL.path),
              let size = attrs[.size] as? Int64 else { return false }
        let expected = Int64(fileSizeGB * 1_073_741_824)
        let minValidBytes = Int64(Double(expected) * 0.95)
        return size >= max(minValidBytes, 1)
    }

    /// Human-readable file size on disk
    var actualFileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localFileURL.path),
              let size = attrs[.size] as? Int64 else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Fetch SHA256 hash in parallel with model download. Returns nil if unavailable.
    static func fetchSHA256(for model: PresetModel) async -> String? {
        guard let url = model.downloadURL else { return nil }
        let sha256URL = URL(string: url.absoluteString + ".sha256")
        guard let checkURL = sha256URL else { return nil }
        var request = URLRequest(url: checkURL)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").first.map(String.init)
        } catch {
            return nil
        }
    }

    /// Fetch the real file size from HuggingFace via HTTP HEAD request.
    /// Returns nil if the request fails or Content-Length is missing.
    static func fetchRemoteSize(for model: PresetModel) async -> Int64? {
        guard let url = model.downloadURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // HuggingFace may redirect — check expectedContentLength
                if httpResponse.expectedContentLength > 0 {
                    return httpResponse.expectedContentLength
                }
            }
        } catch {
            // Network error — fall back to hardcoded size
        }
        return nil
    }

    /// Best-effort display size: real file on disk if downloaded, remote size if available,
    /// hardcoded fallback otherwise.
    func displaySizeString(remoteSize: Int64? = nil) -> String {
        if isDownloaded {
            return actualFileSizeString
        }
        if let remote = remoteSize, remote > 0 {
            return ByteCountFormatter.string(fromByteCount: remote, countStyle: .file)
        }
        return fileSizeString
    }

    /// Local path after download
    var localPath: String {
        localFileURL.path
    }
}
