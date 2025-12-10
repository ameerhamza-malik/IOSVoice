# iOS Voice Translation Module

This project contains the source code for an iOS applications that uses `WhisperKit` to perform real-time speech transcription on-device.

## Prerequisites
- A Mac with Xcode 15+ installed.
- iOS 17+ device (CoreML optimizations work best on recent hardware).

## Setup
1.  **Copy Files**: Move the `Translation Module` folder to your Mac.
2.  **Create Xcode Project**:
    - Open Xcode -> Create a new App -> Interface: SwiftUI -> Language: Swift.
    - Name it `TranslationApp`.
3.  **Add Dependencies**:
    - In Xcode, go to `File > Add Package Dependencies`.
    - Enter URL: `https://github.com/argmax-inc/WhisperKit`
    - Click **Add Package**.
4.  **Import Files**:
    - Drag and drop the `Services/`, `Models/`, and `Views/` folders into your Xcode project navigator.
    - Replace the generated `ContentView.swift` and `App` file with the ones provided.
5.  **Permissions**:
    - Open `Info.plist`.
    - Add Key: `Privacy - Microphone Usage Description`.
    - Value: "We need access to the microphone for real-time translation."

## usage
- Run the app on a physical device (Simulators may not support the ANE/GPU acceleration fully or microphone input).
- Wait for "Model Ready" (First run downloads the model).
- Press "Start" and speak.

## Notes
- The code is configured to use `large-v3-turbo`. WhisperKit will attempt to download the best quantized version (~700-800MB) for your device automatically.
- Ensure your device has enough free storage.
