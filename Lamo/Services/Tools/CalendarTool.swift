import Foundation
import LiteRTLM
import EventKit

// MARK: - Calendar Tool

struct CalendarTool: Tool {
    static let name = ToolDefinitions.Calendar.name
    static let description = ToolDefinitions.Calendar.description

    @ToolParam(description: "'list' shows events in a date range, 'create' adds a new event (requires a title), 'search' finds events by keyword in title/notes/location.")
    var mode: String = "list"

    @ToolParam(description: "Date in YYYY-MM-DD format. For list: range start (default today). For create: the event day (default today).")
    var startDate: String?

    @ToolParam(description: "Date in YYYY-MM-DD format. For list: range end (default 7 days after start).")
    var endDate: String?

    @ToolParam(description: "Event title. Required for create.")
    var title: String?

    @ToolParam(description: "Event notes, for create.")
    var notes: String?

    @ToolParam(description: "Event location, for create.")
    var location: String?

    @ToolParam(description: "Start time HH:MM (24-hour), for create. When omitted, the event is all-day.")
    var startTime: String?

    @ToolParam(description: "End time HH:MM (24-hour), for create. Default: one hour after start.")
    var endTime: String?

    @ToolParam(description: "Keyword to find, for search.")
    var query: String?

    /// Cap on events returned per call — keeps context small; the hint tells the model how to get more.
    private static let maxEventsReturned = 30

    func run() async throws -> Any {
        var params: [String: Any] = ["mode": mode]
        if let sd = startDate { params["start_date"] = sd }
        if let ed = endDate { params["end_date"] = ed }
        if let t = title { params["title"] = t }
        if let n = notes { params["notes"] = n }
        if let l = location { params["location"] = l }
        if let st = startTime { params["start_time"] = st }
        if let et = endTime { params["end_time"] = et }
        if let q = query { params["query"] = q }
        let paramsDesc = ToolReportHelper.paramsJSONString(params)
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsDesc)

        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        // --- Fail fast on bad input BEFORE touching EventKit (avoids a pointless permission prompt) ---
        if let inputError = validateInputs() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: inputError)
            return inputError
        }

        let store = EKEventStore()

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }

        guard granted else {
            let result: [String: Any] = [
                "error": String(localized: "Calendar access denied."),
                "hint": "Ask the user to enable it in Settings > Privacy & Security > Calendars.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
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

    // MARK: - Validation

    /// Validates mode, dates, and times. Returns a model-actionable error dict, or nil when valid.
    /// Strict parsing: an unparseable explicit date must NEVER silently fall back to today —
    /// that would book events on the wrong day.
    private func validateInputs() -> [String: Any]? {
        guard ["list", "create", "search"].contains(mode) else {
            return [
                "error": String(localized: "Invalid mode: '\(mode)'"),
                "hint": "Use 'list', 'create', or 'search'.",
            ]
        }
        if mode == "create", title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return [
                "error": String(localized: "Missing event title."),
                "hint": "A title is required to create an event. Ask the user if you don't have one.",
            ]
        }
        if mode == "search", query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return [
                "error": String(localized: "Missing search keyword."),
                "hint": "Provide a keyword to search for in event titles, notes, and locations.",
            ]
        }
        for (label, value) in [("start", startDate), ("end", endDate)] {
            if let value, !value.isEmpty, !isValidDate(value) {
                return [
                    "error": String(localized: "Invalid \(label) date: '\(value)'"),
                    "hint": "Use YYYY-MM-DD format, e.g. 2026-08-15. Resolve relative dates against <current_time>.",
                ]
            }
        }
        for (label, value) in [("start", startTime), ("end", endTime)] {
            if let value, !value.isEmpty, parseTime(value, on: Date()) == nil {
                return [
                    "error": String(localized: "Invalid \(label) time: '\(value)'"),
                    "hint": "Use HH:MM 24-hour format, e.g. 09:30 or 18:00.",
                ]
            }
        }
        if let st = startTime, let et = endTime,
           let start = parseTime(st, on: Date()), let end = parseTime(et, on: Date()), end <= start {
            return [
                "error": String(localized: "End time '\(et)' is not after start time '\(st)'."),
                "hint": "The end time must be later than the start time on the same day.",
            ]
        }
        return nil
    }

    private func isValidDate(_ str: String) -> Bool {
        strictDateFormatter.date(from: str) != nil
    }

    // MARK: - Date Helpers

    /// Strict formatter — rejects "2026-13-45" and partial dates.
    private var strictDateFormatter: DateFormatter {
        let fmtr = DateFormatter()
        fmtr.locale = Locale(identifier: "en_US_POSIX")
        fmtr.dateFormat = "yyyy-MM-dd"
        fmtr.isLenient = false
        return fmtr
    }

    private func parseDate(_ str: String?, fallback: Date) -> Date {
        guard let str, !str.isEmpty else { return fallback }
        return strictDateFormatter.date(from: str) ?? fallback
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

        let capped = Array(events.prefix(Self.maxEventsReturned))
        let eventList = capped.map(eventDict)

        var result: [String: Any] = [
            "mode": "list",
            "start_date": strictDateFormatter.string(from: start),
            "end_date": strictDateFormatter.string(from: end),
            "returned": eventList.count,
            "events": eventList,
        ]
        if events.count > capped.count {
            result["total"] = events.count
            result["hint"] = "Showing the first \(capped.count) of \(events.count) events. Narrow the date range to see the rest."
        }

        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }

    // MARK: - Create

    private func handleCreate(store: EKEventStore) async throws -> Any {
        return await MainActor.run {
            let event = EKEvent(eventStore: store)
            event.title = title
            if let notes, !notes.isEmpty { event.notes = notes }
            if let location, !location.isEmpty { event.location = location }
            guard let targetCalendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first else {
                return [
                    "error": String(localized: "No calendar available."),
                    "hint": "Ask the user to create a calendar in the Calendar app first.",
                ]
            }
            event.calendar = targetCalendar

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
                return [
                    "status": "created",
                    "title": title ?? "",
                    "start": formatEventDate(event.startDate),
                    "end": formatEventDate(event.endDate),
                    "is_all_day": event.isAllDay,
                    "event_id": event.eventIdentifier ?? "",
                    "calendar": event.calendar?.title ?? targetCalendar.title,
                ]
            } catch {
                return [
                    "error": String(localized: "Failed to save the event: \(error.localizedDescription)"),
                    "hint": "Try again. If it keeps failing, ask the user to create the event manually.",
                ]
            }
        }
    }

    // MARK: - Search

    private func handleSearch(store: EKEventStore) async throws -> Any {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .year, value: -1, to: today) ?? today
        let end = cal.date(byAdding: .year, value: 1, to: today) ?? today

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let allEvents = store.events(matching: predicate)

        let lowerQuery = (query ?? "").lowercased()
        let matched = allEvents.filter { event in
            (event.title?.lowercased().contains(lowerQuery) ?? false) ||
            (event.notes?.lowercased().contains(lowerQuery) ?? false) ||
            (event.location?.lowercased().contains(lowerQuery) ?? false)
        }.sorted { $0.startDate < $1.startDate }

        let capped = Array(matched.prefix(Self.maxEventsReturned))
        let eventList = capped.map(eventDict)

        var result: [String: Any] = [
            "mode": "search",
            "query": query ?? "",
            "returned": eventList.count,
            "events": eventList,
        ]
        if matched.isEmpty {
            result["hint"] = "No events matched. Try a shorter or different keyword."
        } else if matched.count > capped.count {
            result["total"] = matched.count
            result["hint"] = "Showing the first \(capped.count) of \(matched.count) matches. Use a more specific keyword to narrow down."
        }

        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }

    // MARK: - Shared formatting

    private func eventDict(_ event: EKEvent) -> [String: Any] {
        [
            "title": event.title ?? "(No title)",
            "start": formatEventDate(event.startDate),
            "end": formatEventDate(event.endDate),
            "location": event.location ?? "",
            "calendar": event.calendar?.title ?? "",
            "is_all_day": event.isAllDay,
            "event_id": event.eventIdentifier ?? "",
        ]
    }
}
