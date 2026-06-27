import Foundation
import UIKit
import Metal
import Combine

/// Analyzes device capabilities and estimates AI performance.
@MainActor
final class DeviceBenchmark: ObservableObject {
    @Published var result: BenchmarkResult?
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?

    struct BenchmarkResult {
        let deviceName: String
        let chipName: String
        let ramGB: Double
        let storageFreeGB: Double
        let hasGPU: Bool
        let gpuCoreCount: Int
        let computeScore: Double
        let aiTier: AITier
        let recommendations: [Recommendation]

        var aiTierLabel: String {
            switch aiTier {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .moderate: return "Moderate"
            case .limited: return "Limited"
            }
        }

        var aiTierIcon: String {
            switch aiTier {
            case .excellent: return "bolt.fill"
            case .good: return "hand.thumbsup.fill"
            case .moderate: return "gauge.medium"
            case .limited: return "exclamationmark.triangle.fill"
            }
        }

        var aiTierColor: String {
            switch aiTier {
            case .excellent: return "green"
            case .good: return "blue"
            case .moderate: return "orange"
            case .limited: return "red"
            }
        }
    }

    enum AITier {
        case excellent, good, moderate, limited
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    func runBenchmark() async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        result = nil
        errorMessage = nil

        do {
            // Phase 1: Device info (instant)
            progress = 0.1
            let deviceName = await getDeviceName()
            let chipName = getChipName()
            let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            let storageFree = getFreeStorageGB()
            let gpuInfo = getGPUInfo()
            let hasGPU = gpuInfo.hasGPU
            let gpuCores = gpuInfo.coreCount

            progress = 0.3

            // Phase 2: Compute benchmark
            let computeScore = runComputeTest()
            progress = 0.8

            // Phase 3: Rate the device
            let tier = rateDevice(ramGB: ramGB, computeScore: computeScore, gpuCores: gpuCores, hasGPU: hasGPU)

            // Phase 4: Build recommendations
            let recs = buildRecommendations(tier: tier, ramGB: ramGB, hasGPU: hasGPU, storageFree: storageFree)

            progress = 1.0

            result = BenchmarkResult(
                deviceName: deviceName,
                chipName: chipName,
                ramGB: ramGB,
                storageFreeGB: storageFree,
                hasGPU: hasGPU,
                gpuCoreCount: gpuCores,
                computeScore: computeScore,
                aiTier: tier,
                recommendations: recs
            )
        } catch {
            errorMessage = "Benchmark failed: \(error.localizedDescription)"
        }

        isRunning = false
    }

    // MARK: - Device Info

    private func getDeviceName() async -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapDeviceIdentifier(identifier)
    }

    private func getChipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chip = [CChar](repeating: 0, count: size + 1)
        sysctlbyname("machdep.cpu.brand_string", &chip, &size, nil, 0)
        return String(cString: chip)
    }

    private func getFreeStorageGB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
              let freeBytes = attrs[.systemFreeSize] as? UInt64 else { return 0 }
        return Double(freeBytes) / 1_073_741_824
    }

    private func getGPUInfo() -> (hasGPU: Bool, coreCount: Int) {
        guard let device = MTLCreateSystemDefaultDevice() else { return (false, 0) }
        let cores: Int = {
            if device.supportsFamily(.apple9) { return 6 }
            if device.supportsFamily(.apple8) { return 5 }
            if device.supportsFamily(.apple7) { return 5 }
            if device.supportsFamily(.apple6) { return 4 }
            if device.supportsFamily(.apple5) { return 4 }
            return 3
        }()
        return (true, cores)
    }

    // MARK: - Compute Benchmark

    /// Runs a matrix multiplication benchmark to measure raw compute.
    /// Returns time in seconds (lower = better).
    private func runComputeTest() -> Double {
        let size = 256
        var a = [Float](repeating: 0, count: size * size)
        var b = [Float](repeating: 0, count: size * size)
        var c = [Float](repeating: 0, count: size * size)

        for i in 0..<(size * size) {
            a[i] = Float.random(in: -1...1)
            b[i] = Float.random(in: -1...1)
        }

        let start = CFAbsoluteTimeGetCurrent()

        for i in 0..<size {
            for k in 0..<size {
                let aik = a[i * size + k]
                for j in 0..<size {
                    c[i * size + j] += aik * b[k * size + j]
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        _ = c[0]

        return elapsed
    }

    // MARK: - Rating

    private func rateDevice(ramGB: Double, computeScore: Double, gpuCores: Int, hasGPU: Bool) -> AITier {
        var score = 0

        if ramGB >= 7 { score += 3 }
        else if ramGB >= 5 { score += 2 }
        else if ramGB >= 3 { score += 1 }

        if hasGPU {
            score += gpuCores >= 5 ? 2 : 1
        }

        if computeScore < 0.5 { score += 3 }
        else if computeScore < 1.0 { score += 2 }
        else if computeScore < 2.0 { score += 1 }

        if score >= 7 { return .excellent }
        if score >= 5 { return .good }
        if score >= 3 { return .moderate }
        return .limited
    }

    // MARK: - Recommendations

    private func buildRecommendations(tier: AITier, ramGB: Double, hasGPU: Bool, storageFree: Double) -> [Recommendation] {
        var recs: [Recommendation] = []

        switch tier {
        case .excellent:
            recs.append(Recommendation(
                icon: "sparkles",
                title: "Best Experience",
                detail: "Your device handles all models. Try Gemma 4 E4B for the highest quality."
            ))
        case .good:
            recs.append(Recommendation(
                icon: "hand.thumbsup",
                title: "Great Performance",
                detail: "Your device works well with both models. E4B for quality, E2B for speed."
            ))
        case .moderate:
            recs.append(Recommendation(
                icon: "bolt.horizontal",
                title: "Recommended: Compact Model",
                detail: "Use Gemma 4 E2B for the best balance of speed and quality."
            ))
        case .limited:
            recs.append(Recommendation(
                icon: "exclamationmark.triangle",
                title: "Performance May Be Slow",
                detail: "AI models will work but responses will take longer. Use E2B for best results."
            ))
        }

        if !hasGPU {
            recs.append(Recommendation(
                icon: "gpu",
                title: "No GPU Detected",
                detail: "GPU acceleration is unavailable. Inference will use CPU only."
            ))
        }

        if ramGB < 4 {
            recs.append(Recommendation(
                icon: "memorychip",
                title: "Low Memory",
                detail: "Close other apps before using AI to free up memory."
            ))
        }

        if storageFree < 5 {
            recs.append(Recommendation(
                icon: "internaldrive",
                title: "Low Storage",
                detail: "You have \(String(format: "%.1f", storageFree)) GB free. Models need 2–4 GB."
            ))
        }

        return recs
    }

    // MARK: - Device Mapping

    private func mapDeviceIdentifier(_ id: String) -> String {
        let map: [String: String] = [
            "iPhone18,1": "iPhone 17",
            "iPhone18,2": "iPhone 17 Pro",
            "iPhone18,3": "iPhone 17 Pro Max",
            "iPhone18,4": "iPhone 17 Air",
            "iPhone17,1": "iPhone 16 Pro Max",
            "iPhone17,2": "iPhone 16 Pro",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone16,1": "iPhone 15 Pro Max",
            "iPhone16,2": "iPhone 15 Pro",
            "iPhone16,3": "iPhone 15",
            "iPhone16,4": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 14",
            "iPhone15,5": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPad16,3": "iPad Pro (M4)",
            "iPad16,4": "iPad Pro (M4)",
            "iPad14,3": "iPad Pro (M2)",
            "iPad14,4": "iPad Pro (M2)",
            "iPad13,4": "iPad Pro (M1)",
            "iPad13,5": "iPad Pro (M1)",
            "iPad14,8": "iPad Air (M2)",
            "iPad14,9": "iPad Air (M2)",
            "iPad13,16": "iPad Air (M1)",
            "iPad13,17": "iPad Air (M1)",
        ]
        return map[id] ?? id
    }
}
