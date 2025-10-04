# YOU AND GOALS

**A conversational AI-powered goal management app for iOS that revolutionizes how you plan, track, and achieve your objectives through intelligent card-based interfaces and voice interaction.**

## 🎯 Overview

YOU AND GOALS is an innovative iOS app that combines the power of AI with intuitive goal management. Instead of traditional calendar interfaces, it uses conversational AI and smart cards to help you break down, schedule, and track your goals naturally.

### Key Features

- **🤖 AI-First Design**: Every goal gets its own AI assistant for personalized guidance
- **🎤 Voice-First Input**: Speak your goals naturally using advanced speech recognition
- **📱 Card-Based Interface**: Goals are represented as interactive, intelligent cards
- **🔄 Mirror Mode**: See how AI understands your goals and progress
- **📅 Smart Scheduling**: AI automatically schedules time for your goals in your calendar
- **🌳 Hierarchical Goals**: Break down complex goals into manageable steps
- **📊 Progress Tracking**: Visual progress indicators and timeline views
- **🔒 Privacy-First**: On-device processing for sensitive data

## 🏗️ Architecture

### Tech Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (iOS 17.0+)
- **Data Persistence**: SwiftData
- **AI Integration**: OpenAI API (GPT-4)
- **Voice Processing**: Speech Framework + Whisper
- **Calendar Integration**: EventKit
- **Minimum iOS**: 17.0

### Project Structure
```
box/
├── Models/              # SwiftData models
│   ├── Goal.swift      # Core goal model with hierarchical structure
│   ├── ChatEntry.swift # Unified chat system
│   └── AIAction.swift  # AI action definitions
├── Services/           # Core business logic
│   ├── AIService.swift # OpenAI integration and prompt engineering
│   ├── VoiceService.swift # Speech recognition and transcription
│   ├── CalendarService.swift # EventKit integration
│   └── AutopilotService.swift # Automated goal management
├── Views/              # SwiftUI user interface
│   ├── ContentView.swift # Main app interface
│   ├── GoalCardView.swift # Individual goal cards
│   ├── MirrorModeView.swift # AI understanding visualization
│   └── Components/     # Reusable UI components
└── Utilities/          # Extensions and helpers
```

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+ device or simulator
- OpenAI API key (for AI features)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd box
   ```

2. **Open in Xcode**
   ```bash
   open box.xcodeproj
   ```

3. **Configure API Keys**
   - Create a `SecretsService.swift` file with your OpenAI API key
   - Add your API key to the configuration

4. **Build and Run**
   - Select your target device/simulator
   - Press Cmd+R to build and run

### Configuration

The app requires the following permissions:
- **Microphone**: For voice input
- **Speech Recognition**: For converting speech to text
- **Calendar**: For scheduling goal sessions

## 🎨 Core Features

### 1. Goal Management
- **Hierarchical Structure**: Goals can have subgoals and dependencies
- **Sequential Steps**: Break down goals into ordered, actionable steps
- **Progress Tracking**: Visual progress bars and completion status
- **Categories**: Organize goals by theme or project
- **Priorities**: Now/Next/Later priority system

### 2. AI Integration
- **Goal Breakdown**: AI automatically decomposes complex goals
- **Smart Scheduling**: AI suggests optimal times for goal work
- **Conversational Interface**: Chat with individual goals
- **Mirror Mode**: See AI's understanding of your goals
- **Proactive Insights**: AI suggests actions and improvements

### 3. Voice Interface
- **Natural Language**: Speak goals in plain English
- **Real-time Transcription**: Live speech-to-text conversion
- **Voice Commands**: Control the app through voice
- **Offline Support**: Works without internet connection

### 4. Calendar Integration
- **Smart Scheduling**: AI finds optimal time slots
- **Conflict Detection**: Avoids double-booking
- **Session Planning**: Breaks goals into focused work sessions
- **Progress Tracking**: Links calendar events to goal progress

## 🔧 Development

### Code Style
- Swift 5.9+ with modern concurrency (async/await)
- SwiftUI-first approach
- SwiftData for persistence
- MVVM architecture with ObservableObject

### Key Patterns
- **Dependency Injection**: Services are injected as environment objects
- **State Management**: @StateObject and @ObservedObject for reactive UI
- **Error Handling**: Comprehensive error handling with user feedback
- **Accessibility**: VoiceOver support and Dynamic Type

### Testing
- Unit tests for core business logic
- SwiftUI previews for UI components
- Mock services for testing without external dependencies

## 📱 User Interface

### Main Tabs
1. **Chat**: Conversational interface for goal management
2. **Timeline**: Visual timeline of goal progress and deadlines
3. **Categories**: Organized view of goals by category

### Goal Cards
- **Collapsed State**: Title, progress, and quick actions
- **Expanded State**: Full details, subgoals, and chat interface
- **Interactive Elements**: Tap to expand, swipe for actions

### Mirror Mode
- **AI Understanding**: See how AI interprets your goals
- **Insights**: AI-generated suggestions and analysis
- **Pattern Recognition**: Identify trends in your goal management

## 🔒 Privacy & Security

- **On-Device Processing**: Sensitive data stays on your device
- **Minimal Data Collection**: Only essential data is stored
- **Encrypted Storage**: All data is encrypted at rest
- **No Tracking**: No user behavior tracking or analytics
- **Local-First**: App works offline with local data

## 🚀 Deployment

### App Store Requirements
- iOS 17.0+ deployment target
- Privacy manifest configured
- App Store Connect metadata
- Screenshots and app description

### Build Configuration
- Debug/Release configurations
- Code signing setup
- Provisioning profiles
- App Store Connect integration

## 🤝 Contributing

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Code Standards
- Follow Swift style guidelines
- Add documentation for public APIs
- Include unit tests for new features
- Ensure accessibility compliance

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- OpenAI for GPT-4 API
- Apple for SwiftUI and SwiftData frameworks
- Whisper for speech recognition
- The Swift community for inspiration and tools

## 📞 Support

For support, feature requests, or bug reports, please:
1. Check existing issues
2. Create a new issue with detailed information
3. Include device and iOS version
4. Provide steps to reproduce bugs

---

**Built with ❤️ for goal achievers everywhere**
