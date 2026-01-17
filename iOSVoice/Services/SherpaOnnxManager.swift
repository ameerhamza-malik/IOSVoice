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
                            "cjkchar".withCString { unitCStr in
                                var config = createOfflineConfig(
                                    modelPath: modelCStr,
                                    tokensPath: tokensCStr,
                                    language: langCStr,
                                    provider: providerCStr,
                                    decodingMethod: methodCStr,
                                    modelingUnit: unitCStr,
                                    sampleRate: Int32(sampleRate)
                                )
                                
                                // Create recognizer
                                recognizer = SherpaOnnxCreateOfflineRecognizer(&config)
                            }
                        }
                    }
                }
            }
        }
        
        // Setup VAD (optional - only if model exists)
        if let vadModelPath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            vadModelPath.withCString { vadCStr in
                "cpu".withCString { providerCStr in
                    var vadModelConfig = SherpaOnnxSileroVadModelConfig(
                        model: vadCStr,
                        threshold: 0.5,
                        min_silence_duration: 0.5,
                        min_speech_duration: 0.25,
                        window_size: 512,
                        max_speech_duration: 5.0
                    )
                    
                    var tenVad = SherpaOnnxTenVadModelConfig(
                        model: nil, threshold: 0, min_silence_duration: 0,
                        min_speech_duration: 0, window_size: 0, max_speech_duration: 0
                    )
                    
                    var vadConfig = SherpaOnnxVadModelConfig(
                        silero_vad: vadModelConfig,
                        sample_rate: Int32(sampleRate),
                        num_threads: 1,
                        provider: providerCStr,
                        debug: 0,
                        ten_vad: tenVad
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
}

// Helper function to create config with proper C struct initialization
private func createOfflineConfig(
    modelPath: UnsafePointer<Int8>,
    tokensPath: UnsafePointer<Int8>,
    language: UnsafePointer<Int8>,
    provider: UnsafePointer<Int8>,
    decodingMethod: UnsafePointer<Int8>,
    modelingUnit: UnsafePointer<Int8>,
    sampleRate: Int32
) -> SherpaOnnxOfflineRecognizerConfig {
    
    // Create empty model configs
    var transducer = SherpaOnnxOfflineTransducerModelConfig(encoder: nil, decoder: nil, joiner: nil)
    var paraformer = SherpaOnnxOfflineParaformerModelConfig(model: nil)
    var nemoCtc = SherpaOnnxOfflineNemoEncDecCtcModelConfig(model: nil)
    var whisper = SherpaOnnxOfflineWhisperModelConfig(encoder: nil, decoder: nil, language: nil, task: nil, tail_paddings: 0)
    var tdnn = SherpaOnnxOfflineTdnnModelConfig(model: nil)
    
    // SenseVoice config (the one we're using)
    var senseVoice = SherpaOnnxOfflineSenseVoiceModelConfig(
        model: modelPath,
        language: language,
        use_itn: 1
    )
    
    // Empty model configs for other models
    var moonshine = SherpaOnnxOfflineMoonshineModelConfig(preprocessor: nil, encoder: nil, uncached_decoder: nil, cached_decoder: nil)
    var fireRedAsr = SherpaOnnxOfflineFireRedAsrModelConfig(encoder: nil, decoder: nil)
    var dolphin = SherpaOnnxOfflineDolphinModelConfig(model: nil)
    var zipformerCtc = SherpaOnnxOfflineZipformerCtcModelConfig(model: nil)
    var canary = SherpaOnnxOfflineCanaryModelConfig(encoder: nil, decoder: nil, src_lang: nil, tgt_lang: nil, use_pnc: 0)
    var wenetCtc = SherpaOnnxOfflineWenetCtcModelConfig(model: nil)
    var omnilingual = SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(model: nil)
    var medasr = SherpaOnnxOfflineMedAsrCtcModelConfig(model: nil)
    var funasrNano = SherpaOnnxOfflineFunASRNanoModelConfig(
        encoder_adaptor: nil, llm: nil, embedding: nil, tokenizer: nil,
        system_prompt: nil, user_prompt: nil, max_new_tokens: 0, temperature: 0, top_p: 0, seed: 0
    )
    
    // Model config
    var modelConfig = SherpaOnnxOfflineModelConfig(
        transducer: transducer,
        paraformer: paraformer,
        nemo_ctc: nemoCtc,
        whisper: whisper,
        tdnn: tdnn,
        tokens: tokensPath,
        num_threads: 2,
        debug: 0,
        provider: provider,
        model_type: nil,
        modeling_unit: modelingUnit,
        bpe_vocab: nil,
        telespeech_ctc: nil,
        sense_voice: senseVoice,
        moonshine: moonshine,
        fire_red_asr: fireRedAsr,
        dolphin: dolphin,
        zipformer_ctc: zipformerCtc,
        canary: canary,
        wenet_ctc: wenetCtc,
        omnilingual: omnilingual,
        medasr: medasr,
        funasr_nano: funasrNano
    )
    
    // Feature config
    var featConfig = SherpaOnnxFeatureConfig(
        sample_rate: sampleRate,
        feature_dim: 80
    )
    
    // LM config (not used for SenseVoice)
    var lmConfig = SherpaOnnxOfflineLMConfig(model: nil, scale: 0.0)
    
    // Homophone replacer (not used)
    var hr = SherpaOnnxHomophoneReplacerConfig(dict_dir: nil, lexicon: nil, rule_fsts: nil)
    
    // Final recognizer config
    return SherpaOnnxOfflineRecognizerConfig(
        feat_config: featConfig,
        model_config: modelConfig,
        lm_config: lmConfig,
        decoding_method: decodingMethod,
        max_active_paths: 4,
        hotwords_file: nil,
        hotwords_score: 1.5,
        rule_fsts: nil,
        rule_fars: nil,
        blank_penalty: 0.0,
        hr: hr
    )
}
