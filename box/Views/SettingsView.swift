//
//  SettingsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("userPreferredName") private var userPreferredName = ""
    @AppStorage("enableHaptics") private var enableHaptics = true
    @AppStorage("enableSounds") private var enableSounds = true
    @AppStorage("defaultPriority") private var defaultPriority = "next"
    @AppStorage("defaultCategory") private var defaultCategory = "General"
    
    @StateObject private var secretsService = SecretsService.shared
    @State private var showingAPIKeySheet = false
    @State private var tempAPIKey = ""
    @State private var showingRemoveConfirmation = false

    private var hasAPIKey: Bool {
        guard let key = secretsService.openAIKey else { return false }
        return !key.isEmpty
    }

    private var maskedAPIKey: String {
        guard let key = secretsService.openAIKey, !key.isEmpty else { return "Not configured" }
        let suffix = key.suffix(4)
        return "••••••••••\(suffix)"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Profile", icon: "person.fill")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter your name", text: $userPreferredName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // AI Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "AI Configuration", icon: "brain")
                        
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("OpenAI API Key")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(maskedAPIKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(hasAPIKey ? "Update" : "Add") {
                                    tempAPIKey = secretsService.openAIKey ?? ""
                                    showingAPIKeySheet = true
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .clipShape(Capsule())
                            }

                            if hasAPIKey {
                                Button(role: .destructive) {
                                    showingRemoveConfirmation = true
                                } label: {
                                    HStack {
                                        Text("Remove Stored Key")
                                            .font(.subheadline)
                                        Spacer()
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                }
                                .tint(.red)
                            }
                            
                            Divider()
                            
                            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                HStack {
                                    Text("Get API Key")
                                        .font(.subheadline)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Preferences
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Preferences", icon: "slider.horizontal.3")
                        
                        VStack(spacing: 0) {
                            SettingRow(
                                title: "Haptic Feedback",
                                icon: "iphone.radiowaves.left.and.right",
                                isOn: $enableHaptics
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            SettingRow(
                                title: "Sound Effects",
                                icon: "speaker.wave.2.fill",
                                isOn: $enableSounds
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            // Default Priority
                            HStack {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)
                                
                                Text("Default Priority")
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Picker("", selection: $defaultPriority) {
                                    Text("Now").tag("now")
                                    Text("Next").tag("next")
                                    Text("Later").tag("later")
                                }
                                .pickerStyle(.menu)
                                .tint(.blue)
                            }
                            .padding()
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            // Default Category
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)
                                
                                Text("Default Category")
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                TextField("Category", text: $defaultCategory)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                            .padding()
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // About Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "About", icon: "info.circle.fill")
                        
                        VStack(spacing: 16) {
                            HStack {
                                Text("Version")
                                    .font(.subheadline)
                                Spacer()
                                Text("1.0.0")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Build")
                                    .font(.subheadline)
                                Spacer()
                                Text("2025.09.29")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            Button(action: {}) {
                                HStack {
                                    Text("Privacy Policy")
                                        .font(.subheadline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            
                            Divider()
                            
                            Button(action: {}) {
                                HStack {
                                    Text("Terms of Service")
                                        .font(.subheadline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Footer
                    VStack(spacing: 8) {
                        Text("YOU AND GOALS")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Making goals feel like conversations")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            NavigationStack {
                APIKeyEntrySheet(
                    apiKey: $tempAPIKey,
                    onSave: { key in
                        secretsService.updateOpenAIKey(key)
                        tempAPIKey = ""
                        showingAPIKeySheet = false
                    },
                    onCancel: {
                        tempAPIKey = ""
                        showingAPIKeySheet = false
                    }
                )
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Remove stored OpenAI API key?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Key", role: .destructive) {
                secretsService.updateOpenAIKey(nil)
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

struct APIKeyEntrySheet: View {
    @Binding var apiKey: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                TextField("sk-...", text: $apiKey, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .focused($isFieldFocused)
                    .lineLimit(1...3)
            }

            Section {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }

                Button {
                    guard !apiKey.trimmed.isEmpty else {
                        onCancel()
                        return
                    }
                    onSave(apiKey.trimmed)
                } label: {
                    Label("Save Key", systemImage: "checkmark.circle.fill")
                }
                .disabled(apiKey.trimmed.isEmpty)
            }
        }
        .navigationTitle("Configure AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFieldFocused = true
            }
        }
    }
}

struct SettingRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.blue)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}


