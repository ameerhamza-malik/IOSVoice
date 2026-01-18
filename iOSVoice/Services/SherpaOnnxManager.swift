import Foundation
import AVFoundation
import Combine

// Sherpa-ONNX SenseVoice Manager using C API directly
// No Swift module - uses bridging header to access C API

protocol SherpaOnnxDelegate: AnyObject {
    func didUpdateAudioLevels(level: Float)
    func didDetectSpeechSegment(text: String)
}

@MainActor
class SherpaOnnxManager: ObservableObject {
    
    @Published var currentText = ""
    @Published var partialText = ""
    @Published var isModelLoaded = false
    @Published var audioLevel: Float = 0.0
    
    weak var delegate: SherpaOnnxDelegate?
    
    // Sherpa-ONNX C API objects (OpaquePointers)
    private var recognizer: OpaquePointer?
    private var vad: OpaquePointer?
    
    private var audioBuffer: [Float] = []
    private let sampleRate: Int = 16000
    private let maxBufferSize: Int = 16000 * 30 // 30 seconds max
    
    // Thread safety
    private let processingQueue = DispatchQueue(label: "com.iosvoice.sherpa.processing", qos: .userInitiated)
    private let inferenceLock = NSLock()
    
    init() {
        setupModel()
    }
    
    deinit {
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
        if let vad = vad {
            SherpaOnnxDestroyVoiceActivityDetector(vad)
        }
    }
    
    private func setupModel() {
        print("🔧 Setting up Sherpa-ONNX SenseVoice using C API...")
        
        // Model paths - debug bundle contents first
        let modelDir = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        
        // Debug: List bundle contents
        if let bundlePath = Bundle.main.resourcePath {
            print("📦 Bundle path: \(bundlePath)")
            if let items = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) {
                print("📦 Bundle contents: \(items.filter { $0.contains("sherpa") })")
            }
        }
        
        // Try to find model files
        let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx")
        let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt")
        
        print("🔍 Looking in directory: \(modelDir)")
        print("🔍 Model path result: \(modelPath ?? "nil")")
        print("🔍 Tokens path result: \(tokensPath ?? "nil")")
        
        guard let modelPath = modelPath, let tokensPath = tokensPath else {
            print("❌ Model files not found in bundle: \(modelDir)")
            return
        }
        
        print("✓ Model path: \(modelPath)")
        print("✓ Tokens path: \(tokensPath)")
        
        // Use helper function to create config with all required C structs
        modelPath.withCString { modelCStr in
            tokensPath.withCString { tokensCStr in
                "auto".withCString { langCStr in
                    "cpu".withCString { providerCStr in
                        "greedy_search".withCString { methodCStr in
                            var config = createOfflineConfig(
                                modelPath: modelCStr,
                                tokensPath: tokensCStr,
                                language: langCStr,
                                provider: providerCStr,
                                decodingMethod: methodCStr,
                                sampleRate: Int32(sampleRate)
                            )
                            
                            // Create recognizer
                            recognizer = SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }
        
        // Setup VAD (optional - only if model exists)
        if let vadModelPath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            vadModelPath.withCString { vadCStr in
                "cpu".withCString { providerCStr in
                    let vadModelConfig = SherpaOnnxSileroVadModelConfig(
                        model: vadCStr,
                        threshold: 0.5,
                        min_silence_duration: 0.5,
                        min_speech_duration: 0.25,
                        window_size: 512,
                        max_speech_duration: 5.0
                    )
                    
                    var vadConfig = SherpaOnnxVadModelConfig(
                        silero_vad: vadModelConfig,
                        sample_rate: Int32(sampleRate),
                        num_threads: 1,
                        provider: providerCStr,
                        debug: 0
                    )
                    
                    vad = SherpaOnnxCreateVoiceActivityDetector(&vadConfig, 30.0)
                }
            }
        }
        
        let success = (recognizer != nil)
        isModelLoaded = success
        print(success ? "✅ Sherpa-ONNX loaded successfully via C API" : "❌ Failed to load Sherpa-ONNX")
    }
    
    func processAudio(_ samples: [Float]) {
        guard let recognizer = recognizer else { return }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.inferenceLock.lock()
            defer { self.inferenceLock.unlock() }
            
            // Use VAD if available
            if let vad = self.vad {
                // Feed audio to VAD
                samples.withUnsafeBufferPointer { bufferPointer in
                    SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, bufferPointer.baseAddress, Int32(samples.count))
                }
                
                // Process detected speech segments
                while SherpaOnnxVoiceActivityDetectorDetected(vad) != 0 {
                    // Get speech segment
                    if let segment = SherpaOnnxVoiceActivityDetectorFront(vad) {
                        let segmentSamples = Array(UnsafeBufferPointer(start: segment.pointee.samples, count: Int(segment.pointee.n)))
                        
                        // Transcribe segment
                        self.transcribeSegment(segmentSamples, recognizer: recognizer)
                        
                        // Clean up
                        SherpaOnnxDestroySpeechSegment(segment)
                    }
                    
                    // Remove processed segment
                    SherpaOnnxVoiceActivityDetectorPop(vad)
                }
            } else {
                // No VAD - process entire audio buffer directly
                self.transcribeSegment(samples, recognizer: recognizer)
            }
        }
    }
    
    private func transcribeSegment(_ samples: [Float], recognizer: OpaquePointer) {
        // Create offline stream
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            print("❌ Failed to create stream")
            return
        }
        
        defer {
            SherpaOnnxDestroyOfflineStream(stream)
        }
        
        // Feed audio samples
        samples.withUnsafeBufferPointer { bufferPointer in
            SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), bufferPointer.baseAddress, Int32(samples.count))
        }
        
        // Decode
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        
        // Get result
        if let result = SherpaOnnxGetOfflineStreamResult(stream) {
            defer {
                SherpaOnnxDestroyOfflineRecognizerResult(result)
            }
            
            if let textPtr = result.pointee.text {
                let transcribedText = String(cString: textPtr)
                
                // Get language, emotion, event (SenseVoice specific)
                let language = result.pointee.lang != nil ? String(cString: result.pointee.lang) : ""
                let emotion = result.pointee.emotion != nil ? String(cString: result.pointee.emotion) : ""
                let event = result.pointee.event != nil ? String(cString: result.pointee.event) : ""
                
                print("🎯 Transcription: \(transcribedText)")
                if !language.isEmpty { print("   Language: \(language)") }
                if !emotion.isEmpty { print("   Emotion: \(emotion)") }
                if !event.isEmpty { print("   Event: \(event)") }
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.currentText = transcribedText
                    self.delegate?.didDetectSpeechSegment(text: transcribedText)
                }
            }
        }
    }
    
    func reset() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.inferenceLock.lock()
            defer { self.inferenceLock.unlock() }
            
            self.audioBuffer.removeAll()
            
            if let vad = self.vad {
                SherpaOnnxVoiceActivityDetectorReset(vad)
            }
            
            DispatchQueue.main.async {
                self.currentText = ""
                self.partialText = ""
            }
        }
    }
    
    func manualStop() {
        // Process any remaining audio in buffer
        if !audioBuffer.isEmpty {
            processAudio(audioBuffer)
            audioBuffer.removeAll()
        }
    }
    
    func startNewRecording() {
        // Clear previous state
        audioBuffer.removeAll()
        DispatchQueue.main.async {
            self.currentText = ""
            self.partialText = ""
        }
    }
}

// Helper function to create config with proper C struct initialization
// Based on: https://github.com/k2-fsa/sherpa-onnx/blob/master/c-api-examples/sense-voice-c-api.c
private func createOfflineConfig(
    modelPath: UnsafePointer<Int8>,
    tokensPath: UnsafePointer<Int8>,
    language: UnsafePointer<Int8>,
    provider: UnsafePointer<Int8>,
    decodingMethod: UnsafePointer<Int8>,
    sampleRate: Int32
) -> SherpaOnnxOfflineRecognizerConfig {
    
    // Step 1: Create SherpaOnnxOfflineSenseVoiceModelConfig (memset equivalent)
    var senseVoiceConfig = SherpaOnnxOfflineSenseVoiceModelConfig()
    withUnsafeMutablePointer(to: &senseVoiceConfig) { ptr in
        memset(ptr, 0, MemoryLayout<SherpaOnnxOfflineSenseVoiceModelConfig>.size)
    }
    senseVoiceConfig.model = modelPath
    senseVoiceConfig.language = language
    senseVoiceConfig.use_itn = 1
    
    // Step 2: Create SherpaOnnxOfflineModelConfig (memset equivalent)
    var offlineModelConfig = SherpaOnnxOfflineModelConfig()
    withUnsafeMutablePointer(to: &offlineModelConfig) { ptr in
        memset(ptr, 0, MemoryLayout<SherpaOnnxOfflineModelConfig>.size)
    }
    offlineModelConfig.debug = 1
    offlineModelConfig.num_threads = 1
    offlineModelConfig.provider = provider
    offlineModelConfig.tokens = tokensPath
    offlineModelConfig.sense_voice = senseVoiceConfig
    
    // Step 3: Create SherpaOnnxOfflineRecognizerConfig (memset equivalent)
    var recognizerConfig = SherpaOnnxOfflineRecognizerConfig()
    withUnsafeMutablePointer(to: &recognizerConfig) { ptr in
        memset(ptr, 0, MemoryLayout<SherpaOnnxOfflineRecognizerConfig>.size)
    }
    recognizerConfig.decoding_method = decodingMethod
    recognizerConfig.model_config = offlineModelConfig
    
    return recognizerConfig
}
