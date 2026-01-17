import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var whisperManager = WhisperManager()
    @StateObject private var senseVoiceManager = SenseVoiceManager()
    @State private var useSenseVoice = false
    
    // File Import State
    @State private var showFileImporter = false
    @State private var isProcessingFile = false
    private let audioFileService = AudioFileService()
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                VStack {
                    Text("Live Transcription")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Picker("Engine", selection: $useSenseVoice) {
                        Text("Whisper").tag(false)
                        Text("SenseVoice").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .onChange(of: useSenseVoice) { _ in
                        setupPipeline()
                    }
                }
                .padding(.top, 40)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        // Committed / Final Text
                        Text(useSenseVoice ? senseVoiceManager.currentText : whisperManager.currentText)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // Partial / In-Progress Text
                        if !(useSenseVoice ? senseVoiceManager.partialText : whisperManager.partialText).isEmpty {
                            Text(useSenseVoice ? senseVoiceManager.partialText : whisperManager.partialText)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
                .padding(.horizontal)
                
                // Error Message
                if let errorMessage = audioRecorder.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Text(audioRecorder.debugRMS)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospaced()

                // Status & Visualizer
                VStack(spacing: 20) {
                    if (useSenseVoice ? senseVoiceManager.isModelLoaded : whisperManager.isModelLoaded) {
                        if audioRecorder.isRecording {
                            AudioVisualizerView(level: useSenseVoice ? senseVoiceManager.audioLevel : whisperManager.audioLevel)
                                .frame(height: 50)
                            
                            Text("Listening...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else if isProcessingFile {
                            ProgressView("Processing File...")
                        } else {
                            Text("Ready to Transcribe")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        ProgressView(useSenseVoice ? "Loading SenseVoice..." : "Loading Optimized Model...")
                    }
                    
                    // Controls
                    HStack(spacing: 40) {
                        // Import Button
                        Button(action: {
                            showFileImporter = true
                        }) {
                            VStack {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.blue.gradient)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                                
                                Text("Import")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(!(useSenseVoice ? senseVoiceManager.isModelLoaded : whisperManager.isModelLoaded) || audioRecorder.isRecording || isProcessingFile)
                        
                        // Mic Button
                        Button(action: {
                            toggleRecording()
                        }) {
                            VStack {
                                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 70, height: 70)
                                    .background(audioRecorder.isRecording ? Color.red.gradient : Color.blue.gradient)
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                                    .scaleEffect(audioRecorder.isRecording ? 1.1 : 1.0)
                                    .animation(.spring(), value: audioRecorder.isRecording)
                                
                                Text(audioRecorder.isRecording ? "Stop" : "Record")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(!(useSenseVoice ? senseVoiceManager.isModelLoaded : whisperManager.isModelLoaded) || isProcessingFile)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .task {
            // Load model immediately when view appears
            await whisperManager.setup()
            setupPipeline()
        }
        .onChange(of: audioRecorder.errorMessage) { newValue in
            if let error = newValue {
                print("Error: \(error)")
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                processFile(url: url)
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupPipeline() {
        // Link Audio -> Active Manager
        audioRecorder.onAudioBuffer = { buffer in
            if useSenseVoice {
                senseVoiceManager.processAudio(samples: buffer)
            } else {
                whisperManager.processAudio(samples: buffer)
            }
        }
    }
    
    private func toggleRecording() {
        let manager: AnyObject = useSenseVoice ? senseVoiceManager : whisperManager
        
        if audioRecorder.isRecording {
            if useSenseVoice {
                senseVoiceManager.manualStop()
            } else {
                whisperManager.manualStop()
            }
            audioRecorder.stopRecording()
        } else {
            if useSenseVoice {
                senseVoiceManager.startNewRecording()
            } else {
                whisperManager.startNewRecording()
            }
            audioRecorder.startRecording()
        }
    }
    
    private func processFile(url: URL) {
        print("Attempting to access file: \(url.absoluteString)")
        guard url.startAccessingSecurityScopedResource() else {
            print("ERROR: startAccessingSecurityScopedResource returned FALSE. Permission denied by system.")
            // Try to read anyway? Sometimes standard files work? 
            // Usually failure here means we really can't read it.
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        print("Successfully accessed security scoped resource.")
        isProcessingFile = true
        whisperManager.resetState()
        
        Task {
            do {
                let samples = try await audioFileService.loadAudio(url: url)
                // Use simulated live stream instead of one-shot
                await whisperManager.simulateLiveStream(samples: samples)
            } catch {
                print("File Processing Error: \(error)")
            }
            
            await MainActor.run {
                isProcessingFile = false
            }
        }
    }
}

#Preview {
    ContentView()
}
