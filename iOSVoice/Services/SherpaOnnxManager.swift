import Foundation
import AVFoundation
import Combine
import sherpa_onnx

protocol SherpaOnnxDelegate: AnyObject {
    func didUpdateAudioLevels(level: Float)
    func didDetectSpeechSegment(text: String)
}

class SherpaOnnxManager: ObservableObject {
    
    @Published var currentText = ""
    @Published var partialText = ""
    @Published var isModelLoaded = false
    @Published var audioLevel: Float = 0.0
    
    weak var delegate: SherpaOnnxDelegate?
    
    // Sherpa-ONNX objects
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetector?
    
    private var audioBuffer: [Float] = []
    private let sampleRate: Int = 16000
    private let maxBufferSize: Int = 16000 * 30 // 30 seconds max
    
    // Thread safety
    private let processingQueue = DispatchQueue(label: "com.iosvoice.sherpa.processing", qos: .userInitiated)
    private let inferenceLock = NSLock()
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        print("🔧 Setting up Sherpa-ONNX SenseVoice...")
        
        // Configure SenseVoice model
        var config = sherpaOnnxOfflineRecognizerConfig()
        
        // Model paths - adjust based on where you place the model files
        let modelDir = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        config.modelConfig.senseVoice.model = Bundle.main.path(
            forResource: "model.int8", 
            ofType: "onnx", 
            inDirectory: modelDir
        ) ?? ""
        
        config.modelConfig.tokens = Bundle.main.path(
            forResource: "tokens", 
            ofType: "txt", 
            inDirectory: modelDir
        ) ?? ""
        
        // Configuration
        config.modelConfig.senseVoice.language = "auto" // Auto-detect language
        config.modelConfig.senseVoice.useInverseTextNormalization = 1 // Add punctuation
        config.modelConfig.numThreads = 2 // Adjust based on device
        config.modelConfig.debug = 0
        config.modelConfig.provider = "cpu"
        
        // Create recognizer
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        
        // Setup VAD for automatic speech detection
        var vadConfig = sherpaOnnxVadModelConfig()
        if let vadModelPath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            vadConfig.sileroVad.model = vadModelPath
            vadConfig.sileroVad.minSilenceDuration = 0.5  // 500ms silence to split
            vadConfig.sileroVad.minSpeechDuration = 0.25  // 250ms minimum speech
            vadConfig.sileroVad.threshold = 0.5
            vadConfig.sampleRate = Int32(sampleRate)
            
            vad = SherpaOnnxVoiceActivityDetector(config: vadConfig, bufferSizeInSeconds: 30)
        }
        
        let success = (recognizer != nil)
        print(success ? "✅ Sherpa-ONNX loaded successfully" : "❌ Failed to load Sherpa-ONNX")
        
        DispatchQueue.main.async {
            self.isModelLoaded = success
        }
    }
    
    func processAudio(samples: [Float]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate audio level
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            DispatchQueue.main.async {
                self.audioLevel = rms
            }
            
            // Add to buffer
            self.audioBuffer.append(contentsOf: samples)
            
            // Keep buffer size manageable
            if self.audioBuffer.count > self.maxBufferSize {
                let overflow = self.audioBuffer.count - self.maxBufferSize
                self.audioBuffer.removeFirst(overflow)
            }
            
            // TODO: Uncomment after adding sherpa-onnx framework
            /*
            guard let vad = self.vad else { return }
            
            // Feed to VAD
            vad.acceptWaveform(samples: samples)
            
            // Check if speech detected
            if vad.isSpeechDetected() {
                print("🎤 Speech detected")
            }
            
            guard let vad = self.vad else { return }
            
            // Feed to VAD
            vad.acceptWaveform(samples: samples)
            
            // Check if speech detected
            if vad.isSpeechDetected() {
                print("🎤 Speech detected")
            }
            
            // Process completed speech segments
            while !vad.isEmpty() {
                let segment = vad.front()
                self.transcribeSegment(samples: segment.samples)
                vad.pop()
            }O: Uncomment after adding sherpa-onnx framework
        /*
        guard let recognizer = recognizer else { return }
        guard let recognizer = recognizer else { return }
        
        print("🔄 Transcribing segment (\(samples.count) samples)...")
        
        // Create stream
        var stream = recognizer.createStream()
        
        // Accept waveform
        stream.acceptWaveform(sampleRate: sampleRate, samples: samples)
        
        // Decode
        recognizer.decode(stream: stream)
        
        // Get result
        let result = stream.result
        let text = result.text
        
        if !text.isEmpty {
            print("✅ Transcribed: \(text)")
            
            // Extract language if available
            let language = result.lang ?? "unknown"
            if language != "unknown" {
                print("🌍 Detected language: \(language)")
            }
            
            DispatchQueue.main.async {
                self.currentText += text + " "
                self.delegate?.didDetectSpeechSegment(text: text)
            }
        }
        guard !audioBuffer.isEmpty else {
            print("⚠️ No audio in buffer to transcribe")
            return
        }
        
        let samples = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        
        transcribeSegment(samples: samples)
    }
    
    func startNewRecording() {
        currentText = ""
        partialText = ""
        audioBuffer.removeAll(keepingCapacity: true)
        
        // TODO: Uncomment after adding sherpa-onnx framework
        // vad?.reset()
    }
    
    func manualStop() {
        // Transcribe any remaining audio
        transcribeAccumulatedAudio()
    }
    vad?.reset()
    }
    
    func manualStop() {
        // Transcribe any remaining audio
        transcribeAccumulatedAudio()
    }
    
    func resetState() {
        audioBuffer.removeAll(keepingCapacity: true)
        currentText = ""
        partialText = ""
       atic let modelFile = "model.int8.onnx" // Use quantized for better performance
        static let tokensFile = "tokens.txt"
        static let vadModelFile = "silero_vad.onnx"
        
        // Supported languages
        enum Language: String {
            case auto = "auto"      // Auto-detect
            case chinese = "zh"     // Mandarin
            case english = "en"
            case cantonese = "yue"  // 粤语
            case japanese = "ja"
            case korean = "ko"
        }
    }
}
