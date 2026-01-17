# Sherpa-ONNX Integration Guide for iOS

## Why Sherpa-ONNX is Better

Compared to our current manual ONNX Runtime implementation, sherpa-onnx offers:

✅ **Pre-built iOS Framework** - No manual bridging headers or compilation
✅ **Native Swift API** - Clean, idiomatic Swift interface
✅ **SenseVoice Support** - Built-in support with optimized models
✅ **Audio Processing Included** - No need to implement Mel spectrogram extraction
✅ **Production Ready** - Battle-tested in real applications
✅ **Multi-Platform** - Same API for iOS, Android, Windows, Linux, macOS
✅ **Extensive Examples** - Lots of working iOS examples to reference
✅ **Active Maintenance** - Regular updates and bug fixes

## Installation

### Option 1: Pre-built XCFramework (Recommended)

1. **Download the pre-built framework:**
```bash
# Download from GitHub releases
# Latest: https://github.com/k2-fsa/sherpa-onnx/releases

# Or use this direct link (check for latest version):
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.10.30/sherpa-onnx-v1.10.30-ios.tar.bz2
tar xf sherpa-onnx-v1.10.30-ios.tar.bz2
```

2. **Add to Xcode:**
   - Drag `sherpa-onnx.xcframework` into your Xcode project
   - Ensure "Copy items if needed" is checked
   - Ensure your app target is selected

3. **Download SenseVoice model:**
```bash
# Download pre-converted model
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2
tar xf sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2

# Add the extracted folder to your Xcode project
# Make sure to add it to your app target's "Copy Bundle Resources"
```

### Option 2: Swift Package Manager

Add to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/k2-fsa/sherpa-onnx", from: "1.10.30")
]
```

## Usage Examples

### 1. Basic SenseVoice Manager (Replaces current implementation)

Create `SherpaOnnxManager.swift`:

```swift
import Foundation
import sherpa_onnx

class SherpaOnnxManager: ObservableObject {
    @Published var currentText = ""
    @Published var isModelLoaded = false
    @Published var audioLevel: Float = 0.0
    
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var audioBuffer: [Float] = []
    private let sampleRate: Int = 16000
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        // Configure SenseVoice model
        var config = sherpaOnnxOfflineRecognizerConfig()
        
        // SenseVoice model paths (adjust to your bundle paths)
        config.modelConfig.senseVoice.model = Bundle.main.path(forResource: "model", ofType: "onnx", inDirectory: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17") ?? ""
        config.modelConfig.senseVoice.useInverseTextNormalization = 1
        config.modelConfig.tokens = Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17") ?? ""
        config.modelConfig.numThreads = 2
        config.modelConfig.debug = 0
        config.modelConfig.provider = "cpu"
        
        // Language configuration
        config.modelConfig.senseVoice.language = "auto" // auto-detect
        
        // Create recognizer
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        
        if recognizer != nil {
            print("✅ Sherpa-ONNX SenseVoice loaded successfully")
            isModelLoaded = true
        } else {
            print("❌ Failed to load Sherpa-ONNX model")
        }
    }
    
    func processAudio(samples: [Float]) {
        // Accumulate audio samples
        audioBuffer.append(contentsOf: samples)
        
        // Update audio level for UI
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        DispatchQueue.main.async {
            self.audioLevel = rms
        }
    }
    
    func transcribeAccumulatedAudio() {
        guard let recognizer = recognizer, !audioBuffer.isEmpty else { return }
        
        // Create stream
        var stream = recognizer.createStream()
        
        // Accept waveform
        stream.acceptWaveform(sampleRate: sampleRate, samples: audioBuffer)
        
        // Decode
        recognizer.decode(stream: stream)
        
        // Get result
        let result = stream.result
        let text = result.text
        
        if !text.isEmpty {
            print("🎯 Transcribed: \(text)")
            DispatchQueue.main.async {
                self.currentText += text + " "
            }
        }
        
        // Clear buffer
        audioBuffer.removeAll()
    }
    
    func reset() {
        audioBuffer.removeAll()
        currentText = ""
    }
}
```

### 2. Real-time Recognition with VAD (Voice Activity Detection)

```swift
import Foundation
import sherpa_onnx

class SherpaRealtimeManager: ObservableObject {
    @Published var currentText = ""
    @Published var partialText = ""
    @Published var isModelLoaded = false
    
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var vad: SherpaOnnxVoiceActivityDetector?
    private var circularBuffer: [Float] = []
    private let sampleRate: Int = 16000
    private let maxBufferSize: Int = 16000 * 30 // 30 seconds max
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        // Setup VAD first
        var vadConfig = sherpaOnnxVadModelConfig()
        vadConfig.sileroVad.model = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") ?? ""
        vadConfig.sileroVad.minSilenceDuration = 0.5
        vadConfig.sileroVad.minSpeechDuration = 0.25
        vadConfig.sileroVad.threshold = 0.5
        vadConfig.sampleRate = Int32(sampleRate)
        
        vad = SherpaOnnxVoiceActivityDetector(config: vadConfig, bufferSizeInSeconds: 30)
        
        // Setup SenseVoice recognizer
        var config = sherpaOnnxOfflineRecognizerConfig()
        config.modelConfig.senseVoice.model = Bundle.main.path(forResource: "model", ofType: "onnx", inDirectory: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17") ?? ""
        config.modelConfig.tokens = Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17") ?? ""
        config.modelConfig.numThreads = 2
        
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        
        isModelLoaded = (recognizer != nil && vad != nil)
        print(isModelLoaded ? "✅ Sherpa-ONNX with VAD loaded" : "❌ Failed to load")
    }
    
    func processAudioChunk(samples: [Float]) {
        guard let vad = vad, let recognizer = recognizer else { return }
        
        // Add samples to VAD
        vad.acceptWaveform(samples: samples)
        
        // Check if speech detected
        if vad.isSpeechDetected() {
            print("🎤 Speech detected")
        }
        
        // Check if we have a complete segment
        if !vad.isEmpty() {
            while !vad.isEmpty() {
                let segment = vad.front()
                
                // Transcribe segment
                var stream = recognizer.createStream()
                stream.acceptWaveform(sampleRate: sampleRate, samples: segment.samples)
                recognizer.decode(stream: stream)
                
                let result = stream.result
                if !result.text.isEmpty {
                    print("📝 Segment transcribed: \(result.text)")
                    DispatchQueue.main.async {
                        self.currentText += result.text + " "
                    }
                }
                
                vad.pop()
            }
        }
    }
    
    func reset() {
        vad?.reset()
        currentText = ""
        partialText = ""
    }
}
```

### 3. Integrate with ContentView

Update `ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var whisperManager = WhisperManager()
    @StateObject private var sherpaManager = SherpaRealtimeManager() // ✨ New!
    
    @State private var selectedEngine = "Whisper"
    
    var body: some View {
        VStack {
            // Engine picker
            Picker("Engine", selection: $selectedEngine) {
                Text("Whisper").tag("Whisper")
                Text("SenseVoice (Sherpa)").tag("SenseVoice")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Display text based on selected engine
            ScrollView {
                Text(selectedEngine == "Whisper" ? whisperManager.currentText : sherpaManager.currentText)
                    .padding()
            }
            
            // Record button
            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                    if selectedEngine == "SenseVoice" {
                        sherpaManager.reset()
                    }
                } else {
                    audioRecorder.startRecording()
                    audioRecorder.onAudioBuffer = { samples in
                        if selectedEngine == "Whisper" {
                            whisperManager.processAudio(samples: samples)
                        } else {
                            sherpaManager.processAudioChunk(samples: samples)
                        }
                    }
                }
            }) {
                Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .resizable()
                    .frame(width: 70, height: 70)
                    .foregroundColor(audioRecorder.isRecording ? .red : .blue)
            }
        }
    }
}
```

## Model Files Structure

After downloading and adding to Xcode, your project should have:

```
iOSVoice/
├── sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/
│   ├── model.onnx (or model.int8.onnx for quantized)
│   ├── tokens.txt
│   └── README.md
└── (optional) silero_vad.onnx for VAD
```

Ensure these are added to "Copy Bundle Resources" in Build Phases.

## Supported Features

### Languages
- Chinese (Mandarin, 普通话)
- Cantonese (粤语)
- English
- Japanese  
- Korean

### Capabilities
- Automatic language detection
- Emotion recognition tags
- Event detection (applause, laughter, etc.)
- Inverse text normalization (punctuation)
- VAD for automatic segmentation

## Configuration Options

```swift
// Language selection
config.modelConfig.senseVoice.language = "auto" // or "zh", "en", "yue", "ja", "ko"

// Inverse text normalization (adds punctuation)
config.modelConfig.senseVoice.useInverseTextNormalization = 1

// Number of threads (adjust based on device)
config.modelConfig.numThreads = 2 // 1-4 depending on device

// Use quantized model for better performance
// Use model.int8.onnx instead of model.onnx
```

## Performance Tips

1. **Use quantized model** (`model.int8.onnx`) for better speed with minimal accuracy loss
2. **Adjust threads** based on device (2 threads for most iPhones)
3. **Enable VAD** for automatic speech detection and segmentation
4. **Process in background** to avoid blocking UI

## Comparison: Current vs Sherpa-ONNX

| Feature | Current (Manual ONNX) | Sherpa-ONNX |
|---------|----------------------|-------------|
| Code complexity | ~500 lines | ~100 lines |
| Audio processing | Manual implementation | Built-in |
| Dependencies | 3 separate packages | 1 framework |
| Model format | Need export script | Pre-converted |
| Thread safety | Manual locks | Built-in |
| VAD | Manual implementation | Built-in |
| Error handling | Manual | Built-in |
| Examples | None | Many |
| Maintenance | DIY | Actively maintained |

## Next Steps

1. Download sherpa-onnx framework
2. Download SenseVoice model files
3. Replace `SenseVoiceManager.swift` with `SherpaOnnxManager.swift`
4. Remove ONNX Runtime and SentencePiece dependencies
5. Test with sample audio
6. Deploy! 🚀

## Resources

- [Sherpa-ONNX GitHub](https://github.com/k2-fsa/sherpa-onnx)
- [iOS Documentation](https://k2-fsa.github.io/sherpa/onnx/ios/index.html)
- [SenseVoice Models](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html)
- [Swift API Examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)
