import Foundation

/// Stateless model discovery helpers — path resolution, listing, display names.
enum ModelDiscovery {
    /// The models directory: ~/Documents/models/
    static var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
    }

    /// Formats a model path/filename into a human-readable display name.
    static func displayName(forModelPath path: String) -> String {
        let filename = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return filename
    }

    /// Resolves a model path: checks the custom path directly, then in
    /// modelsDirectory, or falls back to the first available model.
    static func resolveModelPath(custom: String? = nil) -> String? {
        if let custom = custom {
            if FileManager.default.fileExists(atPath: custom) { return custom }
            let fullPath = modelsDirectory.appendingPathComponent(custom).path
            if FileManager.default.fileExists(atPath: fullPath) { return fullPath }
            return nil
        }
        return findFirstModel()
    }

    /// Finds the first model file (.litertlm, .bin, .tflite) in modelsDirectory.
    static func findFirstModel() -> String? {
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return nil }
        guard let first = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "litertlm" || $0.pathExtension == "bin" || $0.pathExtension == "tflite" })
        else { return nil }
        return first.path
    }

    /// Lists all model files (.litertlm, .bin, .tflite) in modelsDirectory.
    static func listModels() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "litertlm" || $0.pathExtension == "bin" || $0.pathExtension == "tflite" }
            .map { $0.lastPathComponent }
    }
}
