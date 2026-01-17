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
        
        // Model paths
        let modelDir = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        guard let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx", inDirectory: modelDir),
              let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: modelDir) else {
            print("❌ Model files not found")
            return
        }
        
        // Create SenseVoice config using C API
        var senseVoiceConfig = SherpaOnnxOfflineSenseVoiceModelConfig(
            model: strdup(modelPath),
            language: strdup("auto"),
            use_itn: 1  // Enable Inverse Text Normalization (punctuation)
        )
        
        var modelConfig = SherpaOnnxOfflineModelConfig(
            transducer: SherpaOnnxOfflineTransducerModelConfig(encoder: nil, decoder: nil, joiner: nil),
            paraformer: SherpaOnnxOfflineParaformerModelConfig(model: nil),
            nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(model: nil),
            whisper: SherpaOnnxOfflineWhisperModelConfig(encoder: nil, decoder: nil, language: nil, task: nil, tail_paddings: 0),
            tdnn: SherpaOnnxOfflineTdnnModelConfig(model: nil),
            tokens: strdup(tokensPath),
            num_threads: 2,
            debug: 0,
            provider: strdup("cpu"),
            model_type: strdup(""),
            modeling_unit: strdup("cjkchar"),
            bpe_vocab: nil,
            telespeech_ctc: nil,
            sense_voice: senseVoiceConfig,
            moonshine: SherpaOnnxOfflineMoonshineModelConfig(preprocessor: nil, encoder: nil, uncached_decoder: nil, cached_decoder: nil),
            fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(encoder: nil, decoder: nil),
            dolphin: SherpaOnnxOfflineDolphinModelConfig(model: nil),
            zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(model: nil),
            canary: SherpaOnnxOfflineCanaryModelConfig(encoder: nil, decoder: nil, src_lang: nil, tgt_lang: nil, use_pnc: 0),
            wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(model: nil),
            omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(model: nil),
            medasr: SherpaOnnxOfflineMedAsrCtcModelConfig(model: nil),
            funasr_nano: SherpaOnnxOfflineFunASRNanoModelConfig(
                encoder_adaptor: nil, llm: nil, embedding: nil, tokenizer: nil,
                system_prompt: nil, user_prompt: nil, max_new_tokens: 0, temperature: 0, top_p: 0, seed: 0
            )
        )
        
        var featConfig = SherpaOnnxFeatureConfig(
            sample_rate: Int32(sampleRate),
            feature_dim: 80
        )
        
        var lmConfig = SherpaOnnxOfflineLMConfig(model: nil, scale: 0.0)
        
        var config = SherpaOnnxOfflineRecognizerConfig(
            feat_config: featConfig,
            model_config: modelConfig,
            lm_config: lmConfig,
            decoding_method: strdup("greedy_search"),
            max_active_paths: 4,
            hotwords_file: nil,
            hotwords_score: 1.5,
            rule_fsts: nil,
            rule_fars: nil,
            blank_penalty: 0.0,
            hr: SherpaOnnxHomophoneReplacerConfig(dict_dir: nil, lexicon: nil, rule_fsts: nil)
        )
        
        // Create recognizer
        recognizer = SherpaOnnxCreateOfflineRecognizer(&config)
        
        // Setup VAD (optional but recommended)
        if let vadModelPath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            var vadModelConfig = SherpaOnnxSileroVadModelConfig(
                model: strdup(vadModelPath),
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
                provider: strdup("cpu"),
                debug: 0,
                ten_vad: SherpaOnnxTenVadModelConfig(
                    model: nil, threshold: 0, min_silence_duration: 0,
                    min_speech_duration: 0, window_size: 0, max_speech_duration: 0
                )
            )
            
            vad = SherpaOnnxCreateVoiceActivityDetector(&vadConfig, 30.0)
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
}

// Helper to duplicate C strings (must be freed later)
private func strdup(_ string: String?) -> UnsafePointer<Int8>? {
    guard let string = string else { return nil }
    return (string as NSString).utf8String
}
