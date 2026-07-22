import Foundation
import Combine
import Speech
import AVFoundation
import os

/// On-device speech recognition via SFSpeechRecognizer.
///
/// Requires `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription`
/// in Info.plist. All processing happens locally — no network.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""

    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.lamo", category: "Speech")

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.unavailable
        }

        // Stop any ongoing recognition
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.requestFailed
        }

        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        transcribedText = ""

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                }
            }

            if error != nil || result?.isFinal == true {
                self.stopAudio()
                Task { @MainActor in
                    self.isRecording = false
                }
            }
        }
    }

    func stopRecording() {
        stopAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

enum SpeechError: LocalizedError {
    case unavailable
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Speech recognition is unavailable. Check device settings."
        case .requestFailed:
            return "Failed to create recognition request."
        }
    }
}
