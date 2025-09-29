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
        // AI-powered scheduling based on goal priority and user patterns
        let context = UserContextService.shared.buildContext(from: goals)

        do {
            let aiResponse = try await AIService.shared.generateCalendarEvents(for: goal, context: context)

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
        var components = calendar.dateComponents([.year, .month, .day], from: Date())

        // Use AI-suggested time slot if available
        if let timeSlot = timeSlot {
            switch timeSlot.lowercased() {
            case "morning":
                components.hour = 9
            case "afternoon":
                components.hour = 14
            case "evening":
                components.hour = 18
            default:
                components.hour = 10 // Default to mid-morning
            }
        } else {
            // Use priority-based scheduling
            switch goal.priority {
            case .now:
                // Schedule for next available hour
                components.hour = calendar.component(.hour, from: Date()) + 1
            case .next:
                // Schedule for tomorrow morning
                components.day! += 1
                components.hour = 9
            case .later:
                // Schedule for next week
                components.day! += 7
                components.hour = 14
            }
        }

        components.minute = 0
        return calendar.date(from: components) ?? Date()
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
