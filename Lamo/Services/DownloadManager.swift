import Foundation
import Combine
import SwiftUI
import CryptoKit

/// Manages downloading LiteRT-LM models from HuggingFace.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: DownloadState] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]
    private var resumeData: [String: Data] = [:]
    private let session: URLSession
    private let backgroundSessionID = "com.lamo.download"

    /// Directory for persisting resume data across app launches.
    private var resumeDataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
            .appendingPathComponent(".resume_data")
    }

    struct DownloadState {
        var progress: Double = 0
        var bytesWritten: Int64 = 0
        var totalBytes: Int64 = 0
        var isDownloading: Bool = false
        var error: String? = nil
        var isComplete: Bool = false
        var retryCount: Int = 0
        var lastError: String? = nil

        var progressPercentage: Int {
            guard totalBytes > 0 else { return Int(progress * 100) }
            return Int(progress * 100)
        }

        var downloadedSizeString: String {
            ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        }

        var totalSizeString: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
    }

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionID)
        config.allowsCellularAccess = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: DownloadSessionDelegate.shared, delegateQueue: nil)

        // #7: Load persisted resume data from disk
        loadPersistedResumeData()
        // #7: Clean up old resume data (> 7 days)
        cleanupOldResumeData()
    }

    // MARK: - Resume Data Persistence (#7)

    /// Loads any persisted resume data from ~/Documents/models/.resume_data/
    private func loadPersistedResumeData() {
        guard FileManager.default.fileExists(atPath: resumeDataURL.path) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resumeDataURL, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files where file.pathExtension == "resume" {
            let filename = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file) {
                resumeData[filename] = data
                print("[Lamo] Loaded persisted resume data for \(filename)")
            }
        }
    }

    /// Removes resume data files older than 7 days.
    private func cleanupOldResumeData() {
        guard FileManager.default.fileExists(atPath: resumeDataURL.path) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resumeDataURL, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in files where file.pathExtension == "resume" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = attrs.creationDate,
               creationDate < cutoff {
                try? FileManager.default.removeItem(at: file)
                print("[Lamo] Cleaned up old resume data: \(file.lastPathComponent)")
            }
        }
    }

    /// Persists resume data to ~/Documents/models/.resume_data/
    private func persistResumeData(_ data: Data, for filename: String) {
        try? FileManager.default.createDirectory(at: resumeDataURL, withIntermediateDirectories: true)
        let fileURL = resumeDataURL.appendingPathComponent(filename + ".resume")
        try? data.write(to: fileURL)
        print("[Lamo] Persisted resume data for \(filename)")
    }

    /// Removes persisted resume data for a filename.
    private func removePersistedResumeData(for filename: String) {
        let fileURL = resumeDataURL.appendingPathComponent(filename + ".resume")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func download(model: PresetModel) {
        guard let url = model.downloadURL else { return }
        guard activeDownloads[model.filename]?.isDownloading != true else { return }

        // Check if already downloaded
        if model.isDownloaded {
            activeDownloads[model.filename] = DownloadState(progress: 1.0, isComplete: true)
            return
        }

        // Create models directory
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        activeDownloads[model.filename] = DownloadState(isDownloading: true)

        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.filename) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }

        // Store metadata for delegate
        DownloadSessionDelegate.shared.pendingModels[model.filename] = model

        // Track progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            Task { @MainActor in
                self.activeDownloads[model.filename]?.progress = progress.fractionCompleted
                self.activeDownloads[model.filename]?.bytesWritten = progress.completedUnitCount
                self.activeDownloads[model.filename]?.totalBytes = progress.totalUnitCount
            }
        }

        observations[model.filename] = observation
        tasks[model.filename] = task
        task.resume()
    }

    func cancelDownload(model: PresetModel) {
        guard let task = tasks[model.filename] else { return }
        // #7: Save resume data to disk before cancelling
        task.cancel { [weak self] resumeData in
            guard let self, let resumeData else { return }
            Task { @MainActor in
                self.resumeData[model.filename] = resumeData
                self.persistResumeData(resumeData, for: model.filename)
            }
        }
        tasks.removeValue(forKey: model.filename)
        observations.removeValue(forKey: model.filename)
        activeDownloads[model.filename]?.isDownloading = false
    }

    func deleteModel(_ model: PresetModel) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent("models").appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: fileURL)
        activeDownloads.removeValue(forKey: model.filename)
        // Clean up any persisted resume data for this model
        removePersistedResumeData(for: model.filename)

        if ProviderManager.shared.litertLMModelPath == model.filename {
            ProviderManager.shared.litertLMModelPath = nil
            ProviderManager.shared.invalidateEngine()
        }
    }

    func handleCompletion(filename: String, tempURL: URL?, error: Error?) {
        Task { @MainActor in
            // Prevent double-handling (race condition between didFinishDownloadingTo and didCompleteWithError)
            guard self.activeDownloads[filename]?.isComplete != true else { return }

            if let error = error {
                self.activeDownloads[filename]?.lastError = error.localizedDescription
                self.activeDownloads[filename]?.error = error.localizedDescription
                self.activeDownloads[filename]?.isDownloading = false

                // Auto-retry up to 3 times for network errors
                if let urlError = error as? URLError,
                   [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code),
                   let retryCount = self.activeDownloads[filename]?.retryCount, retryCount < 3 {
                    self.activeDownloads[filename]?.retryCount = retryCount + 1
                    self.activeDownloads[filename]?.error = "Retrying... (attempt \(retryCount + 1)/3)"
                    self.activeDownloads[filename]?.isDownloading = true
                    // Wait before retry
                    try? await Task.sleep(for: .seconds(2))
                    if let model = DownloadSessionDelegate.shared.pendingModels[filename] {
                        self.download(model: model)
                    }
                }
                return
            }

            guard let tempURL = tempURL else {
                self.activeDownloads[filename]?.error = "Download failed: no data"
                self.activeDownloads[filename]?.isDownloading = false
                return
            }

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent("models").appendingPathComponent(filename)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)

                // #10: SHA256 verification after download
                if let model = DownloadSessionDelegate.shared.pendingModels[filename],
                   let modelURL = model.downloadURL {
                    let sha256URL = URL(string: modelURL.absoluteString + ".sha256")
                    if let sha256URL = sha256URL {
                        do {
                            let (sha256Data, _) = try await URLSession.shared.data(from: sha256URL)
                            let expectedHash = String(data: sha256Data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if let expectedHash = expectedHash, !expectedHash.isEmpty {
                                // Compute SHA256 of the downloaded model file
                                let fileData = try Data(contentsOf: destination)
                                let computedHash = SHA256.hash(data: fileData)
                                    .map { String(format: "%02x", $0) }
                                    .joined()
                                if computedHash != expectedHash {
                                    print("[Lamo] SHA256 mismatch for \(filename): expected \(expectedHash), got \(computedHash)")
                                    try FileManager.default.removeItem(at: destination)
                                    self.activeDownloads[filename]?.error = "File integrity check failed (SHA256 mismatch). Please re-download."
                                    self.activeDownloads[filename]?.isDownloading = false
                                    self.observations.removeValue(forKey: filename)
                                    self.tasks.removeValue(forKey: filename)
                                    return
                                }
                                print("[Lamo] SHA256 verified for \(filename)")
                            }
                        } catch {
                            // .sha256 file doesn't exist or network error — skip verification
                            print("[Lamo] SHA256 verification skipped for \(filename): \(error.localizedDescription)")
                        }
                    }
                }

                self.activeDownloads[filename]?.isComplete = true
                self.activeDownloads[filename]?.isDownloading = false
                self.activeDownloads[filename]?.progress = 1.0
                self.activeDownloads[filename]?.retryCount = 0
                self.activeDownloads[filename]?.lastError = nil
                self.observations.removeValue(forKey: filename)
                self.tasks.removeValue(forKey: filename)
                // Clean up persisted resume data for completed download
                self.removePersistedResumeData(for: filename)

                ProviderManager.shared.reloadEngine()
            } catch {
                self.activeDownloads[filename]?.error = error.localizedDescription
                self.activeDownloads[filename]?.isDownloading = false
            }
        }
    }
}

// MARK: - Background Session Delegate

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadSessionDelegate()
    private let lock = NSLock()
    private var _pendingModels: [String: PresetModel] = [:]
    var pendingModels: [String: PresetModel] {
        get { lock.lock(); defer { lock.unlock() }; return _pendingModels }
        set { lock.lock(); defer { lock.unlock() }; _pendingModels = newValue }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let filename = downloadTask.originalRequest?.url?.lastPathComponent else { return }
        // Copy temp file immediately — iOS deletes it after this method returns
        let tempDir = FileManager.default.temporaryDirectory
        let backupURL = tempDir.appendingPathComponent("lamo_dl_\(filename)")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: location, to: backupURL)
        Task { @MainActor in
            DownloadManager.shared.handleCompletion(filename: filename, tempURL: backupURL, error: nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let filename = task.originalRequest?.url?.lastPathComponent else { return }
        if let error = error as? URLError, error.code == .cancelled { return }
        // Only report errors — success is handled by didFinishDownloadingTo
        if let error = error {
            Task { @MainActor in
                DownloadManager.shared.handleCompletion(filename: filename, tempURL: nil, error: error)
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .backgroundDownloadComplete, object: nil)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let backgroundDownloadComplete = Notification.Name("backgroundDownloadComplete")
}
