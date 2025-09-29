# MVP Milestones

## North Star
- Deliver a market-leading, AI-native goal manager that feels like conversational productivity and surpasses legacy task apps.
- Ship on-device first intelligence with trustworthy privacy, Liquid Glass-grade UI polish, and voice + chat parity.
- Measure success by daily active goals, AI adoption, calendar conversion, and <1s perceived latency during chat.

## Baseline Snapshot (2025-09-29)
- Chat-first shell with voice capture, goal cards, and mirror toggle already live.
- AIService provides contextual goal creation + mirror summaries via OpenAI only.
- Missing card lifecycle controls, modular architecture, on-device AI, calendar automation, hardening.

## Milestone 1 – Structural Reset (Weeks 1-2)
- Restructure project into Feature + Core modules; adopt Factory DI and @Observable view models.
- Upgrade SwiftData models with lifecycle fields (lock, activate, revisions) and embed domain methods.
- Externalize secrets via xcconfig, wire remote config scaffold, ensure clean build + unit smoke tests.
- Exit criteria: `xcodebuild` succeeds, SwiftLint clean, Feature modules compiling with previews intact.

## Milestone 2 – Dual-AI Orchestrator (Weeks 3-4)
- Implement Foundation Model primary path with GPT-4o streaming fallback through MacPaw client + proxy.
- Add caching tiers, retry policy, structured logging, and analytics hooks for latency + adoption.
- Expose streaming updates in chat + card UI using AsyncSequence, optimistic renders, typing indicators.
- Exit criteria: AI flows run offline-first with fallback, telemetry logging, integration tests covering JSON parsing.

## Milestone 3 – Card Agency & Calendar Engine (Weeks 5-6)
- Ship lock/regenerate/activate flows with Liquid Glass visuals, haptics, and chat verbs.
- Build ActivationOrchestrator bridging AI output to EventKit write-only scheduling with confirmation sheet.
- Introduce revision history, mirror sync feed, and Now/Next/Later automation.
- Exit criteria: user can lock, regenerate, activate goals; calendar events created or declined gracefully; mirror mode reflects lifecycle.

## Milestone 4 – Voice & Multimodal Mastery (Weeks 7-8)
- Layer Whisper cloud + WhisperKit offline transcription, streaming utterances into general/card chats.
- Add intent detection for lifecycle commands and general chat orchestration.
- Provide accessibility parity (VoiceOver labels, Dynamic Type) and latency budget instrumentation.
- Exit criteria: voice commands drive full lifecycle, a11y audit passes, logs show sub-1s perceived response.

## Milestone 5 – Hardening & Launch Readiness (Weeks 9-10)
- Expand test suite (unit, snapshot, async stress), add crash + analytics monitoring, finalize privacy copy.
- Perform performance profiling, memory tuning, offline/edge-case sweeps, dark-mode + dynamic type QA.
- Prepare beta rollout assets, App Store metadata, support scripts, and go/no-go checklist.
- Exit criteria: test suite green, build uploads without warnings, pilot metrics aligned with North Star goals.

## Ongoing KPIs & Guardrails
- Daily active goals ≥ 3 per user, calendar conversion ≥ 40%, mirror insights engagement ≥ 60%.
- 95th percentile chat round-trip < 1500 ms, crash-free sessions > 99%, permissions acceptance > 80%.
- Weekly review of AI drift, privacy posture, and customer feedback to adjust milestone scope.

