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
    
    func createEvent(title: String, startDate: Date, duration: TimeInterval, notes: String? = nil) async throws {
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
    }
    
    func generateSmartSchedule(for goal: Goal, goals: [Goal] = []) async throws -> [ProposedEvent] {
        // AI-powered scheduling based on goal priority and user patterns
        let context = UserContextService.shared.buildContext(from: goals)

        do {
            let aiResponse = try await AIService.shared.generateCalendarEvents(for: goal, context: context)

            // Parse AI response and create proposed events
            var proposedEvents: [ProposedEvent] = []

            for event in aiResponse.events {
                let startDate = suggestOptimalTime(for: goal, timeSlot: event.suggestedTimeSlot)
                proposedEvents.append(ProposedEvent(
                    title: event.title,
                    startDate: startDate,
                    duration: TimeInterval(event.duration * 60), // Convert minutes to seconds
                    goalId: goal.id
                ))
            }

            return proposedEvents
        } catch {
            print("❌ AI scheduling failed, using fallback: \(error)")

            // Fallback: create a simple proposed event
            let startDate = suggestOptimalTime(for: goal)
            return [ProposedEvent(
                title: "Work on: \(goal.title)",
                startDate: startDate,
                duration: 3600, // 1 hour
                goalId: goal.id
            )]
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
    
    enum CalendarError: LocalizedError {
        case notAuthorized
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Calendar access not authorized"
            }
        }
    }
}

struct ProposedEvent {
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let goalId: UUID
}
