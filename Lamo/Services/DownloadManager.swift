import Foundation
import Combine
import SwiftUI
import CryptoKit
import Network
import os

/// Manages downloading LiteRT-LM models from HuggingFace.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: DownloadState] = [:]
    /// Set when a large download is attempted on cellular — UI shows confirmation.
    @Published var pendingCellularDownload: PresetModel? = nil
    private var tasks: [String: URLSessionDownloadTask] = [:]

    /// Pre-fetched SHA256 hashes, populated in parallel with model downloads.
    private var pendingSHA256: [String: String] = [:]

    private var resumeData: [String: Data] = [:]
    private let session: URLSession
    private let backgroundSessionID = "com.lamo.download"

    // MARK: - Network Monitor
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.lamo.network")
    private(set) var isExpensive = false  // true = cellular or hotspot
    private(set) var isConstrained = false // true = low-data mode / data cap

    /// Directory for persisting resume data across app launches.
    private static let resumeDataURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
            .appendingPathComponent(".resume_data")
    }()

    struct DownloadState {
        var progress: Double = 0
        var bytesWritten: Int64 = 0
        var totalBytes: Int64 = 0
        var isDownloading: Bool = false
        var error: String? = nil
        var isComplete: Bool = false
        var retryCount: Int = 0
        var lastError: String? = nil
        /// nil = not yet checked, true = verified, false = verification failed/skipped
        var integrityVerified: Bool? = nil

        var speedBytesPerSec: Double = 0
        var lastSpeedUpdateTime: Date = Date()
        var lastSpeedUpdateBytes: Int64 = 0

        var progressPercentage: Int {
            guard totalBytes > 0 else { return 0 }
            return Int(progress * 100)
        }

        var downloadedSizeString: String {
            Self.formatBytes(bytesWritten)
        }

        var totalSizeString: String {
            guard totalBytes > 0 else { return "—" }
            return Self.formatBytes(totalBytes)
        }

        var speedString: String {
            guard speedBytesPerSec > 0 else { return "" }
            let mbps = speedBytesPerSec / 1_048_576
            if mbps >= 1.0 {
                return String(format: "%.0f MB/s", mbps)
            } else {
                return String(format: "%.0f KB/s", speedBytesPerSec / 1024)
            }
        }

        var etaString: String {
            guard speedBytesPerSec > 0, totalBytes > bytesWritten else { return "" }
            let remainingBytes = Double(totalBytes - bytesWritten)
            let seconds = remainingBytes / speedBytesPerSec
            if seconds < 60 {
                return String(format: "~%.0fs", seconds)
            } else if seconds < 3600 {
                return String(format: "~%.0f min", seconds / 60)
            } else {
                let hours = Int(seconds / 3600)
                let mins = Int(seconds.truncatingRemainder(dividingBy: 3600)) / 60
                return "~\(hours)h \(mins)m"
            }
        }

        static func formatBytes(_ bytes: Int64) -> String {
            if bytes < 1024 { return "\(bytes) bytes" }
            let kb = Double(bytes) / 1024
            if kb < 1024 { return String(format: "%.0f KB", kb) }
            let mb = kb / 1024
            if mb < 1024 { return String(format: "%.0f MB", mb) }
            let gb = mb / 1024
            return String(format: "%.2f GB", gb)
        }
    }

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionID)
        config.allowsCellularAccess = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: DownloadSessionDelegate.shared, delegateQueue: nil)

        loadPersistedResumeData()
        cleanupOldResumeData()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isExpensive = path.isExpensive
            let isConstrained = path.isConstrained
            let manager = self
            Task { @MainActor in
                manager?.isExpensive = isExpensive
                manager?.isConstrained = isConstrained
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    // MARK: - Resume Data Persistence (#7)

    /// Loads any persisted resume data from ~/Documents/models/.resume_data/
    private func loadPersistedResumeData() {
        guard FileManager.default.fileExists(atPath: Self.resumeDataURL.path) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.resumeDataURL, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files where file.pathExtension == "resume" {
            let filename = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file) {
                resumeData[filename] = data
                LamoLogger.download.info("Loaded persisted resume data for \(filename)")
            }
        }
    }

    /// Removes resume data files older than 7 days.
    private func cleanupOldResumeData() {
        guard FileManager.default.fileExists(atPath: Self.resumeDataURL.path) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.resumeDataURL, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in files where file.pathExtension == "resume" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = attrs.creationDate,
               creationDate < cutoff {
                try? FileManager.default.removeItem(at: file)
                LamoLogger.download.debug("Cleaned up old resume data: \(file.lastPathComponent)")
            }
        }
    }

    /// Persists resume data to ~/Documents/models/.resume_data/
    private func persistResumeData(_ data: Data, for filename: String) {
        try? FileManager.default.createDirectory(at: Self.resumeDataURL, withIntermediateDirectories: true)
        let fileURL = Self.resumeDataURL.appendingPathComponent(filename + ".resume")
        try? data.write(to: fileURL)
        LamoLogger.download.info("Persisted resume data for \(filename)")
    }

    /// Removes persisted resume data for a filename.
    private func removePersistedResumeData(for filename: String) {
        let fileURL = Self.resumeDataURL.appendingPathComponent(filename + ".resume")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func download(model: PresetModel) {
        guard let url = model.downloadURL else { return }
        guard activeDownloads[model.filename]?.isDownloading != true else { return }

        if model.isFileValid {
            activeDownloads[model.filename] = DownloadState(progress: 1.0, isComplete: true)
            return
        }

        if isExpensive {
            // Use hardcoded size for cellular check — fast, no network needed.
            // The real size will come from the server during download.
            let sizeMB = Int64(model.fileSizeGB * 1024)
            if sizeMB > 500 {
                pendingCellularDownload = model
                return
            }
        }

        startDownload(model: model, url: url)
    }

    /// Called after user confirms cellular download.
    func confirmCellularDownload() {
        guard let model = pendingCellularDownload else { return }
        pendingCellularDownload = nil
        guard let url = model.downloadURL else { return }
        startDownload(model: model, url: url)
    }

    /// Called if user cancels cellular download.
    func cancelCellularDownload() {
        pendingCellularDownload = nil
    }

    private func startDownload(model: PresetModel, url: URL) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Total bytes will be updated from server's Content-Length in the delegate.
        // Start with 0 so the UI knows the size is unknown until server responds.
        activeDownloads[model.filename] = DownloadState(totalBytes: 0, isDownloading: true)

        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.filename) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }

        DownloadSessionDelegate.shared.pendingModels[model.filename] = model

        tasks[model.filename] = task
        task.resume()

        // Kick off SHA256 fetch in parallel with the model download
        Task { @MainActor in
            if let sha256 = await PresetModel.fetchSHA256(for: model) {
                self.pendingSHA256[model.filename] = sha256
                LamoLogger.download.info("SHA256 pre-fetched for \(model.filename)")
            }
        }
    }

    func cancelDownload(model: PresetModel) {
        guard let task = tasks[model.filename] else { return }
        task.cancel { [weak self] resumeData in
            guard let self, let resumeData else { return }
            Task { @MainActor in
                self.resumeData[model.filename] = resumeData
                self.persistResumeData(resumeData, for: model.filename)
            }
        }
        tasks.removeValue(forKey: model.filename)
        activeDownloads[model.filename]?.isDownloading = false
    }

    func deleteModel(_ model: PresetModel) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent("models").appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: fileURL)
        activeDownloads.removeValue(forKey: model.filename)
        removePersistedResumeData(for: model.filename)

        if ProviderManager.shared.litertLMModelPath == model.filename {
            ProviderManager.shared.litertLMModelPath = nil
            ProviderManager.shared.invalidateEngine()
        }
    }

    /// Compute SHA256 of a file using streaming (never loads entire file into memory).
    private func computeFileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 64 * 1024) // 64KB chunks
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func handleCompletion(filename: String, tempURL: URL?, error: Error?) {
        Task { @MainActor in
            guard self.activeDownloads[filename]?.isComplete != true else { return }

            if let error = error {
                self.activeDownloads[filename]?.lastError = error.localizedDescription
                self.activeDownloads[filename]?.error = error.localizedDescription
                self.activeDownloads[filename]?.isDownloading = false

                if let urlError = error as? URLError,
                   [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code),
                   let retryCount = self.activeDownloads[filename]?.retryCount, retryCount < 3 {
                    self.activeDownloads[filename]?.retryCount = retryCount + 1
                    self.activeDownloads[filename]?.error = "Retrying... (attempt \(retryCount + 1)/3)"
                    self.activeDownloads[filename]?.isDownloading = true
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

                if let model = DownloadSessionDelegate.shared.pendingModels[filename],
                   let modelURL = model.downloadURL {
                    // Use pre-fetched SHA256 if available (fetched in parallel with download)
                    if let expectedHash = self.pendingSHA256[filename], expectedHash.count == 64 {
                        let computedHash = try computeFileSHA256(at: destination)
                        if computedHash != expectedHash {
                            LamoLogger.download.error("SHA256 mismatch for \(filename): expected \(expectedHash), got \(computedHash)")
                            try FileManager.default.removeItem(at: destination)
                            self.activeDownloads[filename]?.error = "File integrity check failed. Please re-download."
                            self.activeDownloads[filename]?.isDownloading = false
                            self.activeDownloads[filename]?.integrityVerified = false
                            self.pendingSHA256.removeValue(forKey: filename)
                            self.tasks.removeValue(forKey: filename)
                            return
                        }
                        LamoLogger.download.info("SHA256 verified for \(filename)")
                        self.activeDownloads[filename]?.integrityVerified = true
                    } else {
                        // Fallback: fetch SHA256 now (slow path, no parallel pre-fetch available)
                        let sha256URL = URL(string: modelURL.absoluteString + ".sha256")
                        if let sha256URL = sha256URL {
                            do {
                                let (sha256Data, response) = try await URLSession.shared.data(from: sha256URL)
                                let httpResponse = response as? HTTPURLResponse
                                if httpResponse?.statusCode == 200 {
                                    let expectedHash = String(data: sha256Data, encoding: .utf8)?
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .split(separator: " ").first.map(String.init)
                                    if let expectedHash = expectedHash, expectedHash.count == 64 {
                                        let computedHash = try computeFileSHA256(at: destination)
                                        if computedHash != expectedHash {
                                            LamoLogger.download.error("SHA256 mismatch for \(filename): expected \(expectedHash), got \(computedHash)")
                                            try FileManager.default.removeItem(at: destination)
                                            self.activeDownloads[filename]?.error = "File integrity check failed. Please re-download."
                                            self.activeDownloads[filename]?.isDownloading = false
                                            self.activeDownloads[filename]?.integrityVerified = false
                                            self.tasks.removeValue(forKey: filename)
                                            return
                                        }
                                        LamoLogger.download.info("SHA256 verified for \(filename)")
                                        self.activeDownloads[filename]?.integrityVerified = true
                                    } else {
                                        self.activeDownloads[filename]?.integrityVerified = false
                                    }
                                } else {
                                    self.activeDownloads[filename]?.integrityVerified = false
                                }
                            } catch {
                                LamoLogger.download.warning("SHA256 verification skipped for \(filename): \(error.localizedDescription)")
                                self.activeDownloads[filename]?.integrityVerified = false
                            }
                        } else {
                            self.activeDownloads[filename]?.integrityVerified = false
                        }
                    }
                }

                self.activeDownloads[filename]?.isComplete = true
                self.activeDownloads[filename]?.isDownloading = false
                self.activeDownloads[filename]?.progress = 1.0
                self.activeDownloads[filename]?.retryCount = 0
                self.activeDownloads[filename]?.lastError = nil
                self.tasks.removeValue(forKey: filename)
                self.pendingSHA256.removeValue(forKey: filename)
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
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let filename = downloadTask.originalRequest?.url?.lastPathComponent else { return }
        Task { @MainActor in
            let now = Date()
            var state = DownloadManager.shared.activeDownloads[filename] ?? DownloadManager.DownloadState()

            // Throttle UI updates — only publish every 0.3s to avoid jitter
            let timeSinceLastUI = now.timeIntervalSince(state.lastSpeedUpdateTime)
            guard timeSinceLastUI >= 0.3 else { return }

            state.bytesWritten = totalBytesWritten

            // Use server-reported total if valid (>1MB = real Content-Length)
            if totalBytesExpectedToWrite > 1_000_000 {
                state.totalBytes = totalBytesExpectedToWrite
            }

            // Calculate progress from actual bytes
            if state.totalBytes > 0 {
                state.progress = min(Double(totalBytesWritten) / Double(state.totalBytes), 1.0)
            }

            // Smoothed speed calculation
            let deltaBytes = totalBytesWritten - state.lastSpeedUpdateBytes
            if deltaBytes > 0 && timeSinceLastUI > 0 {
                let instantSpeed = Double(deltaBytes) / timeSinceLastUI
                state.speedBytesPerSec = state.speedBytesPerSec > 0
                    ? state.speedBytesPerSec * 0.7 + instantSpeed * 0.3
                    : instantSpeed
            }
            state.lastSpeedUpdateTime = now
            state.lastSpeedUpdateBytes = totalBytesWritten

            DownloadManager.shared.activeDownloads[filename] = state
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let filename = task.originalRequest?.url?.lastPathComponent else { return }
        if let error = error as? URLError, error.code == .cancelled { return }
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
