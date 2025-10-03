//
//  OnboardingView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var userName = ""
    @AppStorage("userPreferredName") private var userPreferredName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 16) {
                        Text("Welcome to\nYOU AND GOALS")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Where goals feel like conversations\nwith a smart friend")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    Spacer()
                }
                .tag(0)
                
                // Page 2: Voice & Chat
                VStack(spacing: 32) {
                    Spacer()
                    
                    HStack(spacing: 24) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.purple)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Speak or Type")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Create goals naturally through\nvoice or text. Each goal becomes\na living card with its own AI assistant.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    Spacer()
                }
                .tag(1)
                
                // Page 3: Cards
                VStack(spacing: 32) {
                    Spacer()
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .frame(width: 200, height: 120)
                            .offset(x: -20, y: -20)
                        
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.regularMaterial)
                            .frame(width: 200, height: 120)
                            .overlay(
                                VStack {
                                    Image(systemName: "target")
                                        .font(.largeTitle)
                                        .foregroundStyle(.blue)
                                }
                            )
                        
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .frame(width: 200, height: 120)
                            .offset(x: 20, y: 20)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Smart Cards")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Cards can regenerate, break down,\nand schedule themselves. Chat with\neach card for personalized guidance.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    Spacer()
                }
                .tag(2)
                
                // Page 4: Mirror Mode
                VStack(spacing: 32) {
                    Spacer()
                    
                    HStack(spacing: 32) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.primary)
                        
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "brain")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 16) {
                        Text("Mirror Mode")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("See how AI understands your goals.\nToggle between your view and\nthe AI's interpretation anytime.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    Spacer()
                }
                .tag(3)
                
                // Page 5: Get Started
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 24) {
                        Text("Let's Get Started")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("What should we call you?")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        TextField("Your name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }
                    
                    Spacer()
                    
                    Button(action: completeOnboarding) {
                        Text("Start Your Journey")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .tag(4)
            }
            #if os(iOS)
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif
            
            // Skip button
            if currentPage < 4 {
                HStack {
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                }
                .padding()
            }
        }
    }
    
    private func completeOnboarding() {
        if !userName.isEmpty {
            userPreferredName = userName
        }
        hasCompletedOnboarding = true
        
        // Haptic feedback
        #if os(iOS)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}


