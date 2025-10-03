//
//  VoiceService.swift
//  box
//
//  Created on 29.09.2025.
//

import AVFoundation
import AVFAudio
import Combine
import Foundation

@MainActor
final class VoiceService: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(level: Float)
        case transcribing
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""

    private let audioEngine = AVAudioEngine()
    #if os(iOS)
    private let audioSession = AVAudioSession.sharedInstance()
    #endif
    private let transcriber: WhisperTranscriptionClient
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var totalFramesWritten: AVAudioFramePosition = 0
    private var outputSampleRate: Double = 16000
    private let minimumRecordingDuration: Double = 0.3  // Increased to 300ms for more reliable recordings
    private var recordingStartTime: Date?
    private var debugFrameCount: Int = 0  // Debug counter
    private var outputURL: URL? {
        didSet { cleanupOldFile(oldValue) }
    }

    init(transcriber: WhisperTranscriptionClient? = nil) {
        self.transcriber = transcriber ?? WhisperClient()
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func startRecording() async {
        guard case .idle = state else { return }

        do {
            try configureSession()
            try createRecorder()

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.handle(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            await MainActor.run {
                state = .recording(level: 0)
                recordingStartTime = Date()
                totalFramesWritten = 0
                debugFrameCount = 0
                print("🎤 Recording started at \(recordingStartTime?.description ?? "nil")")
                print("🎤 Audio engine running: \(audioEngine.isRunning)")
            }
        } catch {
            await MainActor.run { state = .error(error.localizedDescription) }
        }
    }

    func stopRecordingGeneral() async {
        guard isRecording else {
            // Force cleanup if stuck
            await MainActor.run {
                cancel()
            }
            return
        }

        // Stop engine and cleanup
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        guard let url = outputURL else {
            await MainActor.run {
                state = .error("No audio captured")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        // Validate by duration written instead of file size
        let framesDuration = Double(totalFramesWritten) / max(outputSampleRate, 1)
        let elapsedDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let seconds = max(framesDuration, elapsedDuration)

        print("🎤 Recording stats: frames=\(totalFramesWritten), duration=\(String(format: "%.2f", seconds))s, buffers=\(debugFrameCount)")
        print("🎤 Debug: framesDuration=\(String(format: "%.3f", framesDuration))s, elapsedDuration=\(String(format: "%.3f", elapsedDuration))s")
        print("🎤 Debug: recordingStartTime=\(recordingStartTime?.description ?? "nil"), outputSampleRate=\(outputSampleRate)")

        if seconds < minimumRecordingDuration {
            await MainActor.run {
                try? FileManager.default.removeItem(at: url)
                state = .error("Recording too short (\(String(format: "%.1f", seconds))s). Hold for at least \(String(format: "%.1f", minimumRecordingDuration))s.")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        // Validate file exists and has content
        guard FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run {
                state = .error("Audio file not created")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("🎤 Audio file size: \(fileSize) bytes")

        if fileSize < 100 {  // Very small file, likely empty
            await MainActor.run {
                try? FileManager.default.removeItem(at: url)
                state = .error("No audio captured. Check microphone permissions.")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        await MainActor.run { state = .transcribing }

        do {
            let text = try await transcriber.transcribeAudio(at: url, goalTitle: "General Chat")
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                transcript = text
                state = .idle
                outputURL = nil
                recordingStartTime = nil
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                state = .error(error.localizedDescription)
                outputURL = nil
                recordingStartTime = nil
            }
        }
    }

    func stopRecording(for goal: Goal) async {
        guard isRecording else {
            // Force cleanup if stuck
            await MainActor.run {
                cancel()
            }
            return
        }

        // Stop engine and cleanup
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        guard let url = outputURL else {
            await MainActor.run {
                state = .error("No audio captured")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        // Validate by duration written instead of file size
        let framesDuration = Double(totalFramesWritten) / max(outputSampleRate, 1)
        let elapsedDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let seconds = max(framesDuration, elapsedDuration)

        print("🎤 Recording stats: frames=\(totalFramesWritten), duration=\(String(format: "%.2f", seconds))s, buffers=\(debugFrameCount)")

        if seconds < minimumRecordingDuration {
            await MainActor.run {
                try? FileManager.default.removeItem(at: url)
                state = .error("Recording too short (\(String(format: "%.1f", seconds))s). Hold for at least \(String(format: "%.1f", minimumRecordingDuration))s.")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        // Validate file exists and has content
        guard FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run {
                state = .error("Audio file not created")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("🎤 Audio file size: \(fileSize) bytes")

        if fileSize < 100 {  // Very small file, likely empty
            await MainActor.run {
                try? FileManager.default.removeItem(at: url)
                state = .error("No audio captured. Check microphone permissions.")
                outputURL = nil
                recordingStartTime = nil
            }
            return
        }

        await MainActor.run { state = .transcribing }

        do {
            let text = try await transcriber.transcribeAudio(at: url, goalTitle: goal.title)
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                transcript = text
                state = .idle
                outputURL = nil
                recordingStartTime = nil
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                outputURL = nil
                recordingStartTime = nil
                self.transitionToError(error.localizedDescription)
            }
        }
    }

    func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        audioFile = nil
        converter = nil
        outputURL = nil
        transcript = ""
        totalFramesWritten = 0
        debugFrameCount = 0
        recordingStartTime = nil
        state = .idle
    }

    func resetTranscript() {
        transcript = ""
    }

    private func configureSession() throws {
        #if os(iOS)
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .mixWithOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #else
        // macOS: AVAudioSession is unavailable; nothing to configure
        #endif
    }

    private func createRecorder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goal-recording.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Use WAV format (PCM) which is universally supported by Whisper
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)

        // Create output format: 16kHz mono PCM for speech recognition
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }

        audioFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
        outputSampleRate = outputFormat.sampleRate
        totalFramesWritten = 0

        // Create converter if formats don't match
        if inputFormat != outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        outputURL = url
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        debugFrameCount += 1
        
        if debugFrameCount % 50 == 0 {
            print("🎤 Audio buffer received: frames=\(frameCount), count=\(debugFrameCount)")
        }

        if let channelData = buffer.floatChannelData {
            let samples = channelData.pointee
            for index in 0..<frameCount {
                peak = max(peak, abs(samples[index]))
            }
        } else if let int16Data = buffer.int16ChannelData {
            let samples = int16Data.pointee
            let scale: Float = 1.0 / Float(Int16.max)
            for index in 0..<frameCount {
                peak = max(peak, abs(Float(samples[index]) * scale))
            }
        } else if let int32Data = buffer.int32ChannelData {
            let samples = int32Data.pointee
            let scale: Float = 1.0 / Float(Int32.max)
            for index in 0..<frameCount {
                peak = max(peak, abs(Float(samples[index]) * scale))
            }
        }

        if let file = audioFile {
            do {
                // Convert and write buffer if needed
                if let converter = converter,
                   let outputFormat = file.processingFormat as AVAudioFormat? {

                    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
                    let capacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio))
                    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                        return
                    }

                    convertedBuffer.frameLength = capacity

                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

                    if let error = error {
                        print("⚠️ Audio conversion error: \(error)")
                    } else if status == .haveData || (status == .inputRanDry && convertedBuffer.frameLength > 0) {
                        try file.write(from: convertedBuffer)
                        totalFramesWritten += AVAudioFramePosition(convertedBuffer.frameLength)
                        if debugFrameCount % 100 == 0 {
                            print("🎤 Frames written: \(totalFramesWritten)")
                        }
                    } else {
                        print("⚠️ Audio conversion status: \(status), frames: \(convertedBuffer.frameLength)")
                    }
                } else {
                    // No conversion needed
                    try file.write(from: buffer)
                    totalFramesWritten += AVAudioFramePosition(buffer.frameLength)
                }
            } catch {
                Task { @MainActor in
                    self.transitionToError("Failed to write audio")
                }
            }
        }

        Task { @MainActor in
            self.state = .recording(level: peak)
        }
    }

    private func cleanupOldFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func transitionToError(_ message: String) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        audioFile = nil
        converter = nil
        outputURL = nil
        totalFramesWritten = 0
        debugFrameCount = 0
        recordingStartTime = nil
        state = .error(message)
    }
}

protocol WhisperTranscriptionClient {
    func transcribeAudio(at url: URL, goalTitle: String) async throws -> String
}

struct WhisperClient: WhisperTranscriptionClient {
    func transcribeAudio(at url: URL, goalTitle: String) async throws -> String {
        let audioData = try Data(contentsOf: url)
        guard !audioData.isEmpty else {
            print("❌ Voice: Audio file is empty")
            throw VoiceError.emptyAudio
        }

        print("🎤 Voice: Sending \(audioData.count) bytes to Whisper API")
        print("🎤 Voice: Goal context: \(goalTitle)")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let apiKey = AIService.shared.currentAPIKey
        guard !apiKey.isEmpty else {
            print("❌ Voice: No API key configured")
            throw VoiceError.api(message: "OpenAI API key not configured. Please add it in Settings.")
        }

        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var formData = MultipartData()
        formData.addField(name: "model", value: "whisper-1")
        formData.addField(name: "response_format", value: "json")
        formData.addField(name: "language", value: "en")
        if !goalTitle.isEmpty {
            formData.addField(name: "prompt", value: "Goal: \(goalTitle)")
        }
        formData.addFile(name: "file", filename: "recording.wav", mimeType: "audio/wav", data: audioData)
        formData.finalize()

        request.addValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Voice: Invalid HTTP response")
            throw VoiceError.network
        }

        print("🎤 Voice: HTTP status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Voice API Error (\(httpResponse.statusCode)): \(message)")

            // Parse OpenAI error response format
            struct OpenAIError: Decodable {
                struct ErrorDetail: Decodable {
                    let message: String
                    let type: String?
                    let param: String?
                    let code: String?
                }
                let error: ErrorDetail
            }

            if let errorResponse = try? JSONDecoder().decode(OpenAIError.self, from: data) {
                var errorMsg = errorResponse.error.message
                if let param = errorResponse.error.param {
                    errorMsg += " (parameter: \(param))"
                }
                print("❌ Voice: OpenAI error: \(errorMsg)")
                throw VoiceError.api(message: errorMsg)
            }

            // Fallback for non-standard error format
            throw VoiceError.api(message: "Transcription failed (Status \(httpResponse.statusCode)). Check your API key and try again.")
        }

        do {
            let payload = try JSONDecoder().decode(WhisperResponse.self, from: data)
            guard let text = payload.text, !text.isEmpty else {
                print("❌ Voice: Empty transcript received")
                throw VoiceError.emptyTranscript
            }
            print("✓ Voice: Transcribed \(text.count) characters")
            return text
        } catch {
            print("❌ Voice: JSON decode error: \(error)")
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("❌ Voice: Response was: \(responseString)")
            throw VoiceError.api(message: "Failed to decode transcription response")
        }
    }
}

struct WhisperResponse: Decodable {
    let text: String?
}

enum VoiceError: LocalizedError {
    case emptyAudio
    case emptyTranscript
    case network
    case api(message: String)

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "Audio capture failed"
        case .emptyTranscript:
            return "No speech detected"
        case .network:
            return "Network unavailable"
        case .api(let message):
            return message
        }
    }
}

private struct MultipartData {
    private let boundary = UUID().uuidString
    private(set) var body = Data()

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    mutating func finalize() {
        body.append("--\(boundary)--\r\n")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

