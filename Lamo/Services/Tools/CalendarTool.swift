import Foundation
import LiteRTLM
import EventKit

// MARK: - Helpers

private func report(_ name: String, params: String) async {
    await ToolCallReporter.shared.reportCall(name: name, params: params)
}
private func reportResult(_ name: String, _ result: Any) async {
    await ToolCallReporter.shared.reportResult(name: name, result: result)
}

// MARK: - Calendar Tool

struct CalendarTool: Tool {
    static let name = "calendar"
    static let description = "List, create, or search calendar events."

    @ToolParam(description: "Operation: list, create, or search.")
    var mode: String = "list"

    @ToolParam(description: "Start date YYYY-MM-DD, default today.")
    var startDate: String?

    @ToolParam(description: "End date YYYY-MM-DD, default +7 days.")
    var endDate: String?

    @ToolParam(description: "Event title, required for create.")
    var title: String?

    @ToolParam(description: "Event notes for create mode.")
    var notes: String?

    @ToolParam(description: "Event location for create mode.")
    var location: String?

    @ToolParam(description: "Start time HH:MM, for create mode.")
    var startTime: String?

    @ToolParam(description: "End time HH:MM, for create mode.")
    var endTime: String?

    @ToolParam(description: "Search query for search mode.")
    var query: String?

    func run() async throws -> Any {
        var paramsDesc = "{\"mode\": \"\(mode)\""
        if let sd = startDate { paramsDesc += ", \"start_date\": \"\(sd)\"" }
        if let ed = endDate { paramsDesc += ", \"end_date\": \"\(ed)\"" }
        if let t = title { paramsDesc += ", \"title\": \"\(t)\"" }
        if let n = notes { paramsDesc += ", \"notes\": \"\(n)\"" }
        if let l = location { paramsDesc += ", \"location\": \"\(l)\"" }
        if let st = startTime { paramsDesc += ", \"start_time\": \"\(st)\"" }
        if let et = endTime { paramsDesc += ", \"end_time\": \"\(et)\"" }
        if let q = query { paramsDesc += ", \"query\": \"\(q)\"" }
        paramsDesc += "}"
        await report(Self.name, params: paramsDesc)

        let store = EKEventStore()

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }

        guard granted else {
            let result: [String: Any] = ["error": "Calendar access denied. Enable in Settings > Privacy > Calendars."]
            await reportResult(Self.name, result)
            return result
        }

        switch mode {
        case "create":
            return try await handleCreate(store: store)
        case "search":
            return try await handleSearch(store: store)
        default:
            return try await handleList(store: store)
        }
    }

    // MARK: - Date Helpers

    private var dateFormatter: DateFormatter {
        let fmtr = DateFormatter()
        fmtr.locale = Locale(identifier: "en_US_POSIX")
        fmtr.dateFormat = "yyyy-MM-dd"
        return fmtr
    }

    private func parseDate(_ str: String?, fallback: Date) -> Date {
        guard let str, !str.isEmpty else { return fallback }
        return dateFormatter.date(from: str) ?? fallback
    }

    private func parseTime(_ str: String?, on date: Date) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let parts = str.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private func formatEventDate(_ date: Date) -> String {
        let fmtr = DateFormatter()
        fmtr.locale = Locale(identifier: "en_US_POSIX")
        fmtr.dateFormat = "yyyy-MM-dd HH:mm"
        return fmtr.string(from: date)
    }

    // MARK: - List

    private func handleList(store: EKEventStore) async throws -> Any {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: parseDate(startDate, fallback: today))
        let defaultEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let end = cal.startOfDay(for: parseDate(endDate, fallback: defaultEnd))
        // Include events starting on end_date by extending one day (predicate end is exclusive)
        let predicateEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end

        let predicate = store.predicateForEvents(withStart: start, end: predicateEnd, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let eventList: [[String: Any]] = events.map { event in
            [
                "title": event.title ?? "(No title)",
                "start": formatEventDate(event.startDate),
                "end": formatEventDate(event.endDate),
                "location": event.location as Any,
                "calendar": event.calendar.title,
                "is_all_day": event.isAllDay,
                "event_id": event.eventIdentifier ?? "",
            ]
        }

        let result: [String: Any] = [
            "mode": "list",
            "start_date": dateFormatter.string(from: start),
            "end_date": dateFormatter.string(from: end),
            "count": eventList.count,
            "events": eventList,
        ]

        let limit = await AgenticLoopBudget.shared.consumeIteration()
        let truncated = await TokenTruncator.truncateResult(result, maxTokens: limit)
        await reportResult(Self.name, truncated)
        return truncated
    }

    // MARK: - Create

    private func handleCreate(store: EKEventStore) async throws -> Any {
        guard let title, !title.isEmpty else {
            let result: [String: Any] = ["error": "Title is required for 'create' mode."]
            await reportResult(Self.name, result)
            return result
        }

        return await MainActor.run {
            let event = EKEvent(eventStore: store)
            event.title = title
            if let notes, !notes.isEmpty { event.notes = notes }
            if let location, !location.isEmpty { event.location = location }
            event.calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let eventDate = parseDate(startDate, fallback: today)

            if let st = startTime, let parsedStart = parseTime(st, on: eventDate) {
                event.startDate = parsedStart
                if let et = endTime, let parsedEnd = parseTime(et, on: eventDate) {
                    event.endDate = parsedEnd
                } else {
                    event.endDate = cal.date(byAdding: .hour, value: 1, to: parsedStart) ?? parsedStart
                }
                event.isAllDay = false
            } else {
                event.startDate = eventDate
                event.endDate = cal.date(byAdding: .day, value: 1, to: eventDate) ?? eventDate
                event.isAllDay = true
            }

            let alarm = EKAlarm(relativeOffset: -15 * 60)
            event.addAlarm(alarm)

            do {
                try store.save(event, span: .thisEvent, commit: true)
                let result: [String: Any] = [
                    "status": "created",
                    "title": title,
                    "start": formatEventDate(event.startDate),
                    "end": formatEventDate(event.endDate),
                    "is_all_day": event.isAllDay,
                    "event_id": event.eventIdentifier ?? "",
                    "calendar": event.calendar.title,
                ]
                return result
            } catch {
                return ["error": "Failed to save event: \(error.localizedDescription)"]
            }
        }
    }

    // MARK: - Search

    private func handleSearch(store: EKEventStore) async throws -> Any {
        guard let query, !query.isEmpty else {
            let result: [String: Any] = ["error": "Query is required for 'search' mode."]
            await reportResult(Self.name, result)
            return result
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .year, value: -1, to: today) ?? today
        let end = cal.date(byAdding: .year, value: 1, to: today) ?? today

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let allEvents = store.events(matching: predicate)

        let lowerQuery = query.lowercased()
        let matched = allEvents.filter { event in
            (event.title?.lowercased().contains(lowerQuery) ?? false) ||
            (event.notes?.lowercased().contains(lowerQuery) ?? false) ||
            (event.location?.lowercased().contains(lowerQuery) ?? false)
        }.sorted { $0.startDate < $1.startDate }

        let eventList: [[String: Any]] = matched.map { event in
            [
                "title": event.title ?? "(No title)",
                "start": formatEventDate(event.startDate),
                "end": formatEventDate(event.endDate),
                "location": event.location as Any,
                "calendar": event.calendar.title,
                "is_all_day": event.isAllDay,
                "event_id": event.eventIdentifier ?? "",
            ]
        }

        let result: [String: Any] = [
            "mode": "search",
            "query": query,
            "count": eventList.count,
            "events": eventList,
        ]

        let limit = await AgenticLoopBudget.shared.consumeIteration()
        let truncated = await TokenTruncator.truncateResult(result, maxTokens: limit)
        await reportResult(Self.name, truncated)
        return truncated
    }
}
