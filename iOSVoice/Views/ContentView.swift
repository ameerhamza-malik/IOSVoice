import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var whisperManager = WhisperManager()
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                Text("Whisper Live")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        // Committed / Final Text
                        Text(whisperManager.currentText)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // Partial / In-Progress Text
                        if !whisperManager.partialText.isEmpty {
                            Text(whisperManager.partialText)
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
                
                // Status & Visualizer
                VStack(spacing: 20) {
                    if whisperManager.isModelLoaded {
                        if audioRecorder.isRecording {
                            AudioVisualizerView(level: whisperManager.audioLevel)
                                .frame(height: 50)
                            
                            Text("Listening...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Ready to Transcribe")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        ProgressView("Loading Optimized Model...")
                    }
                    
                    // Main Action Button
                    Button(action: {
                        toggleRecording()
                    }) {
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .frame(width: 70, height: 70)
                            .background(audioRecorder.isRecording ? Color.red.gradient : Color.blue.gradient)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 5)
                            .scaleEffect(audioRecorder.isRecording ? 1.1 : 1.0)
                            .animation(.spring(), value: audioRecorder.isRecording)
                    }
                    .disabled(!whisperManager.isModelLoaded)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            setupPipeline()
        }
        .onChange(of: audioRecorder.errorMessage) { newValue in
            if let error = newValue {
                print("Error: \(error)")
            }
        }
    }
    
    private func setupPipeline() {
        Task {
            await whisperManager.setup()
        }
        
        // Link Audio -> Whisper
        audioRecorder.onAudioBuffer = { buffer in
            whisperManager.processAudio(samples: buffer)
        }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            whisperManager.resetState()
            audioRecorder.startRecording()
        }
    }
}

#Preview {
    ContentView()
}
