# Sherpa-ONNX Setup Instructions

## ✅ COMPLETED: Code Migration

The app has been updated to use Sherpa-ONNX instead of manual ONNX Runtime implementation:
- ✅ Old `SenseVoiceManager.swift` → New `SherpaOnnxManager.swift`
- ✅ `ContentView.swift` updated to use Sherpa manager
- ✅ Removed manual audio processing, tokenization, and CTC decoding

## 📦 Required: Add Sherpa-ONNX Framework

### Step 1: Download Sherpa-ONNX Framework

Download the latest iOS framework:
```bash
# Latest release (check for newer versions)
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.10.30/sherpa-onnx-v1.10.30-ios.tar.bz2
tar xf sherpa-onnx-v1.10.30-ios.tar.bz2
```

Or get it from: https://github.com/k2-fsa/sherpa-onnx/releases

### Step 2: Add Framework to Xcode

1. **Drag `sherpa-onnx.xcframework` into your Xcode project**
   - Ensure "Copy items if needed" is checked
   - Ensure your app target is selected

2. **Verify Framework is Linked**
   - Go to Project Settings → Target → General
   - Check "Frameworks, Libraries, and Embedded Content"
   - `sherpa-onnx.xcframework` should be listed as "Embed & Sign"

### Step 3: Download SenseVoice Model

Download the pre-converted model:
```bash
# Download quantized model (faster, smaller, recommended)
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2
tar xf sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2
```

Or get it from: https://github.com/k2-fsa/sherpa-onnx/releases (check Assets)

### Step 4: Add Model Files to Xcode

1. **Drag the extracted model folder** into your Xcode project
   - The folder is: `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/`
   - Ensure "Create folder references" is selected (blue folder icon)
   - Ensure your app target is checked

2. **Verify in Build Phases**
   - Go to Target → Build Phases → Copy Bundle Resources
   - Ensure the model folder is listed

3. **Model folder should contain:**
   - `model.int8.onnx` (quantized model, ~82MB)
   - `model.onnx` (full precision, ~289MB) - optional
   - `tokens.txt`
   - Other metadata files

### Step 5: (Optional) Add VAD Model for Auto Speech Detection

For automatic speech detection, download the VAD model:
```bash
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
```

Add `silero_vad.onnx` to your Xcode project (same process as above).

### Step 6: Uncomment Code in SherpaOnnxManager.swift

Open `iOSVoice/Services/SherpaOnnxManager.swift` and:

1. **Uncomment the import:**
   ```swift
   import sherpa_onnx
   ```

2. **Uncomment the recognizer and VAD properties:**
   ```swift
   private var recognizer: SherpaOnnxOfflineRecognizer?
   private var vad: SherpaOnnxVoiceActivityDetector?
   ```

3. **Uncomment the setup code in `setupModel()`**

4. **Uncomment the transcription code in `transcribeSegment()`**

5. **Uncomment VAD processing in `processAudio()`**

### Step 7: Build and Run

1. Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
2. Build: Product → Build (Cmd+B)
3. Run on device or simulator

## 🎯 Verify Installation

When you run the app:
1. Switch to "SenseVoice (Sherpa)" in the picker
2. Check console for: `✅ Sherpa-ONNX loaded successfully`
3. Tap microphone button and speak
4. Should see transcription appear

## 🔧 Troubleshooting

### Framework not found
- **Error:** `No such module 'sherpa_onnx'`
- **Fix:** Ensure framework is in "Frameworks, Libraries, and Embedded Content" as "Embed & Sign"

### Model files not found
- **Error:** Model path returns empty string
- **Fix:** 
  - Verify folder is added with "Create folder references" (blue folder)
  - Check "Copy Bundle Resources" in Build Phases
  - Folder name must match: `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`

### App crashes on launch
- **Error:** Library not loaded
- **Fix:** Change framework embedding from "Do Not Embed" to "Embed & Sign"

### No transcription output
- **Error:** Silent failures
- **Fix:** Check console logs for specific error messages

## 📊 Expected Performance

- **Model size:** ~82MB (quantized) or ~289MB (full)
- **Speed:** ~50x faster than real-time on iPhone 12+
- **Languages:** Chinese, Cantonese, English, Japanese, Korean
- **Features:** Auto language detection, emotion tags, punctuation

## 🗑️ Clean Up Old Dependencies

Once Sherpa-ONNX is working, you can remove:

1. **From Xcode:**
   - onnxruntime-swift-package-manager
   - swift-sentencepiece
   - SenseVoiceManager.swift (old)
   - AudioProcessor.swift (no longer needed)

2. **From Package.swift:** Remove the old dependencies

3. **Files to delete:**
   - `iOSVoice/iOSVoice-Bridging-Header.h`
   - Any `.onnx` model files you manually added before

## 📚 Additional Resources

- [Sherpa-ONNX GitHub](https://github.com/k2-fsa/sherpa-onnx)
- [iOS Documentation](https://k2-fsa.github.io/sherpa/onnx/ios/index.html)
- [SenseVoice Documentation](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html)
- [Swift API Examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)

## 💡 Next Steps

After setup:
1. Test transcription with different languages
2. Experiment with VAD settings for better segmentation
3. Try emotion detection features
4. Optimize number of threads for your target device
5. Consider using quantized model for better performance
