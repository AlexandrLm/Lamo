import Foundation
import HealthKit
import LiteRTLM

// MARK: - Health Tool

struct HealthTool: Tool {
    static let name = "health"
    static let description = "Read steps, heart rate, sleep, or weight from Health."

    @ToolParam(description: "Metric: steps, heart_rate, sleep, weight, or summary.")
    var mode: String

    @ToolParam(description: "Days to look back (1–30). Default 1.")
    var days: Int = 1

    private let store = HKHealthStore()


    enum CodingKeys: String, CodingKey {
        case mode
        case days
    }

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(
            name: Self.name,
            params: "{\"mode\": \"\(mode)\", \"days\": \(days)}"
        )

        let cappedDays = min(max(days, 1), 30)

        guard HKHealthStore.isHealthDataAvailable() else {
            let result: [String: Any] = ["error": "Health data is not available on this device."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        // Request authorization
        let typeIdentifiers: [HKQuantityTypeIdentifier] = [.stepCount, .heartRate, .bodyMass, .activeEnergyBurned]
        let categoryIdentifiers: [HKCategoryTypeIdentifier] = [.sleepAnalysis]
        let quantityTypes = typeIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        let categoryTypes = categoryIdentifiers.compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        let readTypes = Set<HKObjectType>(quantityTypes + categoryTypes)

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            let result: [String: Any] = ["error": "Health authorization denied: \(error.localizedDescription)"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        let rawResult: [String: Any]
        switch mode.lowercased() {
        case "steps":
            rawResult = try await fetchSteps(days: cappedDays)
        case "heart_rate":
            rawResult = try await fetchHeartRate(days: cappedDays)
        case "sleep":
            rawResult = try await fetchSleep(days: cappedDays)
        case "weight":
            rawResult = try await fetchWeight()
        case "summary":
            rawResult = try await fetchSummary()
        default:
            rawResult = ["error": "Unknown mode '\(mode)'. Valid modes: steps, heart_rate, sleep, weight, summary."]
        }

        let limit = await AgenticLoopBudget.shared.consumeIteration()
        let truncated = await TokenTruncator.truncateResult(rawResult, maxTokens: limit)

        await ToolCallReporter.shared.reportResult(name: Self.name, result: truncated)
        return truncated
    }

    // MARK: - Steps

    private func fetchSteps(days: Int) async throws -> [String: Any] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate.addingTimeInterval(Double(-days) * 86400)

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return ["error": "Step count type unavailable."]
        }

        var dailySteps: [[String: Any]] = []

        let calendar = Calendar.current
        for dayOffset in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: -(days - 1) + dayOffset, to: startDate),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            let steps: Double = await withCheckedContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, _ in
                    let sum = statistics?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    continuation.resume(returning: sum)
                }
                store.execute(query)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dailySteps.append(["date": formatter.string(from: dayStart), "steps": Int(steps)])
        }

        let totalSteps = dailySteps.reduce(0) { $0 + (($1["steps"] as? Int) ?? 0) }
        return [
            "mode": "steps",
            "days": days,
            "total_steps": totalSteps,
            "daily": dailySteps,
        ]
    }

    // MARK: - Heart Rate

    private func fetchHeartRate(days: Int) async throws -> [String: Any] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate.addingTimeInterval(Double(-days) * 86400)

        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return ["error": "Heart rate type unavailable."]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else {
            return ["mode": "heart_rate", "days": days, "sample_count": 0, "message": "No heart rate data available for this period."]
        }

        let values = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        let avg = values.reduce(0, +) / Double(values.count)
        guard let minHR = values.min(), let maxHR = values.max() else {
            return ["mode": "heart_rate", "days": days, "sample_count": values.count, "message": "Could not compute heart rate stats."]
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let recentValues = samples.prefix(10).map { sample -> [String: Any] in
            [
                "date": formatter.string(from: sample.endDate),
                "bpm": Int(sample.quantity.doubleValue(for: HKUnit(from: "count/min"))),
            ]
        }

        return [
            "mode": "heart_rate",
            "days": days,
            "sample_count": samples.count,
            "min_bpm": Int(minHR),
            "avg_bpm": Int(avg),
            "max_bpm": Int(maxHR),
            "recent": recentValues,
        ]
    }

    // MARK: - Sleep

    private func fetchSleep(days: Int) async throws -> [String: Any] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate.addingTimeInterval(Double(-days) * 86400)

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return ["error": "Sleep analysis type unavailable."]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else {
            return ["mode": "sleep", "days": days, "message": "No sleep data available for this period."]
        }

        // Group sleep samples by night (date of endDate)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var nights: [String: TimeInterval] = [:]
        for sample in samples {
            // Use the end date to determine which "night" this sleep belongs to
            // (sleep ending early morning is assigned to the previous day's night)
            let nightDate = calendar.startOfDay(for: sample.endDate)
            let key = formatter.string(from: nightDate)
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            nights[key, default: 0] += duration
        }

        var dailySleep: [[String: Any]] = []
        var totalDuration: TimeInterval = 0
        let sortedNights = nights.sorted { $0.key < $1.key }
        for (dateKey, duration) in sortedNights {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            dailySleep.append([
                "date": dateKey,
                "duration_hours": Double(hours) + Double(minutes) / 60.0,
                "duration_display": "\(hours)h \(minutes)m",
            ])
            totalDuration += duration
        }

        let avgHours = sortedNights.isEmpty ? 0 : (totalDuration / Double(sortedNights.count)) / 3600.0

        return [
            "mode": "sleep",
            "days": days,
            "nights_tracked": sortedNights.count,
            "total_sleep_hours": (totalDuration / 3600.0).rounded(to: 1),
            "avg_sleep_hours": avgHours.rounded(to: 1),
            "daily": dailySleep,
        ]
    }

    // MARK: - Weight

    private func fetchWeight() async throws -> [String: Any] {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return ["error": "Body mass type unavailable."]
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample])?.first)
            }
            store.execute(query)
        }

        guard let sample = sample else {
            return ["mode": "weight", "message": "No weight data available."]
        }

        let weightKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        let weightLb = weightKg * 2.20462

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return [
            "mode": "weight",
            "weight_kg": weightKg.rounded(to: 1),
            "weight_lb": weightLb.rounded(to: 1),
            "date": formatter.string(from: sample.endDate),
        ]
    }

    // MARK: - Summary

    private func fetchSummary() async throws -> [String: Any] {
        let today = Date()
        let startOfDay = Calendar.current.startOfDay(for: today)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: today, options: .strictStartDate)

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return ["error": "Health data types unavailable."]
        }

        async let stepsToday = fetchStatisticSum(quantityType: stepType, predicate: predicate, unit: HKUnit.count())
        async let energyToday = fetchStatisticSum(quantityType: energyType, predicate: predicate, unit: HKUnit.kilocalorie())
        async let sleepToday = fetchCategoryDuration(categoryType: sleepType, predicate: predicate)

        let (steps, energy, sleep) = await (stepsToday, energyToday, sleepToday)

        let sleepHours = sleep / 3600.0

        return [
            "mode": "summary",
            "date": ISO8601DateFormatter().string(from: today).prefix(10),
            "steps_today": Int(steps),
            "active_energy_kcal": Int(energy),
            "sleep_hours_today": sleepHours.rounded(to: 1),
        ]
    }

    // MARK: - HealthKit Async Helpers

    private func fetchStatisticSum(quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let sum = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(query)
        }
    }

    private func fetchCategoryDuration(categoryType: HKCategoryType, predicate: NSPredicate) async -> TimeInterval {
        await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, _ in
                let samples = (results as? [HKCategorySample]) ?? []
                let total = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
