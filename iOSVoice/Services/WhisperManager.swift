import WhisperKit
import AVFoundation
import Combine

class WhisperManager: ObservableObject, SpeechBufferDelegate {
    
    @Published var isModelLoaded = false
    @Published var currentText = ""
    @Published var partialText = ""
    @Published var audioLevel: Float = 0.0
    
    private var whisperKit: WhisperKit?
    private var bufferManager = SpeechBufferManager()
    
    // Use a Task for inference to support async/await
    private var isInferencing = false
    private let inferenceLock = NSLock()
    
    // User requested specific optimized model (~626MB)
    let modelName = "openai_whisper-large-v3-v20240930_626MB"
    
    // Metrics
    var modelLoadTime: TimeInterval = 0
    
    init() {
        bufferManager.delegate = self
    }
    
    func setup() async {
        do {
            print("Initializing WhisperKit...")
            let startLoad = Date()
            let pipe = try await WhisperKit(model: modelName)
            let duration = Date().timeIntervalSince(startLoad)
            
            await MainActor.run {
                self.whisperKit = pipe
                self.isModelLoaded = true
                self.modelLoadTime = duration
                print("WhisperKit loaded in \(String(format: "%.2f", duration))s")
            }
        } catch {
            print("Error loading WhisperKit: \(error)")
        }
    }
    
    func processAudio(samples: [Float]) {
        bufferManager.process(buffer: samples)
    }
    
    func resetState() {
        bufferManager.reset()
        currentText = ""
        partialText = ""
    }
    
    
    // MARK: - SpeechBufferDelegate
    
    func didUpdateAudioLevels(level: Float) {
        DispatchQueue.main.async {
            self.audioLevel = level
        }
    }
    
    func didDetectSpeechStart() {
        // Optional hook
    }
    
    func didUpdatePartialBuffer(buffer: [Float]) {
        // Skip partials for push-to-talk mode
    }
    
    func didDetectSpeechEnd(segment: [Float]) {
        print("Speech ended. Transcribing segment (size: \(segment.count))...")
        
        Task {
            guard let pipe = whisperKit else { 
                print("ERROR: WhisperKit not loaded")
                return 
            }
            
            await MainActor.run {
                self.partialText = "Transcribing..."
            }
            
            do {
                let results = try await pipe.transcribe(audioArray: segment)
                let text = results.map { $0.text }.joined(separator: " ")
                print("✓ Transcribed: '\(text)'")
                
                await MainActor.run {
                    if !text.isEmpty {
                        self.currentText += " " + text
                    }
                    self.partialText = ""
                }
            } catch {
                print("❌ Transcription Error: \(error)")
                await MainActor.run {
                    self.partialText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Simulates a live stream by feeding samples in chunks (for file import)
    func simulateLiveStream(samples: [Float]) async {
        guard let pipe = whisperKit else { return }
        
        await MainActor.run {
            self.currentText = "" // Reset
            self.partialText = "Streaming file..."
        }
        
        // Chunk size: 100ms at 16kHz = 1600 samples
        let chunkSize = 1600
        let sleepNanoseconds: UInt64 = 10_000_000 // 10ms sleep = ~10x realtime
        
        for chunkStart in stride(from: 0, to: samples.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, samples.count)
            let chunk = Array(samples[chunkStart..<chunkEnd])
            
            // Feed to buffer manager as if from mic
            bufferManager.process(buffer: chunk)
            
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            await Task.yield()
        }
        
        print("Stream Loop Finished. Forcing Flush...")
        // Force process any remaining audio in buffer
        bufferManager.forceFlush()
        print("Flush Called.")
        
        await MainActor.run {
            self.partialText = "" 
        }
    }

    func transcribeFile(samples: [Float]) async {
         // Keep old logic for backup if needed, or remove.
         // ... (Logic kept same or reduced)
         // For now, let's comment out or leave as legacy.
    }
}
