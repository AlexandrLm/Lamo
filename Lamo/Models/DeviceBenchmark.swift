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
    @Published var currentPhase: BenchmarkPhase = .idle
    @Published var errorMessage: String?

    enum BenchmarkPhase: String, CaseIterable, Hashable {
        case idle
        case deviceInfo = "Device Info"
        case cpuTest = "CPU Test"
        case gpuTest = "GPU Test"
        case memoryTest = "Memory"
        case analyzing = "Analyzing"

        var icon: String {
            switch self {
            case .idle: return "circle.dashed"
            case .deviceInfo: return "info.circle.fill"
            case .cpuTest: return "cpu.fill"
            case .gpuTest: return "gpu.fill"
            case .memoryTest: return "memorychip"
            case .analyzing: return "sparkle.magnifyingglass"
            }
        }
    }

    struct BenchmarkResult: Codable {
        let deviceName: String
        let chipName: String
        let ramGB: Double
        let storageFreeGB: Double
        let hasGPU: Bool
        let gpuCoreCount: Int
        let hasNeuralEngine: Bool
        let cpuSingleCore: Double
        let cpuMultiCore: Double
        let gpuScore: Double
        let memoryBandwidthGBps: Double
        let combinedScore: Double
        let aiTier: AITier
        let recommendations: [Recommendation]
        let cpuTime: Double
        let gpuTime: Double
        let memoryTime: Double
        let totalTime: Double

        var cpuScore: Double { cpuSingleCore }

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

        var scoreNormalized: Double {
            min(combinedScore / 5.0, 1.0)
        }

        var cpuNormalized: Double { min(cpuSingleCore / 3.0, 1.0) }
        var cpuMultiNormalized: Double { min(cpuMultiCore / 8.0, 1.0) }
        var gpuNormalized: Double { min(gpuScore / 10.0, 1.0) }
        var memoryNormalized: Double { min(memoryBandwidthGBps / 70.0, 1.0) }

        var modelCompatibility: [ModelCompat] {
            var compat: [ModelCompat] = []
            if ramGB >= 6 && combinedScore >= 1.5 {
                compat.append(ModelCompat(name: "Gemma 4 E4B", size: "3.3 GB", status: .optimal, icon: "checkmark.circle.fill"))
            } else if ramGB >= 4 {
                compat.append(ModelCompat(name: "Gemma 4 E4B", size: "3.3 GB", status: .slow, icon: "exclamationmark.circle.fill"))
            }
            if ramGB >= 3 && combinedScore >= 0.3 {
                compat.append(ModelCompat(name: "Gemma 4 E2B", size: "1.7 GB", status: .optimal, icon: "checkmark.circle.fill"))
            }
            return compat
        }

        var maxConcurrentTokens: Int {
            if ramGB >= 8 { return 4096 }
            if ramGB >= 6 { return 2048 }
            if ramGB >= 4 { return 1024 }
            return 512
        }
    }

    struct ModelCompat: Identifiable, Codable {
        let name: String
        let size: String
        let status: CompatStatus
        let icon: String
        let id: String

        init(name: String, size: String, status: CompatStatus, icon: String) {
            self.name = name
            self.size = size
            self.status = status
            self.icon = icon
            self.id = UUID().uuidString
        }

        enum CompatStatus: String, Codable {
            case optimal, slow, incompatible
            var color: String {
                switch self {
                case .optimal: return "green"
                case .slow: return "orange"
                case .incompatible: return "red"
                }
            }
            var label: String {
                switch self {
                case .optimal: return "Optimal"
                case .slow: return "Usable"
                case .incompatible: return "Not Supported"
                }
            }
        }
    }

    enum AITier: String, Codable {
        case excellent, good, moderate, limited
    }

    struct Recommendation: Identifiable, Codable {
        let icon: String
        let title: String
        let detail: String
        let id: String

        init(icon: String, title: String, detail: String) {
            self.icon = icon
            self.title = title
            self.detail = detail
            self.id = UUID().uuidString
        }
    }

    func runBenchmark() async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        result = nil
        errorMessage = nil
        currentPhase = .deviceInfo

        // Phase 1: Device info
        progress = 0.05
        let deviceName = await getDeviceName()
        let chipName = getChipName()
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let storageFree = getFreeStorageGB()
        let gpuInfo = getGPUInfo()
        let hasGPU = gpuInfo.hasGPU
        let gpuCores = gpuInfo.coreCount
        let hasANE = detectNeuralEngine()
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        progress = 0.10

        // Phase 2: CPU benchmark (single + multi core)
        currentPhase = .cpuTest
        let cpuStart = CFAbsoluteTimeGetCurrent()
        let cpuSingle = runCPUSingleCore()
        progress = 0.25
        let cpuMulti = runCPUMultiCore(threads: coreCount)
        let cpuTime = CFAbsoluteTimeGetCurrent() - cpuStart
        progress = 0.50

        // Phase 3: GPU benchmark
        currentPhase = hasGPU ? .gpuTest : .memoryTest
        let gpuStart = CFAbsoluteTimeGetCurrent()
        let gpuScore = hasGPU ? runGPUMatMul() : 0
        let gpuTime = hasGPU ? CFAbsoluteTimeGetCurrent() - gpuStart : 0
        progress = 0.70

        // Phase 4: Memory bandwidth
        currentPhase = .memoryTest
        let memStart = CFAbsoluteTimeGetCurrent()
        let memBW = runMemoryBandwidth()
        let memoryTime = CFAbsoluteTimeGetCurrent() - memStart
        progress = 0.85

        // Phase 5: Analysis
        currentPhase = .analyzing
        let combinedScore = computeCombinedScore(
            cpuSingle: cpuSingle, cpuMulti: cpuMulti,
            gpuScore: gpuScore, memBW: memBW,
            hasGPU: hasGPU, hasANE: hasANE, gpuCores: gpuCores
        )
        let tier = rateDevice(ramGB: ramGB, combinedScore: combinedScore, gpuCores: gpuCores, hasGPU: hasGPU, hasANE: hasANE)
        let recs = buildRecommendations(tier: tier, ramGB: ramGB, hasGPU: hasGPU, hasANE: hasANE, storageFree: storageFree, memBW: memBW)
        let totalTime = cpuTime + gpuTime + memoryTime

        progress = 1.0

        result = BenchmarkResult(
            deviceName: deviceName,
            chipName: chipName,
            ramGB: ramGB,
            storageFreeGB: storageFree,
            hasGPU: hasGPU,
            gpuCoreCount: gpuCores,
            hasNeuralEngine: hasANE,
            cpuSingleCore: cpuSingle,
            cpuMultiCore: cpuMulti,
            gpuScore: gpuScore,
            memoryBandwidthGBps: memBW,
            combinedScore: combinedScore,
            aiTier: tier,
            recommendations: recs,
            cpuTime: cpuTime,
            gpuTime: gpuTime,
            memoryTime: memoryTime,
            totalTime: totalTime
        )

        // Persist result so it survives app restart
        saveResult()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isRunning = false
        currentPhase = .idle
    }

    // MARK: - Persistence

    private static let storageKey = "com.lamo.benchmark.result"

    init() {
        // Load previously saved result on startup
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(BenchmarkResult.self, from: data) {
            result = decoded
        }
    }

    private func saveResult() {
        guard let result else { return }
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Device Info

    private func getDeviceName() async -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { rawPtr -> String in
            let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
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

    private func detectNeuralEngine() -> Bool {
        // Apple Neural Engine exists on A12+ and all Apple Silicon
        // Detection via sysctl or chip name heuristic
        let chip = getChipName().lowercased()
        return chip.contains("a1") || chip.contains("m1") || chip.contains("m2") ||
               chip.contains("m3") || chip.contains("m4") || chip.contains("a2")
    }

    // MARK: - CPU Single-Core Benchmark

    /// 512x512 matrix multiply on a single thread. Returns GFLOPS.
    private func runCPUSingleCore() -> Double {
        let size = 512
        let iterations = 2
        let a = (0..<(size * size)).map { _ in Float.random(in: -1...1) }
        let b = (0..<(size * size)).map { _ in Float.random(in: -1...1) }
        var c = [Float](repeating: 0, count: size * size)

        var totalTime: CFAbsoluteTime = 0

        for _ in 0..<iterations {
            c = [Float](repeating: 0, count: size * size)
            let start = CFAbsoluteTimeGetCurrent()

            for i in 0..<size {
                for k in 0..<size {
                    let aik = a[i * size + k]
                    for j in 0..<size {
                        c[i * size + j] += aik * b[k * size + j]
                    }
                }
            }

            totalTime += CFAbsoluteTimeGetCurrent() - start
            _ = c[0]
        }

        let avgTime = totalTime / Double(iterations)
        let flops = 2.0 * Double(size) * Double(size) * Double(size)
        return flops / avgTime / 1_000_000_000
    }

    // MARK: - CPU Multi-Core Benchmark

    /// Parallel matrix multiply across N threads. Returns aggregate GFLOPS.
    private func runCPUMultiCore(threads: Int) -> Double {
        let size = 512
        let iterations = 2
        let a = (0..<(size * size)).map { _ in Float.random(in: -1...1) }
        let b = (0..<(size * size)).map { _ in Float.random(in: -1...1) }

        var totalTime: CFAbsoluteTime = 0

        for _ in 0..<iterations {
            let c = [Float](repeating: 0, count: size * size)
            let start = CFAbsoluteTimeGetCurrent()

            // Each thread computes a chunk of rows
            let rowsPerThread = size / threads
            DispatchQueue.concurrentPerform(iterations: threads) { threadIdx in
                let startRow = threadIdx * rowsPerThread
                let endRow = (threadIdx == threads - 1) ? size : startRow + rowsPerThread
                // We need mutable access — use UnsafeMutableBufferPointer
                c.withUnsafeBufferPointer { cBuf in
                    // This is safe because rows don't overlap
                }
                // Simpler approach: just do the work directly
                for i in startRow..<endRow {
                    for k in 0..<size {
                        let aik = a[i * size + k]
                        for j in 0..<size {
                            // Write to local var, we'll accumulate after
                        }
                    }
                }
            }

            totalTime += CFAbsoluteTimeGetCurrent() - start
            _ = c[0]
        }

        // The above concurrent version is tricky with value types.
        // Use a simpler but still multi-threaded approach:
        var totalTime2: CFAbsoluteTime = 0
        for _ in 0..<iterations {
            let results = UnsafeMutablePointer<Float>.allocate(capacity: size * size)
            defer { results.deallocate() }
            memset(results, 0, size * size * MemoryLayout<Float>.size)

            let start = CFAbsoluteTimeGetCurrent()

            DispatchQueue.concurrentPerform(iterations: threads) { threadIdx in
                let rowsPerThread = size / threads
                let startRow = threadIdx * rowsPerThread
                let endRow = (threadIdx == threads - 1) ? size : startRow + rowsPerThread
                for i in startRow..<endRow {
                    for k in 0..<size {
                        let aik = a[i * size + k]
                        for j in 0..<size {
                            results[i * size + j] += aik * b[k * size + j]
                        }
                    }
                }
            }

            totalTime2 += CFAbsoluteTimeGetCurrent() - start
            _ = results[0]
        }

        let avgTime = totalTime2 / Double(iterations)
        let flops = 2.0 * Double(size) * Double(size) * Double(size)
        return flops / avgTime / 1_000_000_000
    }

    // MARK: - GPU Matrix Multiply Benchmark

    /// Metal matrix multiply kernel — more representative of AI workloads than vector add.
    private func runGPUMatMul() -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }
        guard let commandQueue = device.makeCommandQueue() else { return 0 }

        let N = 256 // 256x256 matrix
        let count = N * N
        let iterations = 5

        guard let bufferA = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared) else {
            return 0
        }

        let ptrA = bufferA.contents().bindMemory(to: Float.self, capacity: count)
        let ptrB = bufferB.contents().bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            ptrA[i] = Float.random(in: -1...1)
            ptrB[i] = Float.random(in: -1...1)
        }

        // Metal compute shader for tiled matrix multiply
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void matMul(device const float* A [[buffer(0)]],
                           device const float* B [[buffer(1)]],
                           device float* C [[buffer(2)]],
                           constant uint& N [[buffer(3)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= N || gid.y >= N) return;
            float sum = 0.0;
            for (uint k = 0; k < N; k++) {
                sum += A[gid.y * N + k] * B[k * N + gid.x];
            }
            C[gid.y * N + gid.x] = sum;
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let function = library.makeFunction(name: "matMul"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            // Fallback to vector add if matMul fails
            return runGPUVectorAdd(device: device, commandQueue: commandQueue)
        }

        // Set N constant
        var nVal = UInt32(N)
        let nBuffer = device.makeBuffer(bytes: &nVal, length: MemoryLayout<UInt32>.size, options: .storageModeShared)

        // Warm up
        if let cb = commandQueue.makeCommandBuffer(),
           let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(bufferA, offset: 0, index: 0)
            enc.setBuffer(bufferB, offset: 0, index: 1)
            enc.setBuffer(bufferC, offset: 0, index: 2)
            enc.setBuffer(nBuffer, offset: 0, index: 3)
            let gridSize = MTLSize(width: N, height: N, depth: 1)
            let tgSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, N), height: min(pipeline.maxTotalThreadsPerThreadgroup / N, N), depth: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }

        var totalTime: CFAbsoluteTime = 0
        for _ in 0..<iterations {
            guard let cb = commandQueue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { continue }
            let start = CFAbsoluteTimeGetCurrent()
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(bufferA, offset: 0, index: 0)
            enc.setBuffer(bufferB, offset: 0, index: 1)
            enc.setBuffer(bufferC, offset: 0, index: 2)
            enc.setBuffer(nBuffer, offset: 0, index: 3)
            let gridSize = MTLSize(width: N, height: N, depth: 1)
            let tgSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, N), height: min(pipeline.maxTotalThreadsPerThreadgroup / N, N), depth: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            totalTime += CFAbsoluteTimeGetCurrent() - start
        }

        let avgTime = totalTime / Double(iterations)
        let flops = 2.0 * Double(N) * Double(N) * Double(N)
        return flops / avgTime / 1_000_000_000
    }

    /// Fallback GPU benchmark using vector add.
    private func runGPUVectorAdd(device: MTLDevice, commandQueue: MTLCommandQueue) -> Double {
        let count = 1_000_000
        let iterations = 10

        guard let bufferA = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared) else {
            return 0
        }

        let ptrA = bufferA.contents().bindMemory(to: Float.self, capacity: count)
        let ptrB = bufferB.contents().bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            ptrA[i] = Float.random(in: -1...1)
            ptrB[i] = Float.random(in: -1...1)
        }

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void vectorAdd(device float* A [[buffer(0)]],
                             device float* B [[buffer(1)]],
                             device float* C [[buffer(2)]],
                             uint id [[thread_position_in_grid]]) {
            C[id] = A[id] + B[id];
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let function = library.makeFunction(name: "vectorAdd"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return 0
        }

        // Warm up
        if let cb = commandQueue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(bufferA, offset: 0, index: 0)
            enc.setBuffer(bufferB, offset: 0, index: 1)
            enc.setBuffer(bufferC, offset: 0, index: 2)
            let gridSize = MTLSize(width: count, height: 1, depth: 1)
            let tgSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, count), height: 1, depth: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }

        var totalTime: CFAbsoluteTime = 0
        for _ in 0..<iterations {
            guard let cb = commandQueue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { continue }
            let start = CFAbsoluteTimeGetCurrent()
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(bufferA, offset: 0, index: 0)
            enc.setBuffer(bufferB, offset: 0, index: 1)
            enc.setBuffer(bufferC, offset: 0, index: 2)
            let gridSize = MTLSize(width: count, height: 1, depth: 1)
            let tgSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, count), height: 1, depth: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            totalTime += CFAbsoluteTimeGetCurrent() - start
        }

        let avgTime = totalTime / Double(iterations)
        let flops = 2.0 * Double(count)
        return flops / avgTime / 1_000_000_000
    }

    // MARK: - Memory Bandwidth

    /// Measures sequential memory read bandwidth (GB/s). Important for model loading and KV-cache.
    private func runMemoryBandwidth() -> Double {
        let sizeMB = 64
        let sizeBytes = sizeMB * 1024 * 1024
        let iterations = 20

        guard let buffer = malloc(sizeBytes) else { return 0 }
        defer { free(buffer) }

        // Fill with data
        let ptr = buffer.assumingMemoryBound(to: UInt8.self)
        for i in 0..<sizeBytes {
            ptr[i] = UInt8(i & 0xFF)
        }

        var totalTime: CFAbsoluteTime = 0
        var sink: UInt8 = 0

        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            // Sequential read — tests memory bandwidth
            let intPtr = buffer.assumingMemoryBound(to: UInt64.self)
            let count = sizeBytes / MemoryLayout<UInt64>.size
            var acc: UInt64 = 0
            for i in 0..<count {
                acc &+= intPtr[i]
            }
            sink = UInt8(acc & 0xFF)
            totalTime += CFAbsoluteTimeGetCurrent() - start
        }

        _ = sink
        let avgTime = totalTime / Double(iterations)
        let bytesPerSec = Double(sizeBytes) / avgTime
        return bytesPerSec / 1_000_000_000 // GB/s
    }

    // MARK: - Scoring

    private func computeCombinedScore(
        cpuSingle: Double, cpuMulti: Double,
        gpuScore: Double, memBW: Double,
        hasGPU: Bool, hasANE: Bool, gpuCores: Int
    ) -> Double {
        // Weighted combination reflecting AI inference characteristics:
        // - Single-core CPU: 25% (token generation is sequential)
        // - Multi-core CPU: 15% (prompt processing can be parallel)
        // - GPU: 40% (matrix multiply is the core AI operation)
        // - Memory bandwidth: 20% (KV-cache and model loading are bandwidth-bound)
        var score = cpuSingle * 0.25
        score += cpuMulti * 0.15
        if hasGPU {
            score += gpuScore * 0.40
        }
        score += memBW * 0.20 * 0.1 // Scale memory BW contribution

        // Bonus for Neural Engine (can accelerate INT8 inference)
        if hasANE {
            score *= 1.15
        }

        return score
    }

    private func rateDevice(ramGB: Double, combinedScore: Double, gpuCores: Int, hasGPU: Bool, hasANE: Bool) -> AITier {
        var score = 0

        // RAM scoring (0-3)
        if ramGB >= 7 { score += 3 }
        else if ramGB >= 5 { score += 2 }
        else if ramGB >= 3 { score += 1 }

        // GPU scoring (0-2)
        if hasGPU {
            score += gpuCores >= 5 ? 2 : 1
        }

        // Neural Engine bonus (0-1)
        if hasANE { score += 1 }

        // Compute scoring (0-3)
        if combinedScore >= 2.0 { score += 3 }
        else if combinedScore >= 1.0 { score += 2 }
        else if combinedScore >= 0.5 { score += 1 }

        if score >= 8 { return .excellent }
        if score >= 5 { return .good }
        if score >= 3 { return .moderate }
        return .limited
    }

    // MARK: - Recommendations

    private func buildRecommendations(tier: AITier, ramGB: Double, hasGPU: Bool, hasANE: Bool, storageFree: Double, memBW: Double) -> [Recommendation] {
        var recs: [Recommendation] = []

        switch tier {
        case .excellent:
            recs.append(Recommendation(
                icon: "sparkles",
                title: "Best Experience",
                detail: "Your device handles all models at full quality. Gemma 4 E4B recommended for best results."
            ))
        case .good:
            recs.append(Recommendation(
                icon: "hand.thumbsup",
                title: "Great Performance",
                detail: "Both models run well. E4B for quality, E2B for faster responses."
            ))
        case .moderate:
            recs.append(Recommendation(
                icon: "bolt.horizontal",
                title: "Recommended: Compact Model",
                detail: "Gemma 4 E2B will give you the best speed-to-quality ratio."
            ))
        case .limited:
            recs.append(Recommendation(
                icon: "exclamationmark.triangle",
                title: "Performance May Be Slow",
                detail: "Expect longer response times. Use E2B and keep context short for best results."
            ))
        }

        if hasANE {
            recs.append(Recommendation(
                icon: "brain.head.profile",
                title: "Neural Engine Available",
                detail: "Your device has a Neural Engine that can accelerate INT8 quantized inference."
            ))
        }

        if !hasGPU {
            recs.append(Recommendation(
                icon: "cpu",
                title: "No GPU Acceleration",
                detail: "Inference will use CPU only. Performance will be significantly slower."
            ))
        }

        if memBW < 20 {
            recs.append(Recommendation(
                icon: "memorychip",
                title: "Low Memory Bandwidth",
                detail: String(format: "%.0f GB/s measured. Model loading and token generation may be slower.", memBW)
            ))
        }

        if ramGB < 4 {
            recs.append(Recommendation(
                icon: "memorychip",
                title: "Low Memory",
                detail: "Close other apps before using AI to ensure enough memory is available."
            ))
        }

        if storageFree < 5 {
            recs.append(Recommendation(
                icon: "internaldrive",
                title: "Low Storage",
                detail: "You have \(String(format: "%.1f", storageFree)) GB free. Models need 2–4 GB of storage."
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
