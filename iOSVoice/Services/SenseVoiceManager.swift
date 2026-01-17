import Foundation
import AVFoundation

// ONNX Runtime types are available via Objective-C bridging - no import needed
// TODO: Add SentencePiece dependency to your Xcode project
// import SentencePiece 

class SenseVoiceManager: ObservableObject, SpeechBufferDelegate {
    
    @Published var currentText = ""
    @Published var isModelLoaded = false
    @Published var audioLevel: Float = 0.0
    @Published var partialText = ""
    
    private var session: ORTSession?
    private var env: ORTEnv?
    
    // Placeholder for Tokenizer
    // private var tokenizer: SentencePieceProcessor?
    
    private let audioProcessor = AudioProcessor()
    private var bufferManager = SpeechBufferManager()
    
    // Config
    let modelPath: String?
    let tokenizerPath: String?
    
    // Vocabulary size (check your model, typically around 25000-80000)
    // You can inspect 'logitsData.count / (seqLength * 4)' in runtime to find this dynamically
    private var vocabSize: Int = 25000 
    
    init() {
        // Load model from bundle
        self.modelPath = Bundle.main.path(forResource: "model", ofType: "onnx")
        self.tokenizerPath = Bundle.main.path(forResource: "chn_jpn_yue_eng_ko_spectok", ofType: "bpe.model")
        self.bufferManager.delegate = self
        setup()
    }
    
    func setup() {
        guard let path = modelPath else {
            print("SenseVoice: 'model.onnx' not found in Bundle.")
            return
        }
        
        do {
            env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            let sessionOptions = try ORTSessionOptions()
            // Optimize for Apple Neural Engine if available, or CPU
            // try sessionOptions.appendCoreMLExecutionProvider(withOptions: [:])
            
            session = try ORTSession(env: env!, modelPath: path, sessionOptions: sessionOptions)
            
            // Load Tokenizer
            if let tokPath = tokenizerPath {
                // tokenizer = try SentencePieceProcessor(modelPath: tokPath)
                print("Tokenizer found at \(tokPath) (Not initialized - SentencePiece dependency missing)")
            } else {
                print("SenseVoice: Tokenizer model not found in Bundle.")
            }
            
            print("SenseVoice model loaded successfully.")
            DispatchQueue.main.async {
                self.isModelLoaded = true
            }
        } catch {
            print("Failed to load SenseVoice model: \(error)")
        }
    }

    
    func processAudio(samples: [Float]) {
        bufferManager.process(buffer: samples)
    }
    
    func startNewRecording() {
        currentText = ""
        partialText = ""
        bufferManager.reset()
    }
    
    func manualStop() {
        bufferManager.manualFinalize()
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
        // Optional
    }
    
    func didUpdatePartialBuffer(buffer: [Float]) {
        // SenseVoice is non-autoregressive, usually runs on full segments.
        // We might not support Partial results efficiently without running full inference repeatedly.
        // For now, ignore partials or run inference if really needed.
    }
    
    func didDetectSpeechEnd(segment: [Float]) {
        Task {
            await transcribe(audioSamples: segment)
        }
    }
    
    func transcribe(audioSamples: [Float]) async {
        guard isModelLoaded, let session = session, let env = env else { return }
        
        // 1. Feature Extraction
        guard let features = audioProcessor.computeLogMelSpectrogram(audioSamples: audioSamples) else {
            print("Failed to extract features")
            return
        }
        
        // 2. Prepare Inputs
        let seqLength = features.count
        let featureDim = 560 // 80 mels * 7 stacked
        let flatFeatures = featureToFlatArray(features)
        
        do {
            // Shape: [Batch=1, Time, FeatureDim]
            let speechShape: [NSNumber] = [1, NSNumber(value: seqLength), NSNumber(value: featureDim)]
            let speechData = NSMutableData(bytes: flatFeatures, length: flatFeatures.count * MemoryLayout<Float>.size)
            let speechTensor = try ORTValue(
                tensorData: speechData,
                elementType: ORTTensorElementDataType.float,
                shape: speechShape
            )
            
            // Shape: [Batch=1]
            let lengthShape: [NSNumber] = [1]
            var lengthVal: Int32 = Int32(seqLength)
            let lengthData = Data(bytes: &lengthVal, count: MemoryLayout<Int32>.size)
            let speechLengthsTensor = try ORTValue(
                tensorData: NSMutableData(data: lengthData),
                elementType: ORTTensorElementDataType.int32,
                shape: lengthShape
            )
            
            // Language: 0 (auto)
            var langVal: Int32 = 0 
            let langData = Data(bytes: &langVal, count: MemoryLayout<Int32>.size)
            let languageTensor = try ORTValue(
                tensorData: NSMutableData(data: langData),
                elementType: ORTTensorElementDataType.int32,
                shape: lengthShape
            )
            
            // TextNorm: 15 (withitn)
            var normVal: Int32 = 15
            let normData = Data(bytes: &normVal, count: MemoryLayout<Int32>.size)
            let textNormTensor = try ORTValue(
                tensorData: NSMutableData(data: normData),
                elementType: ORTTensorElementDataType.int32,
                shape: lengthShape
            )
            
            // 3. Inference
            let outputs = try session.run(
                withInputNames: ["speech", "speech_lengths", "language", "textnorm"],
                inputValues: [speechTensor, speechLengthsTensor, languageTensor, textNormTensor],
                outputNames: ["ctc_logits", "encoder_out_lens"],
                runOptions: nil
            )
            
            // 4. Post-processing
            // Get ctc_logits. Shape: [Batch=1, Time, VocabSize]
            guard let logitsValue = outputs["ctc_logits"] else { return }
            let logitsData = try logitsValue.tensorData() as Data
            
            // Calculate actual vocab size from data size
            // Data is Float (4 bytes). Total Elements = Data.count / 4
            // Elements = Time * VocabSize
            // We know Time (output sequence length) is roughly input length / 4 (subsampling)
            // But let's retrieve the output shape if possible, or infer it.
            
            // For now, let's assume we implement a Greedy Decode
            let floatArray = logitsData.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            
            // Infer dimensions
            // The encoder output length is returned in "encoder_out_lens"
            guard let encoderLensValue = outputs["encoder_out_lens"] else { return }
            let encoderLensData = try encoderLensValue.tensorData() as Data
            let outTimeLength = Int(encoderLensData.withUnsafeBytes { $0.load(as: Int32.self) })
            
            if outTimeLength > 0 {
                let inferredVocabSize = floatArray.count / outTimeLength
                
                // Decode Int IDs
                let ids = ctcGreedyDecode(logits: floatArray, timeSteps: outTimeLength, vocabSize: inferredVocabSize)
                
                print("SenseVoice Decoded IDs: \(ids)")
                
                // Convert IDs to String using Tokenizer
                /*
                if let decodedText = tokenizer?.decode(ids: ids) {
                    print("Decoded Text: \(decodedText)")
                     await MainActor.run {
                        self.currentText += decodedText + " "
                    }
                }
                */
                 // Temporary Mock
                let mockOutput = "[Text ID sequence: \(ids.prefix(5))...]" 
                await MainActor.run {
                    self.currentText += mockOutput + " "
                }
            }
            
        } catch {
            print("Inference Error: \(error)")
        }
    }
    
    // Simple Greedy Decode: ArgMax per timestep, remove duplicates/blanks (ID=0)
    private func ctcGreedyDecode(logits: [Float], timeSteps: Int, vocabSize: Int) -> [Int32] {
        var mergedIds: [Int32] = []
        var lastId: Int32 = -1
        let blankId: Int32 = 0
        
        for t in 0..<timeSteps {
            // Find ArgMax for this timestep
            var maxVal: Float = -Float.infinity
            var maxId: Int32 = 0
            
            let offset = t * vocabSize
            
            // Optimization: vDSP_maxvi or manual loop
            for i in 0..<vocabSize {
                let val = logits[offset + i]
                if val > maxVal {
                    maxVal = val
                    maxId = Int32(i)
                }
            }
            
            // CTC Logic: Merge repeated characters, drop blanks
            if maxId != lastId {
                if maxId != blankId {
                    mergedIds.append(maxId)
                }
                lastId = maxId
            }
        }
        
        return mergedIds
    }
    
    private func featureToFlatArray(_ features: [[Float]]) -> [Float] {
        return features.flatMap { $0 }
    }
}
