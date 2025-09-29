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
- Request minimal permissions
- Use write-only calendar access when possible
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
- [ ] API keys in Keychain (not in code)
- [ ] Privacy policy URL in Info.plist
- [ ] All permissions have usage descriptions
- [ ] Crash analytics configured
- [ ] Test on iPhone SE (smallest) and iPad Pro (largest)
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
- ❌ Don't store API keys in code
- ❌ Don't make Mirror Mode interactive
- ❌ Don't create complex navigation hierarchies
- ❌ Don't ignore voice input alternatives
- ❌ Don't process everything in AI (use local logic when possible)
- ❌ Don't create calendar events without user consent
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