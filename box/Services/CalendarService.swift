//
//  CalendarService.swift
//  box
//
//  Created on 29.09.2025.
//

import EventKit
import SwiftUI
import Combine

@MainActor
class CalendarService: ObservableObject {
    struct ActivationPlan {
        let events: [ProposedEvent]
        let tips: [String]
    }

    private let eventStore = EKEventStore()
    @Published var isAuthorized = false
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Calendar access error: \(error)")
            return false
        }
    }

    func fetchExistingEvents(from startDate: Date, to endDate: Date) async throws -> [EKEvent] {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
    }

    func formatBusySlots(_ events: [EKEvent]) -> [String] {
        return events.map { event in
            let start = event.startDate.formatted(date: .abbreviated, time: .shortened)
            let end = event.endDate.formatted(date: .omitted, time: .shortened)
            return "\(start) - \(end): \(event.title ?? "Busy")"
        }
    }
    
    @discardableResult
    func createEvent(title: String, startDate: Date, duration: TimeInterval, notes: String? = nil) async throws -> String {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent)
        guard let identifier = event.eventIdentifier else {
            throw CalendarError.unknown
        }
        return identifier
    }
    
    func generateSmartSchedule(for goal: Goal, goals: [Goal] = []) async throws -> ActivationPlan {
        // Fetch existing events to avoid conflicts
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 14, to: startDate) ?? startDate
        let existingEvents = (try? await fetchExistingEvents(from: startDate, to: endDate)) ?? []
        let busySlots = formatBusySlots(existingEvents)

        // Build context with calendar data
        var context = await UserContextService.shared.buildContext(from: goals)
        context.existingCalendarEvents = busySlots

        do {
            let aiResponse = try await AIService.shared.generateCalendarEvents(
                for: goal,
                context: context,
                existingEvents: busySlots
            )

            // Parse AI response and create proposed events
            let proposedEvents: [ProposedEvent] = aiResponse.events.map { event in
                let startDate = suggestOptimalTime(for: goal, timeSlot: event.suggestedTimeSlot)
                return ProposedEvent(
                    title: event.title,
                    startDate: startDate,
                    duration: TimeInterval(event.duration * 60),
                    goalId: goal.id,
                    notes: event.description,
                    suggestedTimeSlot: event.suggestedTimeSlot,
                    preparation: event.preparation
                )
            }

            return ActivationPlan(
                events: proposedEvents,
                tips: aiResponse.schedulingTips ?? []
            )
        } catch {
            print("❌ AI scheduling failed, using fallback: \(error)")

            // Fallback: create a simple proposed event
            let startDate = suggestOptimalTime(for: goal)
            let fallbackEvent = ProposedEvent(
                title: "Work on: \(goal.title)",
                startDate: startDate,
                duration: 3600,
                goalId: goal.id,
                notes: "Auto-generated focus block",
                suggestedTimeSlot: nil,
                preparation: nil
            )

            return ActivationPlan(
                events: [fallbackEvent],
                tips: ["We scheduled a starter focus session. Adjust timing as needed."]
            )
        }
    }
    
    private func suggestOptimalTime(for goal: Goal, timeSlot: String? = nil) -> Date {
        let calendar = Calendar.current
        let now = Date()

        // Helper to guarantee the resulting date is in the future
        func futureDate(from date: Date) -> Date {
            if date > now { return date }
            return calendar.date(byAdding: .day, value: 1, to: date) ?? now.addingTimeInterval(86400)
        }

        if let timeSlot = timeSlot?.lowercased() {
            let targetHour: Int
            switch timeSlot {
            case "morning":
                targetHour = 9
            case "afternoon":
                targetHour = 14
            case "evening":
                targetHour = 18
            default:
                targetHour = 10
            }

            let components = DateComponents(hour: targetHour, minute: 0)
            if let nextMatch = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
                return nextMatch
            }

            let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
            var fallbackComponents = todayComponents
            fallbackComponents.hour = targetHour
            fallbackComponents.minute = 0
            let fallback = calendar.date(from: fallbackComponents) ?? now.addingTimeInterval(3600)
            return futureDate(from: fallback)
        }

        switch goal.priority {
        case .now:
            let minute = calendar.component(.minute, from: now)
            let minutesUntilNextHour = (60 - minute) % 60
            let base: Date
            if minutesUntilNextHour == 0 {
                base = calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
            } else {
                base = calendar.date(byAdding: .minute, value: minutesUntilNextHour, to: now) ?? now.addingTimeInterval(Double(minutesUntilNextHour) * 60)
            }
            let aligned = calendar.date(bySetting: .minute, value: 0, of: base) ?? base
            return futureDate(from: aligned)

        case .next:
            var components = DateComponents()
            components.hour = 9
            components.minute = 0
            var nextMorning = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
            if calendar.isDate(nextMorning, inSameDayAs: now) {
                nextMorning = calendar.date(byAdding: .day, value: 1, to: nextMorning) ?? nextMorning.addingTimeInterval(86400)
            }
            return futureDate(from: nextMorning)

        case .later:
            let base = calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86400)
            var components = calendar.dateComponents([.year, .month, .day], from: base)
            components.hour = 14
            components.minute = 0
            if let scheduled = calendar.date(from: components) {
                return futureDate(from: scheduled)
            }
        }

        // Fallback: two hours from now, aligned to the top of the hour
        let fallback = calendar.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        return calendar.date(bySetting: .minute, value: 0, of: fallback) ?? fallback
    }
    
    func deleteEvent(with identifier: String) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent)
        }
    }

    enum CalendarError: LocalizedError {
        case notAuthorized
        case unknown
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Calendar access not authorized"
            case .unknown:
                return "Unexpected calendar error"
            }
        }
    }
}

struct ProposedEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let goalId: UUID
    let notes: String?
    let suggestedTimeSlot: String?
    let preparation: [String]?

    init(
        title: String,
        startDate: Date,
        duration: TimeInterval,
        goalId: UUID,
        notes: String? = nil,
        suggestedTimeSlot: String? = nil,
        preparation: [String]? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.duration = duration
        self.goalId = goalId
        self.notes = notes
        self.suggestedTimeSlot = suggestedTimeSlot
        self.preparation = preparation
    }
}
