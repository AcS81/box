# Claude.md - YOU AND GOALS iOS App

## Project Overview

You are helping develop "YOU AND GOALS", an iOS app that revolutionizes goal management through conversational AI and intelligent card-based interfaces. This app has a **calendar mindset without a calendar UI** - instead using chat/voice + cards as the primary interaction model.

### Core Concept
- **No traditional calendar UI** - but intelligent calendar integration happens behind the scenes
- **Cards represent goals** that can regenerate, decompose, and evolve through AI
- **Every card has its own AI assistant** that users can chat with directly
- **Mirror Mode** shows how AI understands the user's goals (non-interactive, observational)

## Technical Context

### Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI only (no UIKit unless absolutely necessary)
- **Minimum iOS**: 17.0
- **Storage**: SwiftData (not Core Data)
- **AI**: OpenAI API (GPT-4 preferred)
- **Voice**: Speech Framework (not third-party)
- **Calendar**: EventKit

### Project Structure
```
YouAndGoals/
├── Models/        # SwiftData models
├── Views/         # SwiftUI views
├── Services/      # AI, Calendar, Voice services  
├── ViewModels/    # ObservableObject view models
└── Utilities/     # Extensions and helpers
```

## Key Principles When Coding

### 1. AI-First Design
- Every feature should consider how AI can enhance it
- Cards are living entities with AI capabilities, not static data
- AI responses should feel conversational, not robotic

### 2. Simplicity in UI
- Chat input stays at top, always visible
- Cards below in scrollable area
- Mirror mode toggle at bottom
- No complex navigation - single main view

### 3. Voice as Primary Input
- Voice should be as capable as text input
- Always provide voice alternative for any text action
- Natural language processing for all commands

### 4. Privacy-Conscious

- Process sensitive data locally when feasible
- Clear data handling explanations

## Code Style Guidelines

### SwiftUI Best Practices
```swift
// GOOD - Extracted subviews for clarity
struct GoalCardView: View {
    @ObservedObject var goal: Goal
    
    var body: some View {
        VStack {
            HeaderSection(goal: goal)
            ContentSection(goal: goal)
            ActionButtons(goal: goal)
        }
    }
}

// AVOID - Everything in one massive view
struct GoalCardView: View {
    var body: some View {
        VStack {
            // 200 lines of nested code
        }
    }
}
```

### Async/Await Pattern
```swift
// ALWAYS use modern concurrency
func processGoal() async throws {
    let response = try await AIService.shared.process(goal)
    await MainActor.run {
        updateUI(with: response)
    }
}

// AVOID completion handlers
func processGoal(completion: @escaping (Result<Response, Error>) -> Void) {
    // Don't use this pattern
}
```

### SwiftData Models
```swift
// ALWAYS use @Model macro
@Model
class Goal {
    var id = UUID()
    var title: String = ""
    
    // Use relationships properly
    @Relationship(deleteRule: .cascade) var subgoals: [Goal]?
    @Relationship(inverse: \Goal.subgoals) var parent: Goal?
}
```

## Common Tasks

### Adding a New Card Feature

1. **Update the Goal model** if needed
2. **Create/modify the AI prompt** in AIService
3. **Add UI in GoalCardView** 
4. **Test voice command** recognition
5. **Ensure Mirror Mode** reflects the change

Example:
```swift
// 1. In Goal.swift
var newProperty: String = ""

// 2. In AIService.swift  
case .newFeature(goal: Goal)
// Add to buildPrompt()

// 3. In GoalCardView.swift
Button("New Feature") {
    Task { await processNewFeature() }
}

// 4. Test: "Hey, [new feature] my goal"
// 5. Update MirrorModeView to show AI's understanding
```

### Implementing AI Conversations

Always structure AI interactions as:
1. User input (voice or text)
2. Parse intent
3. Generate contextual prompt
4. Process with AI
5. Update UI with response
6. Store in chat history

```swift
func handleCardChat(_ message: String, for goal: Goal) async {
    // 1. Store user message
    goal.chatHistory.append(ChatMessage(content: message, isUser: true))
    
    // 2. Determine intent
    let intent = parseIntent(from: message)
    
    // 3. Generate prompt with full context
    let prompt = buildContextualPrompt(intent: intent, goal: goal)
    
    // 4. Get AI response
    let response = try await AIService.shared.process(prompt)
    
    // 5. Update UI
    await MainActor.run {
        goal.chatHistory.append(ChatMessage(content: response, isUser: false))
        applyAIChanges(response, to: goal)
    }
}
```

### Calendar Integration

Always check permissions before calendar operations:
```swift
func scheduleGoal(_ goal: Goal) async {
    guard await CalendarService.shared.requestAccess() else {
        showPermissionAlert()
        return
    }
    
    // Generate smart events with AI
    let events = try await AIService.shared.generateEvents(for: goal)
    
    // Create calendar events
    for event in events {
        try await CalendarService.shared.create(event)
    }
}
```

## AI Prompt Engineering

### System Prompt Template
```swift
let systemPrompt = """
You are an AI assistant for YOU AND GOALS, a goal management app.

Core capabilities:
1. Create and decompose goals into actionable steps
2. Generate intelligent calendar events
3. Provide coaching and motivation
4. Analyze patterns and suggest improvements

Always respond in JSON when structural data is needed.
Be conversational and encouraging in chat responses.
Consider the user's context and previous goals.
"""
```

### Goal Parsing Rules
- Extract clear, measurable objectives
- Identify implicit timeframes
- Suggest relevant categories
- Determine initial priority (Now/Next/Later)
- Propose logical subtasks

### Calendar Event Generation
- Consider user's typical schedule patterns
- Avoid over-scheduling
- Include buffer time
- Suggest optimal time blocks based on goal type
- Respect work-life boundaries

## UI/UX Requirements

### Card States
1. **Collapsed**: Title, category, progress, active toggle
2. **Expanded**: + description, chat button, actions
3. **Chatting**: Full-screen chat interface
4. **Regenerating**: Loading state with animation

### Animations
```swift
// Standard animation duration
.animation(.easeInOut(duration: 0.3), value: property)

// Card interactions
.scaleEffect(isPressed ? 0.95 : 1.0)
.shadow(radius: isExpanded ? 4 : 2)
```

### Color Scheme
```swift
// Use semantic colors
Color(.systemBackground)    // Card backgrounds
Color(.label)               // Primary text
Color(.secondaryLabel)      // Secondary text
Color.accentColor          // Active states, CTAs
Color.blue.opacity(0.1)    // Mirror mode cards
```

## Mirror Mode Specifications

Mirror Mode is **observational only** - it shows AI's interpretation without user interaction:

```swift
struct MirrorModeView: View {
    // NO @State for user interactions
    // NO buttons or toggles
    // ONLY display AI's understanding
    
    var body: some View {
        // Read-only visualization of AI interpretation
        // Different visual style (blue tint, different layout)
        // Updates automatically based on user's real goals
    }
}
```

## Testing Considerations

### Always Test
1. **Voice input** in noisy environments
2. **Offline mode** - app should not crash without internet
3. **Empty states** - no goals, no internet, no permissions
4. **Dark mode** appearance
5. **Dynamic Type** sizing
6. **VoiceOver** accessibility

### Common Edge Cases
```swift
// Always handle these scenarios:
- Empty or null AI responses
- Network timeouts (use 30-second timeout)
- Malformed JSON from AI
- Calendar permission denied
- Speech recognition unavailable
- User interrupts voice recording
- Duplicate goal creation
- Circular goal relationships
```

## Performance Guidelines

### Optimization Rules
1. **Lazy load** AI responses - don't process until needed
2. **Cache** frequently accessed data in memory
3. **Batch** calendar operations
4. **Debounce** voice input processing
5. **Use .task** for async view operations

```swift
struct GoalListView: View {
    var body: some View {
        LazyVStack {  // Use Lazy containers
            ForEach(goals) { goal in
                GoalCardView(goal: goal)
                    .task {  // Load async data
                        await loadAIInsights(for: goal)
                    }
            }
        }
    }
}
```

## Debugging Helpers

### Useful Debug Extensions
```swift
#if DEBUG
extension Goal {
    static var preview: Goal {
        let goal = Goal(title: "Sample Goal")
        goal.description = "This is a test goal"
        goal.progress = 0.45
        return goal
    }
}
#endif
```

### Console Logging
```swift
// Use structured logging
print("🎯 Goal created: \(goal.title)")
print("🤖 AI response: \(response)")
print("📅 Calendar event: \(event)")
print("❌ Error: \(error.localizedDescription)")
```

## API Integration Notes

### OpenAI API
- **Model**: Use `gpt-4` for complex reasoning, `gpt-3.5-turbo` for simple tasks
- **Temperature**: 0.7 for creative responses, 0.3 for structured data
- **Max tokens**: 1000 for goal generation, 2000 for complex breakdowns
- **Rate limiting**: Implement 60-second cache for identical requests

### Error Handling
```swift
enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case rateLimited
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API key not configured"
        case .invalidResponse: return "Unable to process AI response"
        case .rateLimited: return "Too many requests. Please wait."
        case .networkError: return "Check your internet connection"
        }
    }
}
```

## Deployment Checklist

Before any release:

- [ ] All permissions have usage descriptions
- [ ] Crash analytics configured
- [ ] VoiceOver fully functional
- [ ] No force unwraps in production code
- [ ] All AI prompts tested for inappropriate content

## Common Commands for Development

When asked to implement features, follow this pattern:

1. **"Add [feature] to goal cards"**
   - Update Goal model
   - Modify GoalCardView
   - Add AI processing
   - Update Mirror Mode

2. **"Make cards do [action]"**
   - Add to card's action buttons
   - Create AI prompt
   - Implement async processing
   - Show loading state

3. **"Fix [issue]"**
   - Check error handling first
   - Verify AI response parsing
   - Ensure proper async/await
   - Test edge cases

4. **"Improve [aspect]"**
   - Consider AI enhancement first
   - Ensure voice compatibility
   - Maintain simplicity
   - Test on all device sizes

## Important Constraints

### Never Do This
- ❌ Don't use UIKit unless absolutely necessary
- ❌ Don't make Mirror Mode interactive
- ❌ Don't create complex navigation hierarchies
- ❌ Don't ignore voice input alternatives
- ❌ Don't use completion handlers (use async/await)

### Always Do This
- ✅ Keep chat input always visible at top
- ✅ Make every text action available via voice
- ✅ Show loading states for AI operations
- ✅ Handle offline mode gracefully
- ✅ Test with VoiceOver enabled
- ✅ Use semantic colors for dark mode support
- ✅ Cache AI responses when appropriate
- ✅ Validate AI JSON responses before parsing

## Quick Reference

### File Naming
- Views: `GoalCardView.swift`, `MirrorModeView.swift`
- Models: `Goal.swift`, `AIMirrorCard.swift`
- Services: `AIService.swift`, `CalendarService.swift`
- View Models: `GoalViewModel.swift`, `ChatViewModel.swift`

### Key Functions
```swift
// Creating goals
createGoalFromInput(_ input: String) async

// AI processing
AIService.shared.processRequest(_ function: AIFunction) async

// Calendar integration  
CalendarService.shared.createEvent(for: Goal) async

// Voice processing
VoiceService.startRecording() async
```

### State Management
- Use `@StateObject` for view models
- Use `@ObservedObject` for passed models
- Use `@State` for local UI state
- Use `@Environment` for model container

## Support Resources

When implementing features, refer to:
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [EventKit Documentation](https://developer.apple.com/documentation/eventkit)
- [Speech Framework](https://developer.apple.com/documentation/speech)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)

---

**Remember**: This app is about making goal management feel like having a conversation with a smart friend, not filling out forms in a task manager. Every interaction should feel natural, intelligent, and helpful.

# Claude.md — YOU AND GOALS iOS App

> **Purpose**: Give Claude Code one authoritative brief for how to work on this repository—architecture, constraints, conventions, and high‑leverage workflows. Claude should treat this as the project’s operating manual.

---

## 0) How Claude should operate on this repo

**Primary role**: senior iOS/AI engineer and pragmatic product partner for the "YOU AND GOALS" app.

**When making changes**

* Prefer minimal, well‑scoped pull requests. Group changes by feature.
* Propose file additions/edits as a unified diff per file. Include new file paths.
* Include tests, docs, and migration notes with each significant change.
* Add a short *Why/Intent* note at the top of each PR.
* If ambiguity exists, make a sensible decision and document the trade‑off.

**Completion checklist for any change**

* [ ] Code builds locally for iOS 17+.
* [ ] Unit tests written/updated and passing (XCTest).
* [ ] Accessibility verified (Dynamic Type, VoiceOver labels, 44pt targets).
* [ ] Performance considerations noted (rendering, allocations, background work).
* [ ] Privacy impact assessed; sensitive processing kept on-device when possible.

**Style**

* Swift 5.9+, SwiftUI-first, async/await, Sendable where appropriate.
* Use SwiftFormat/SwiftLint rules in this file (see Appendix) and keep code idiomatic.
* Keep public APIs small, prefer internal over public.

---

## 1) Executive summary (for fast onboarding)

"YOU AND GOALS" is a conversational goal management app: *calendar mindset without calendar UI*. It combines AI goal decomposition with intelligent scheduling and an approachable, card‑based interface. Core pillars: privacy‑first, offline‑first, progressive disclosure, and real‑time collaboration.

**Key innovation**: AI "mirror mode" + card assistants—AI maintains a parallel, privacy‑respecting understanding of user goals and habits, driving context‑aware guidance without exposing sensitive data to the cloud.

---

## 2) Target platform & constraints

* **iOS**: 17+ (SwiftUI, SwiftData, Observation, Charts as needed)
* **Architecture**: Hybrid Cloud–Edge AI (OpenAI/Claude API in cloud; Core ML on device)
* **Privacy**: Default to on‑device analysis; minimize remote PII. Progressive permissions.
* **Offline‑first**: App works without network; sync when online. Conflict resolution handled.
* **Real‑time**: WebSockets for live sync of cards and mirror insights.

---

## 3) Project structure (proposed)

```
YouAndGoals/
  App/
    YouAndGoalsApp.swift
    AppDelegate.swift
    Environment/
      AppConfig.swift
      Secrets.example.xcconfig
  Core/
    DesignSystem/
      Colors.swift
      Typography.swift
      Components/
    Persistence/
      Models/ (SwiftData)
      Migrations/
      Storage.swift
    Networking/
      HTTPClient.swift
      WebSocketClient.swift
    AI/
      Orchestrator/
      Agents/
      Providers/
      MirrorMode/
    Calendar/
      EventKit/
    Voice/
      Speech/
  Features/
    Goals/
      Views/
      ViewModels/
      UseCases/
    Scheduling/
    Insights/
    Onboarding/
  Tests/
    Unit/
    Snapshot/
  Tools/
    Scripts/
```

> **Modules**: Prefer feature‑first folders with Core providing shared foundations (Networking, Persistence, AI, DesignSystem).

---

## 4) Core data models (SwiftData)

```swift
@Model
final class Goal: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var progress: Double = 0
    var isActive: Bool = true
    var createdAt: Date = .now
    var targetDate: Date?

    @Relationship(.cascade) var milestones: [Milestone] = []
    @Relationship(.cascade) var aiInsights: [AIInsight] = []
    @Relationship(inverse: \Goal.parent) var subcards: [Goal] = []
    @Relationship var parent: Goal?
    @Relationship var aiMirrorCard: AIMirrorCard?
}

@Model
final class Milestone: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var scheduledDate: Date
    var estimatedDurationHours: Int
    var status: String // planned, in_progress, done
    @Relationship var goal: Goal?
}

@Model
final class AIMirrorCard: Identifiable {
    @Attribute(.unique) var id: UUID
    var sourceGoalID: UUID
    var aiUnderstanding: String
    var recommendations: [String] = []
    var emotionalState: String?
    var lastAnalyzed: Date = .now
    @Relationship(inverse: \Goal.aiMirrorCard) var sourceGoal: Goal?
}

@Model
final class AIInsight: Identifiable {
    @Attribute(.unique) var id: UUID
    var summary: String
    var createdAt: Date = .now
    var tags: [String] = []
    @Relationship var goal: Goal?
}
```

**Notes**

* Keep migrations additive. Use lightweight migrations where possible.
* Derive computed fields (e.g., urgency) in ViewModels to avoid redundant storage.

---

## 5) Calendar integration (EventKit)

**Permissions**

* Prefer **write‑only** access for automated scheduling.
* Request **read** access only when user explicitly views calendar context.
* Gate permission prompts by feature usage (progressive disclosure).

**API sketch**

```swift
final class GoalCalendarManager {
    private let store = EKEventStore()

    func schedule(_ milestone: Milestone, for goal: Goal) async throws {
        guard try await store.requestWriteOnlyAccessToEvents() else { return }
        let event = EKEvent(eventStore: store)
        event.title = "Focus: \(milestone.title)"
        event.startDate = milestone.scheduledDate
        event.endDate = Calendar.current.date(byAdding: .hour,
                                              value: milestone.estimatedDurationHours,
                                              to: milestone.scheduledDate)!
        event.calendar = store.defaultCalendarForNewEvents
        event.notes = "YOU AND GOALS — \(goal.title)"
        try store.save(event, span: .thisEvent)
    }
}
```

---

## 6) Voice & chat interface

**Speech**: SFSpeechRecognizer + AVAudioEngine with on‑device recognition when available.

```swift
@MainActor
final class VoiceGoalManager: ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    @Published var isListening = false

    func start() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // configure audio session & tap buffer ...
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let text = result?.bestTranscription.formattedString { self?.handle(text) }
        }
        isListening = true
    }

    private func handle(_ utterance: String) {
        // route to NLP/intent pipeline
    }
}
```

**NLP**

* Lightweight on‑device intent patterns for common commands.
* Cloud LLM (OpenAI/Claude API) for complex decomposition with *context‑aware prompting*.
* Use Tree‑/Graph‑of‑Thought style prompting for multi‑step plans.

---

## 7) AI architecture

**Agents**

* **Conductor** (cloud): orchestrates parse → decompose → schedule → mirror.
* **Goal Parser** (cloud/local): extracts entities, constraints, dates.
* **Task Decomposer** (cloud): produces milestones using utility‑cost heuristics.
* **Calendar Agent** (cloud/local): multi‑constraint scheduling.
* **Mirror Mode** (on‑device Core ML): pattern/behavior analysis, privacy‑first.

**Conductor sketch (pseudo‑Python)**

```python
class GoalConductor:
    def process_goal(self, text, ctx):
        g = parse_goal(text, ctx)
        tasks = decompose(g)
        schedule = schedule_tasks(tasks, ctx)
        mirror = mirror_analyze(g)
        return {"goal": g, "tasks": tasks, "schedule": schedule, "mirror": mirror}
```

**Mirror mode (on‑device)**

```swift
struct MirrorInsights { let motivation: Double; let success: Double; let suggestions: [String]; let mood: String? }

final class MirrorModeProcessor {
    private let model: MLModel
    init(model: MLModel) { self.model = model }

    func analyze(_ activity: UserActivity) throws -> MirrorInsights {
        let pred = try model.prediction(from: activity.features)
        return .init(motivation: pred["motivation"] as! Double,
                     success: pred["success_likelihood"] as! Double,
                     suggestions: pred["suggestions"] as! [String],
                     mood: pred["mood"] as? String)
    }
}
```

**Cloud vs edge**

* On‑device: personal metrics, pattern detection, mood; cache locally.
* Cloud: heavy reasoning, summarization, long‑context planning. Use cost caps, batching, and caching.

---

## 8) Sync & offline

**Approach**

* Local‑first writes (SwiftData/SQLite). Queue mutations.
* Background sync via WebSockets + HTTP retry.
* Conflicts: last‑write‑wins by default; present human‑readable diffs when ambiguous.

**Client sync skeleton (TS)**

```ts
class SyncManager {
  private queue: Change[] = []
  private socket: WebSocket
  constructor(socket: WebSocket) { this.socket = socket }
  async applyLocal(change: Change) { this.queue.push(change); /* persist */ this.flushIfOnline() }
  async flushIfOnline() { /* transmit, ack, reconcile */ }
}
```

---

## 9) UI/UX design system

**Cards**

* Min size: 180×162; 2–4px elevation hover; 200–300ms ease‑out transitions.
* Progressive disclosure: tap to expand advanced controls.

```swift
struct GoalCard: View {
    let goal: Goal
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(goal.title).font(.headline).lineLimit(2)
            ProgressView(value: goal.progress/100)
            if expanded { AdvancedGoalOptionsView(goal: goal).transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() } }
        .accessibilityAddTraits(.isButton)
    }
}
```

**View modes**

* **Now**: high‑contrast, immediate CTAs.
* **Next**: medium priority, preview w/ scheduling.
* **Later**: subdued, planning tools.

**Accessibility**: VoiceOver labels, Dynamic Type, sufficient contrast, 44pt targets.

---

## 10) Performance

* Prefer value types and small Views; avoid heavy work in `body`.
* Use `.animation(_:value:)` for state-driven motion; avoid implicit animations on frequent updates.
* Cache AI responses and mirror insights; throttle background analyses.
* Quantize Core ML models; lazy‑load models by context.

```swift
struct OptimizedGoalCard: View {
    let goal: Goal
    var body: some View {
        VStack {
            Text(goal.title).font(.headline).lineLimit(2)
            ProgressView(value: goal.progress/100)
        }
        .drawingGroup() // rasterize complex layers
    }
}
```

---

## 11) Security & privacy

* Differential privacy where aggregated telemetry is necessary.
* Data minimization + local‑only sensitive analysis.
* Use Keychain for tokens; store API keys in `.xcconfig` (never hard‑code).
* GDPR: export/delete endpoints; clear consent flows; privacy nutrition labels.
* Scheduled security reviews; threat modeling per major feature.

---

## 12) Pricing & product

* **Freemium**: basic goals, simple voice, up to 10 active goals.
* **Premium ($9.99/mo)**: unlimited, advanced AI coaching, calendar automation.
* **Annual ($89.99/yr)**; **Family ($19.99/mo)** up to 6 users.

**Positioning**: conversational, goal‑centric, privacy‑first—distinct from Notion AI, Things 3, Any.do, Fantastical.

---

## 13) Roadmap (Weeks)

**Phase 1 (1–4)**: SwiftUI shell, SwiftData models, basic voice, simple cloud parsing; App Store prep.

**Phase 2 (5–8)**: Multi‑agent AI, Core ML, mirror cards, EventKit auto‑scheduling, real‑time sync.

**Phase 3 (9–12)**: Contextual conversations, advanced views/filters, perf & a11y, analytics.

**Phase 4 (13–16)**: Hardening, privacy/security upgrades, enterprise/API considerations.

---

## 14) KPIs

* Engagement: daily active goals, voice freq/success, AI acceptance, completion & time‑to‑complete.
* Technical: LLM latency, sync success, conflict rate, crash‑free sessions, calendar write success.
* Business: conversion to Premium, MRR, 7/30/90‑day retention, NPS.

---

## 15) Claude task templates

**Feature task**

```
Goal: <one‑line outcome>
Context: <user problem, constraints>
Acceptance Criteria:
- [ ] <functional slice 1>
- [ ] <a11y/perf/privacy checks>
- [ ] Tests & docs included
Out of scope: <explicit>
```

**Commit message (Conventional Commits)**

```
feat(goals): add mirror mode analyzer for motivation heuristics

- implement on‑device Core ML pipeline
- wire insights to Goal detail
- add tests for thresholds
```

**PR description**

```
### Why
<user value + hypothesis>

### What
- bullets of changes

### How to test
- steps, seed data, screenshots (a11y on)

### Risks / roll‑out
- flags, metrics, rollback plan
```

---

## 16) Prompts (internal to orchestrator)

**Task Decomposer (cloud)**

```
Decompose this goal into 3–7 milestones. Optimize for user momentum and minimal context switches. Each milestone should have: title, est_hours, dependencies, success_criteria, and a default scheduling window within the next 4 weeks.
```

**Calendar Agent**

```
Given milestones, user calendar constraints, energy patterns (morning/evening), and do-not-disturb windows, produce event candidates. Respect commute buffers and breaks. Prefer 60–90 min focus blocks.
```

**Mirror Mode Summarizer (local first)**

```
Summarize weekly progress with motivational tone; surface 1–2 small wins; suggest one friction removal.
```

---

## 17) Networking & config

* Use `URLSession` with modern concurrency. Exponential backoff + jitter.
* `.xcconfig` for environments: `API_BASE_URL`, `WS_URL`, `LLM_PROVIDER`, `LLM_API_KEY`.
* Feature flags via remote config (fallback to local JSON).

---

## 18) Testing

* XCTest for units; Dependency injection to mock AI and Calendar.
* Snapshot tests for critical views at multiple Dynamic Type sizes.
* Integration tests for voice intent parsing and EventKit writes (behind fakes on CI).

---

## 19) Appendix — SwiftFormat/SwiftLint sketch

**SwiftFormat**

* maxwidth: 120
* wraparguments: before-first
* decimalgrouping: 3,2

**SwiftLint rules (selected)**

* opt_in: `closure_spacing`, `explicit_acl`, `file_length`, `force_unwrapping` (warning)
* disabled: `identifier_name` (allow short `id`), `line_length` (warn at 130)

---

## 20) Non‑negotiables

1. Simplicity beats completeness; progressive disclosure always.
2. Privacy by default; on‑device first; minimum data collection.
3. Small, steady iterations with measurable user impact.
4. Ship quality: tests, a11y, performance, and rollback plan.
