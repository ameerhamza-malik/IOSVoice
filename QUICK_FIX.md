# 🎯 QUICK FIX - Complete This in Xcode

## ⚠️ THE ONLY THING YOU NEED TO DO

### Open Xcode and Configure the Bridging Header:

1. **Open** `iOSVoice.xcodeproj` in Xcode

2. **Select** the `iOSVoice` target (click on the project in the left sidebar, then select the target)

3. **Click** on "Build Settings" tab

4. **Search** for: `Objective-C Bridging Header`

5. **Double-click** the empty field next to "Objective-C Bridging Header"

6. **Type** or paste ONE of these paths:

   **Option A (Absolute):**
   ```
   $(PROJECT_DIR)/iOSVoice/iOSVoice-Bridging-Header.h
   ```

   **Option B (Relative - usually works better):**
   ```
   iOSVoice/iOSVoice-Bridging-Header.h
   ```

   **Option C (If it's in the same folder as your Swift files):**
   ```
   iOSVoice-Bridging-Header.h
   ```

7. **Press** Enter

8. **Clean** Build Folder: `Product` → `Clean Build Folder` (Cmd+Shift+K)

9. **Build**: `Product` → `Build` (Cmd+B)

## ✅ What Should Happen

- **Build succeeds** ✅
- **No "Cannot find module" errors** ✅
- **All C API functions accessible** ✅

## ❌ If Build Still Fails

### Check Framework Location:

1. **Build Settings** → Search for `Framework Search Paths`
2. Make sure it includes the folder containing `sherpa-onnx.xcframework`
3. Common paths:
   ```
   $(PROJECT_DIR)
   $(PROJECT_DIR)/Frameworks
   ```

### Verify Framework is Linked:

1. Go to **General** tab (not Build Settings)
2. Scroll to **"Frameworks, Libraries, and Embedded Content"**
3. Make sure `sherpa-onnx.xcframework` is there
4. Set to **"Embed & Sign"**

## 📸 Visual Guide

```
Xcode Navigator
├── iOSVoice (project) ← CLICK THIS
│   ├── iOSVoice (target) ← THEN THIS
│   │   ├── General
│   │   ├── Build Settings ← THEN THIS TAB
│   │   └── ...
```

In Build Settings:
```
Filter: "bridging"

Objective-C Bridging Header
Debug    [iOSVoice/iOSVoice-Bridging-Header.h] ← FILL THIS
Release  [iOSVoice/iOSVoice-Bridging-Header.h] ← AND THIS
```

## 🎬 That's It!

Once you set the bridging header path and build successfully, the app will be ready to use sherpa-onnx via the C API. The error "Cannot find module 'sherpa_onnx'" will disappear because we're no longer trying to import a Swift module that doesn't exist.

---

**Questions?**
- Bridging header path format: relative or absolute?
  → Try relative first (`iOSVoice/iOSVoice-Bridging-Header.h`)
- Still errors? → Share the exact error message
- Framework not found? → Check Framework Search Paths
