import Foundation
import LiteRTLM
import EventKit

// MARK: - Calendar Availability Tool

struct CalendarAvailabilityTool: Tool {
    static let name = "calendar_availability"
    static let description = "Find free time slots in your calendar."

    @ToolParam(description: "Desired slot duration in minutes. Default 60 (1 hour).")
    var durationMinutes: Int = 60

    @ToolParam(description: "Start of search range in YYYY-MM-DD format. Default: today.")
    var startDate: String?

    @ToolParam(description: "End of search range in YYYY-MM-DD format. Default: today + 7 days.")
    var endDate: String?

    @ToolParam(description: "Working hours start (0–23). Slots only within working hours. Default 9.")
    var workHoursStart: Int = 9

    @ToolParam(description: "Working hours end (0–23). Slots only within working hours. Default 18.")
    var workHoursEnd: Int = 18

    @ToolParam(description: "Maximum number of slots to return. Default 10.")
    var maxSlots: Int = 10

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(
            name: Self.name,
            params: """
            {"duration_minutes": \(durationMinutes), "start_date": \(startDate.map { "\"\($0)\"" } ?? "null"), \
            "end_date": \(endDate.map { "\"\($0)\"" } ?? "null"), "work_hours_start": \(workHoursStart), \
            "work_hours_end": \(workHoursEnd), "max_slots": \(maxSlots)}
            """
        )

        // Validate parameters
        let duration = max(1, durationMinutes)
        let workStart = max(0, min(23, workHoursStart))
        let workEnd = max(0, min(23, workHoursEnd))
        let maxSlotsCap = max(1, maxSlots)

        guard workStart < workEnd else {
            let errorResult: [String: Any] = ["error": "work_hours_start must be less than work_hours_end"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: errorResult)
            let limit = await AgenticLoopBudget.shared.consumeIteration()
            return await TokenTruncator.truncateResult(errorResult, maxTokens: limit)
        }

        // Parse date range
        let cal = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = cal.startOfDay(for: Date())

        let rangeStart: Date
        if let startStr = startDate, !startStr.isEmpty, let parsed = dateFormatter.date(from: startStr) {
            rangeStart = cal.startOfDay(for: parsed)
        } else {
            rangeStart = today
        }

        let rangeEnd: Date
        if let endStr = endDate, !endStr.isEmpty, let parsed = dateFormatter.date(from: endStr) {
            rangeEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: parsed)) ?? cal.date(byAdding: .day, value: 8, to: today)!
        } else {
            rangeEnd = cal.date(byAdding: .day, value: 8, to: today)!
        }

        guard rangeStart < rangeEnd else {
            let errorResult: [String: Any] = ["error": "start_date must be before end_date"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: errorResult)
            let limit = await AgenticLoopBudget.shared.consumeIteration()
            return await TokenTruncator.truncateResult(errorResult, maxTokens: limit)
        }

        // Request calendar access
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }

        guard granted else {
            let errorResult: [String: Any] = ["error": "Calendar access denied. Enable in Settings > Privacy > Calendars."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: errorResult)
            let limit = await AgenticLoopBudget.shared.consumeIteration()
            return await TokenTruncator.truncateResult(errorResult, maxTokens: limit)
        }

        // Fetch events in range
        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        // Build free slots
        var slots: [[String: Any]] = []
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        // Iterate day by day
        var dayCursor = rangeStart
        while dayCursor < rangeEnd && slots.count < maxSlotsCap {
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayCursor)!

            // Working hours for this day
            guard let workStartDate = cal.date(bySettingHour: workStart, minute: 0, second: 0, of: dayCursor),
                  let workEndDate = cal.date(bySettingHour: workEnd, minute: 0, second: 0, of: dayCursor) else {
                dayCursor = dayEnd
                continue
            }

            // Filter events that overlap this day's working hours
            let dayEvents = events.filter { event in
                event.startDate < workEndDate && event.endDate > workStartDate
            }

            // Find gaps between the events during working hours
            var gapStart = workStartDate
            for event in dayEvents {
                let eventStart = max(event.startDate, workStartDate)
                let eventEnd = min(event.endDate, workEndDate)

                // Gap before this event
                if gapStart < eventStart {
                    let gapMinutes = Int(eventStart.timeIntervalSince(gapStart) / 60)
                    if gapMinutes >= duration {
                        slots.append([
                            "date": dateFormatter.string(from: dayCursor),
                            "start": timeFormatter.string(from: gapStart),
                            "end": timeFormatter.string(from: eventStart),
                            "duration_min": gapMinutes,
                        ])
                        if slots.count >= maxSlotsCap { break }
                    }
                }

                gapStart = max(gapStart, eventEnd)
            }

            // Gap after last event until end of working hours
            if slots.count < maxSlotsCap, gapStart < workEndDate {
                let gapMinutes = Int(workEndDate.timeIntervalSince(gapStart) / 60)
                if gapMinutes >= duration {
                    slots.append([
                        "date": dateFormatter.string(from: dayCursor),
                        "start": timeFormatter.string(from: gapStart),
                        "end": timeFormatter.string(from: workEndDate),
                        "duration_min": gapMinutes,
                    ])
                }
            }

            dayCursor = dayEnd
        }

        let result: [String: Any] = [
            "slots": slots,
            "total_found": slots.count,
            "duration_minutes": duration,
            "search_start": dateFormatter.string(from: rangeStart),
            "search_end": dateFormatter.string(from: cal.date(byAdding: .day, value: -1, to: rangeEnd)!),
            "work_hours": "\(String(format: "%02d", workStart)):00–\(String(format: "%02d", workEnd)):00",
        ]

        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        let limit = await AgenticLoopBudget.shared.consumeIteration()
        return await TokenTruncator.truncateResult(result, maxTokens: limit)
    }
}
