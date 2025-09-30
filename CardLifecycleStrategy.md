# YOU AND GOALS Card Lifecycle Strategy Refresh

## Executive Summary
This refresh translates the updated product direction (lockable cards, selective regeneration, activation-driven calendar automation) into a cohesive architecture plan that aligns with the "Building YOU AND GOALS" blueprint and the current codebase realities. It reframes the experience around a modular feature stack powered primarily by Apple's on-device Foundation Models with OpenAI as a streaming fallback, ensuring privacy, resilience, and rapid iteration.

## Experience Pillars
1. **Conversational creation-first** – Users speak or type to spawn goals; the chat input remains docked at the top with voice parity, producing optimistic cards instantly before AI enriches them.
2. **Living cards with agency** – Cards can be locked (freeze snapshot), regenerated (ask AI for alternative framing), or activated (commit to execution, triggering calendar orchestration) without leaving the primary canvas.
3. **Dual narratives** – Human-facing cards live alongside Mirror Mode's AI-understood cards; the toggle reveals AI perspective without affecting real data.
4. **Background intelligence** – On-device AI handles quick reasoning, while fallback cloud calls stream richer insights. Caching, retry, and telemetry keep interactions smooth.

## Feature Flows
### 1. Goal Ingestion Flow
- **Input capture**: VoiceService streams transcription; ChatViewModel posts text to GoalCreationUseCase.
- **Optimistic card**: A provisional `GoalCard` appears with state `.draft` and spinner while AI enriches details.
- **Foundation-first AI**: `GoalAIOrchestrator` attempts on-device summarization + metadata; on failure, falls back to GPT-4o via MacPaw/OpenAI with AsyncSequence streaming.
- **SwiftData commit**: `Goal` model stores base fields plus `CardLifecycle` metadata (lock flags, activation timestamps).

### 2. Lock Card
- **Intent**: User taps lock icon or issues "Lock this card" command.
- **Behavior**:
  - `Goal.lock()` method (SwiftData model) flips `isLocked = true`, stores `lockedSnapshot` (title, description, AI rationale).
  - UI overlays lock badge; AI regeneration controls disable.
  - Mirror Mode receives read-only note that the card is frozen.
- **AI considerations**: On lock, AI stops pushing updates; caching persists the snapshot for offline viewing.

### 3. Regenerate Card
- **Intent**: User selects "Regenerate" action or says "Give me a different angle." Available only when `isLocked == false`.
- **Flow**:
  - `GoalRegenerationUseCase` passes existing context (subcards, progress) to AI.
  - AI returns alternative framing + optional new subtasks; UI shows side-by-side diff with accept/rollback.
  - Accepted changes update the `Goal` record and append to `GoalRevisionHistory` for audit.
  - Mirror Mode logs rationale changes to keep AI understanding consistent.

### 4. Activate Card → Calendar Events
- **Intent**: User taps "Activate" or issues voice command.
- **Behavior**:
  - `Goal.activate()` sets `activationState = .active` and timestamp.
  - `ActivationOrchestrator` generates structured tasks via Foundation Model; OpenAI fallback handles complex scheduling logic.
  - `CalendarService` (write-only EventKit access) creates or updates calendar items, respecting existing commitments and user preferences stored in context.
  - Activation pins the card to "Now" view and surfaces progress chips.
  - Deactivation removes pending calendar holds but preserves history.

### 5. Mirror Mode Synchronization
- Mirror cards ingest goal lifecycle changes (locked, regenerated, activated) through a unidirectional feed.
- Mirror UI remains read-only; it explains AI reasoning, what it locked onto, and pending actions.
- Provide per-card timeline showing regeneration attempts and activation outcomes.

## Architectural Realignment
1. **Feature Modules**
   - `Features/GoalManagement`: handles card lifecycle, SwiftData repositories, activation orchestration.
   - `Features/AIConversation`: manages chat UI, voice capture, streaming transcripts.
   - `Features/MirrorMode`: read-only projections.
   - Shared `Domain` layer exposes use-case protocols; `Infrastructure` implements AI, calendar, storage, analytics.
2. **Observation Model**
   - Adopt `@Observable` for view models (`GoalBoardViewModel`, `MirrorModeViewModel`) to leverage iOS 17 data flow.
   - Use value-type state slices per card to reduce re-render churn.
3. **Dependency Injection**
   - Register services with Factory (e.g., `Container.goalAIOrchestrator`, `Container.calendarService`). Scope AI engines per session to control resource usage and simplify testing.

## Data Model Enhancements
- Extend `Goal` SwiftData model:
  ```swift
  enum ActivationState: String, Codable { case draft, active, completed, archived }

  @Model final class Goal {
      @Attribute(.unique) var id: UUID
      var title: String
      var detail: String
      var activationState: ActivationState = .draft
      var isLocked: Bool = false
      var lockedSnapshot: GoalSnapshot?
      var lastRegeneratedAt: Date?
      var activatedAt: Date?
      var revisionHistory: [GoalRevision]
      // relationships: subgoals, mirror, events
  }
  ```
- Introduce supporting models (`GoalSnapshot`, `GoalRevision`, `ScheduledEventLink`).
- Business logic lives on the model (e.g., `func lock(with snapshot: GoalSnapshot)`, `func apply(regeneration:) async throws`).

## AI Orchestration Stack
- **Foundation Model primary**: Use Apple's 3B on-device model for summarization, quick breakdowns, and lock snapshots.
- **OpenAI GPT-4o fallback**: Stream responses via MacPaw/OpenAI `ChatStream`; capture tokens progressively and update UI.
- **Prompt patterns**:
  - Lock: "Produce immutable summary capturing [fields] so regenerations cannot override user-approved plan."
  - Regenerate: "Offer 2-3 new frames, respecting locked subtasks. Return JSON with accepted flag suggestions."
  - Activate: "Transform goal into time-blocked plan considering calendar availability JSON."
- **Caching**: Multi-tier caching (memory + disk) keyed by goal ID, lifecycle state, and prompt version. TTL per use case (e.g., 6 hours for lock snapshots, 15 minutes for activation suggestions).
- **Failure management**: Exponential backoff, offline queue for activation events, user alerts when fallback invoked.

## Calendar & EventKit Integration
- Use write-only access with background `BGAppRefreshTask` to reconcile scheduled events.
- Support both auto-generation and manual approval: when activation triggers events, present preview sheet for confirmation if user preference demands.
- Maintain `ScheduledEventLink` entries tying EventKit identifiers to goals for future updates or cancellations.
- Log activation outcomes for analytics (time from activation to completion, cancelation rates).

## Voice & Multimodal Layer
- Implement hybrid transcription: start with Whisper API streaming via server proxy, fallback to WhisperKit offline when network degraded.
- Align voice commands with lifecycle verbs ("lock", "regenerate", "activate", "archive").
- Provide haptic/audio feedback for lifecycle state changes.

## Testing & Observability
- Unit test lifecycle methods on `Goal` with Swift Testing; integration test flows via dependency-injected mocks.
- Simulate streaming AI responses to ensure UI handles partial data.
- Instrument analytics for:
  - Lock adoption rate
  - Regeneration frequency and acceptance
  - Activation-to-event conversion rate
  - AI fallback usage (Foundation vs OpenAI)
- Monitor model drift by comparing activation success metrics over time.

## Migration Path from Current Codebase
1. **Module extraction** – Move `ContentView` responsibilities into dedicated feature folders; introduce `GoalBoardViewModel` using `@Observable`.
2. **Model upgrade** – Migrate SwiftData schema to include lifecycle fields; provide lightweight migration for existing data.
3. **Service abstraction** – Replace singleton `AIService` with orchestrator protocol; implement Foundation + GPT-4o pipeline using Factory DI.
4. **Lifecycle UI** – Add lock/regenerate/activate controls to card view with optimistic UI states and error rollback.
5. **Calendar automation** – Build `ActivationOrchestrator` bridging AI output with `CalendarService`, ensuring confirmation options.
6. **Mirror sync** – Create read-only mirror repository fed by lifecycle events to keep AI perspective updated.
7. **Testing & telemetry** – Stand up Swift Testing targets and analytics scaffolding before scaling features.

Delivering this roadmap ensures the refreshed product vision—lockable, regenerable, activation-aware cards with dual narratives—rests on a scalable, privacy-conscious architecture that honours the research-backed MVP guidance.
