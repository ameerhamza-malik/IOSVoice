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
    
    init() {
        bufferManager.delegate = self
    }
    
    func setup() async {
        do {
            print("Initializing WhisperKit...")
			let pipe = try await WhisperKit(model: modelName)
            await MainActor.run {
                self.whisperKit = pipe
                self.isModelLoaded = true
                print("WhisperKit loaded!")
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
        // Debounce / Check lock
        if inferenceLock.try() {
            Task {
                defer { inferenceLock.unlock() }
                guard let pipe = whisperKit else { return }
                
                do {
                    let results = try await pipe.transcribe(audioArray: buffer)
                    // Results is [TranscriptionResult] or similar, usually has a .text property or we map it
                    let text = results.map { $0.text }.joined(separator: " ")
                    
                    await MainActor.run {
                        self.partialText = text
                    }
                } catch {
                    print("Partial Error: \(error)")
                }
            }
        }
    }
    
    func didDetectSpeechEnd(segment: [Float]) {
        // High priority - Wait for lock or just launch
        Task {
            // Simple lock spin or just go for it (race condition acceptable for final vs partial)
            inferenceLock.lock()
            defer { inferenceLock.unlock() }
            
            guard let pipe = whisperKit else { return }
            
            do {
                let results = try await pipe.transcribe(audioArray: segment)
                let text = results.map { $0.text }.joined(separator: " ")
                
                if !text.isEmpty {
                    await MainActor.run {
                        self.currentText += " " + text
                        self.partialText = ""
                    }
                }
            } catch {
                print("Finalize error: \(error)")
            }
        }
    }
    func transcribeFile(samples: [Float]) async {
        guard let pipe = whisperKit else { return }
        
        await MainActor.run {
            self.currentText = "Transcribing file..."
            self.partialText = ""
        }
        
        let startTime = Date()
        
        do {
            let results = try await pipe.transcribe(audioArray: samples)
            let timeTaken = Date().timeIntervalSince(startTime)
            let text = results.map { $0.text }.joined(separator: " ")
            
            let finalOutput = "\(text)\n\n[Time: \(String(format: "%.2f", timeTaken))s]"
            print("Transcription Time: \(timeTaken)s")
            
            await MainActor.run {
                self.currentText = finalOutput
            }
        } catch {
            print("File Transcription Error: \(error)")
            await MainActor.run {
                self.currentText = "Error: \(error.localizedDescription)"
            }
        }
    }
}
