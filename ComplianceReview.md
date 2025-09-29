# YOU AND GOALS Architecture Compliance Review

This document evaluates the current codebase against the requirements outlined in **Building "YOU AND GOALS": The Complete iOS AI MVP Development Guide** and provides guidance on architectural direction for the chat/voice-first goal management experience.

## 1. High-level assessment

| Area | Status | Key findings |
| --- | --- | --- |
| Project structure & architecture | ❌ Not compliant | Single `Views/`, `Models/`, `Services/` folders. No feature modules or Clean Architecture layering, and `ContentView` directly orchestrates data, AI, and UI concerns. 【F:ContentView.swift†L11-L200】 |
| State management | ❌ Not compliant | Uses `ObservableObject` + `@StateObject` + `@Published`; does not adopt iOS 17 `@Observable` models as recommended. `VoiceService` and `UserContextService` both expose `@Published` properties. 【F:Services/VoiceService.swift†L13-L109】【F:Services/UserContextService.swift†L11-L101】 |
| Dependency injection | ❌ Not compliant | Relies on singletons (`AIService.shared`, `UserContextService.shared`) instead of Factory framework or testable DI. 【F:ContentView.swift†L26-L33】【F:Services/UserContextService.swift†L11-L78】 |
| SwiftData usage | ⚠️ Partially compliant | Models defined with `@Model`, but business logic lives outside the models (no embedded domain rules or async AI hooks). 【F:Models/Goal.swift†L11-L73】 |
| AI integration | ❌ Not compliant | Only integrates OpenAI via custom URLSession; no Apple Foundation Models fallback, no MacPaw/OpenAI client, no streaming, no GPT-4o usage, and no server-side proxy abstraction. 【F:Services/AIService.swift†L41-L155】 |
| Voice & Whisper strategy | ⚠️ Partially compliant | Uses on-device Speech framework only; lacks hybrid Whisper API + WhisperKit approach. 【F:Services/VoiceService.swift†L13-L109】 |
| Networking stack | ⚠️ Partially compliant | Custom URLSession implementation without Alamofire optimizations or retry policies aligned with guide. 【F:Services/AIService.swift†L94-L156】 |
| UI patterns | ⚠️ Partially compliant | Chat-to-card workflow represented, but optimistic updates, streaming UI, and modular card views per feature are not fully realized. 【F:ContentView.swift†L85-L200】 |
| Testing | ❌ Not compliant | Manual test harness instead of XCTest/Swift Testing with DI-friendly mocks. 【F:Tests/AIServiceTests.swift†L11-L149】 |
| Security & config | ❌ Not compliant | API key read from environment in-app; no `.xcconfig`, proxy, or obfuscation layers described in the guide. 【F:Services/AIService.swift†L41-L156】 |

## 2. Detailed gaps & recommendations

### 2.1 Architecture & project structure
- **Feature modules**: Restructure into `Features/GoalManagement`, `Features/AIConversation`, etc., each with dedicated view, view model (`@Observable`), and use-case layer. Current flat folders prevent scaling. 【F:ContentView.swift†L11-L200】
- **Clean separation**: Introduce `Domain/Services` interfaces and `Infrastructure` implementations. Presently, `ContentView` instantiates services directly and mixes UI with orchestration logic. 【F:ContentView.swift†L26-L200】

### 2.2 State management & DI
- Replace `ObservableObject` + `@Published` with `@Observable` models and value types for AI response state to improve performance as recommended.
- Adopt the Factory framework to register `AIService`, `CalendarService`, `UserContextService`, etc., with scoped lifetimes instead of static singletons. 【F:Services/UserContextService.swift†L11-L78】

### 2.3 SwiftData domain logic
- Embed domain behaviors inside `Goal` (e.g., methods to toggle activation, spawn subcards, trigger async AI breakdowns). Currently models are passive data containers. 【F:Models/Goal.swift†L11-L73】
- Create SwiftData-backed repositories in `Domain/Repositories` to decouple persistence from views.

### 2.4 AI platform strategy
- Primary engine should be Apple's on-device Foundation Models; add service wrapper that first attempts on-device inference before falling back to OpenAI.
- When using OpenAI, switch to GPT-4o via the MacPaw/OpenAI client, with response streaming and AsyncSequence consumption on the UI. Current implementation posts to `/chat/completions` with `gpt-4` and blocks until completion. 【F:Services/AIService.swift†L104-L156】
- Implement caching tiers (memory + disk) and fingerprinting per spec; present cache is an in-memory dictionary without TTL eviction. 【F:Services/AIService.swift†L41-L91】
- Introduce server-side proxy integration and remove direct API key handling on device. 【F:Services/AIService.swift†L45-L156】

### 2.5 Voice & multimodal features
- Layer in Whisper cloud API followed by WhisperKit fallback to satisfy hybrid requirement. Present speech handling is limited to SFSpeechRecognizer. 【F:Services/VoiceService.swift†L13-L109】
- Add streaming transcription support to align with real-time chat expectations.

### 2.6 UI and experience
- Implement optimistic card creation with rollback, AI typing indicators, and AsyncSequence-driven streaming updates in chat and card detail views.
- Separate general chat, card chat, and mirror mode into dedicated feature modules with navigation flows. Currently, `ContentView` coordinates everything via state flags. 【F:ContentView.swift†L16-L200】

### 2.7 Testing & monitoring
- Replace ad-hoc asserts with XCTest + Swift Testing suites, mocking AI services through Factory registrations. 【F:Tests/AIServiceTests.swift†L11-L149】
- Plan for AI metrics tracking (latency, accuracy, goal completion) with analytics hooks once infrastructure layers exist.

### 2.8 Security & deployment
- Externalize secrets via `.xcconfig` and proxy endpoints; avoid bundling API key usage directly in the client. 【F:Services/AIService.swift†L45-L156】
- Prepare staged rollout tooling and monitoring integrations as outlined in the guide.

## 3. Is this the best way to build YOU AND GOALS?

The current approach demonstrates the core interaction (chat input producing goal cards) but diverges from the recommended blueprint in critical areas:

1. **Scalability & maintainability risks** – Without feature modules and Clean Architecture boundaries, adding mirror mode behaviors, advanced analytics, or new AI flows will create tight coupling and hinder iteration speed.
2. **AI platform misalignment** – Prioritizing OpenAI without on-device Foundation Models conflicts with the privacy-first strategy and could introduce latency/cost issues once streaming conversations scale. 【F:Services/AIService.swift†L104-L156】
3. **State management overhead** – Legacy `ObservableObject` patterns may lead to redundant re-renders and make it harder to adopt SwiftUI data flow enhancements (e.g., observation macros, data-driven animations). 【F:Services/VoiceService.swift†L13-L109】
4. **Missing hybrid voice & streaming UX** – The guide emphasizes immediate, narrative feedback (typing indicators, progressive disclosure). Current synchronous request flow delays updates and weakens the conversational feel. 【F:ContentView.swift†L126-L200】

### Recommended path forward
- **Reboot around modules**: Create separate feature packages (`GoalManagementFeature`, `AIConversationFeature`, `MirrorModeFeature`) with `@Observable` view models exposing AsyncSequence-driven AI streams.
- **Adopt dual AI engines**: Build an abstraction that consults Foundation Models first and falls back to MacPaw/OpenAI for complex reasoning, with GPT-4o streaming as the cloud tier. Introduce caching, retry, and proxy layers per spec.
- **Empower SwiftData models**: Move card evolution logic (subcard breakdown, activation toggles triggering calendar scheduling) into methods on the `Goal` model or associated domain services, invoked from use cases.
- **Implement hybrid Whisper**: Start with Whisper API + server proxy, add WhisperKit offline support, and wire transcripts directly into the chat pipeline.
- **Upgrade testing & monitoring**: Shift to XCTest/Swift Testing, add dependency-injected mocks via Factory, and prepare instrumentation for AI performance metrics.

Following these changes will align the project with the researched blueprint and better support the ambitious AI-first card experience (including mirror mode) you described. Until then, the current implementation should be treated as a prototype rather than production-ready architecture.
