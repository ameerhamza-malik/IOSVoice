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
    
    // Queue for sequential processing
    private var segmentQueue: [[Float]] = []
    private var isProcessingQueue = false
    
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
        // Only run partials if we are not deep in queue processing to avoid clogging?
        // Actually, for stream simulation, partials are less critical than final order, but let's keep them.
        if isProcessingQueue { return } // Skip partials if busy processing final segments to keep up
        
        if inferenceLock.try() {
            Task {
                defer { inferenceLock.unlock() }
                guard let pipe = whisperKit else { return }
                
                do {
                    let results = try await pipe.transcribe(audioArray: buffer)
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
        print("VAD: Segment Finalized. Size: \(segment.count). Transcribing directly...")
        
        // Transcribe immediately without queue
        Task {
            guard let pipe = whisperKit else { 
                print("ERROR: WhisperKit not loaded")
                return 
            }
            
            print("Starting transcription for segment...")
            
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
            }
        }
    }
    
    private func processQueue() {
        guard !isProcessingQueue, !segmentQueue.isEmpty else { return }
        
        isProcessingQueue = true
        print("Queue: Starting Processing...")
        
        Task {
            // Drain queue
            while !segmentQueue.isEmpty {
                let segment = segmentQueue.removeFirst()
                print("Queue: Processing Segment... (Remaining: \(segmentQueue.count))")
                
                // We must lock to ensure we don't overlap with partials or other logic
                inferenceLock.lock()
                
                guard let pipe = whisperKit else {
                   inferenceLock.unlock()
                   break
                }
                
                do {
                    let results = try await pipe.transcribe(audioArray: segment)
                    let text = results.map { $0.text }.joined(separator: " ")
                    print("Queue: Segment Transcribed: '\(text)'")
                    
                    await MainActor.run {
                         if !text.isEmpty {
                            self.currentText += " " + text
                        }
                        self.partialText = "" // Clear partial after final
                    }
                } catch {
                    print("Queue Processing Error: \(error)")
                }
                
                inferenceLock.unlock()
            }
            
            isProcessingQueue = false
            print("Queue: Processing Finished.")
            // Check again in case new items arrived while processing?
            if !segmentQueue.isEmpty {
                processQueue()
            }
        }
    }
    
    // Simulates a live stream by feeding samples in chunks
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
