# Sherpa-ONNX C API Integration - Setup Complete

## ✅ What Changed

### 1. **Removed Swift Module Import**
- **Before:** `import sherpa_onnx` (doesn't exist)
- **After:** C API via bridging header (correct approach)

### 2. **Updated Bridging Header**
```objc
// iOSVoice-Bridging-Header.h
#import "sherpa-onnx/c-api/c-api.h"
```

### 3. **Rewrote SherpaOnnxManager**
- Now uses C API directly: `SherpaOnnxCreateOfflineRecognizer()`, etc.
- No Swift module dependency
- Proper C string management with `strdup()`
- OpaquePointer for C objects

## 🔧 Xcode Configuration Required

### **CRITICAL: Configure Bridging Header Path**

1. Open `iOSVoice.xcodeproj` in Xcode
2. Select **iOSVoice** target
3. Go to **Build Settings**
4. Search for **"Objective-C Bridging Header"**
5. Set to: `$(PROJECT_DIR)/iOSVoice/iOSVoice-Bridging-Header.h`

OR

Set to: `iOSVoice/iOSVoice-Bridging-Header.h` (relative path)

### **Framework Search Paths** (if needed)

If you still get build errors after setting the bridging header:

1. **Build Settings** → Search for **"Framework Search Paths"**
2. Add: `$(PROJECT_DIR)` (or wherever you placed `sherpa-onnx.xcframework`)

### **Header Search Paths** (for c-api.h)

The framework should include headers, but if needed:

1. **Build Settings** → **Header Search Paths**
2. Add: `$(PROJECT_DIR)/sherpa-onnx.xcframework/Headers` (if headers are separate)

## 📁 Project Structure

```
iOSVoice/
├── iOSVoice-Bridging-Header.h ✅ (Updated to import C API)
├── Services/
│   ├── SherpaOnnxManager.swift ✅ (Rewritten with C API)
│   └── SherpaOnnxManager.swift.old (Backup of old implementation)
├── sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/ (Model folder)
└── sherpa-onnx.xcframework/ (Framework with C API)
```

## 🎯 How the C API Works

### Key C Functions Used:

1. **Recognizer Creation:**
```swift
let recognizer = SherpaOnnxCreateOfflineRecognizer(&config)
```

2. **Stream Processing:**
```swift
let stream = SherpaOnnxCreateOfflineStream(recognizer)
SherpaOnnxAcceptWaveformOffline(stream, sampleRate, samples, count)
SherpaOnnxDecodeOfflineStream(recognizer, stream)
let result = SherpaOnnxGetOfflineStreamResult(stream)
```

3. **VAD (Voice Activity Detection):**
```swift
let vad = SherpaOnnxCreateVoiceActivityDetector(&config, bufferSize)
SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples, count)
let segment = SherpaOnnxVoiceActivityDetectorFront(vad)
```

4. **Cleanup:**
```swift
SherpaOnnxDestroyOfflineRecognizer(recognizer)
SherpaOnnxDestroyVoiceActivityDetector(vad)
SherpaOnnxDestroyOfflineStream(stream)
```

### C String Management:

```swift
// Create C string (must be freed by C API, not Swift)
let cString = strdup("my string")

// Read C string
if let cString = result.pointee.text {
    let swiftString = String(cString: cString)
}
```

## 🔍 Why This Approach is Correct

### Official sherpa-onnx Examples Use:
1. ✅ Bridging header (`SherpaOnnx-Bridging-Header.h`)
2. ✅ C API (`#import "sherpa-onnx/c-api/c-api.h"`)
3. ✅ OpaquePointer for objects
4. ✅ Swift wrappers around C functions

### They DON'T Use:
- ❌ `import sherpa_onnx` (Swift module doesn't exist)
- ❌ Swift Package Manager (not available)
- ❌ Native Swift API (doesn't exist)

## 🚀 Next Steps

### 1. **Build the Project**
```bash
# Clean build folder
Product → Clean Build Folder (Cmd+Shift+K)

# Build
Product → Build (Cmd+B)
```

### 2. **Fix Any Remaining Errors**

If you see:
- **"Cannot find 'SherpaOnnxCreateOfflineRecognizer'"** → Bridging header path not set
- **"sherpa-onnx/c-api/c-api.h' file not found"** → Framework headers not accessible
- **Linker errors** → Framework not properly embedded

### 3. **Test the App**

Once building:
1. Launch on iPad mini (A17 Pro)
2. Switch to "SenseVoice (Sherpa)" in picker
3. Check console for: `✅ Sherpa-ONNX loaded successfully via C API`
4. Test microphone recording
5. Verify transcription output

## 📊 Expected Console Output

```
🔧 Setting up Sherpa-ONNX SenseVoice using C API...
✅ Sherpa-ONNX loaded successfully via C API
🎯 Transcription: 你好世界
   Language: zh
   Emotion: neutral
   Event: 
```

## 🐛 Troubleshooting

### Error: "Use of undeclared type 'SherpaOnnxOfflineRecognizer'"
**Fix:** Bridging header not configured. Set in Build Settings.

### Error: "'sherpa-onnx/c-api/c-api.h' file not found"
**Fix:** Framework headers not accessible. Check framework structure:
```bash
cd sherpa-onnx.xcframework
find . -name "c-api.h"
```

### Error: Linker symbol not found
**Fix:** Framework not linked. Check:
- General → Frameworks, Libraries, and Embedded Content → "Embed & Sign"
- Build Phases → Link Binary With Libraries → sherpa-onnx.xcframework present

## 📚 Reference

- **Official Example:** https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples
- **C API Header:** https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/c-api/c-api.h
- **SenseVoice Models:** https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models

## 🎉 Summary

**Before:**
- ❌ Trying to import non-existent Swift module
- ❌ Build errors: "Cannot find module 'sherpa_onnx'"
- ❌ Wrong architecture

**After:**
- ✅ Using C API via bridging header (official approach)
- ✅ Direct access to all sherpa-onnx functions
- ✅ Matches official examples
- ✅ Ready to build once bridging header path is set

**Final Step:** Set the bridging header path in Xcode Build Settings, then build!
