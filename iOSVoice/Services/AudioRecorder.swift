import Foundation
import AVFoundation
import Combine

class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    
    var onAudioBuffer: (([Float]) -> Void)?
    
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var debugRMS = "RMS: --"
    
    override init() {
        super.init()
        setupSession()
        setupInterruptionHandling()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            #if targetEnvironment(simulator)
            try session.setCategory(.record)
            #else
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            #endif
            try session.setActive(true)
            print("Audio session configured successfully")
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            print("Audio session error: \(error)")
        }
        
        session.requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                if !allowed {
                    self?.errorMessage = "Microphone permission denied. Please enable it in Settings."
                }
            }
        }
    }
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: nil)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            stopRecording()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Optionally restart
                }
            }
        @unknown default:
            break
        }
    }
    
    func startRecording() {
        guard !audioEngine.isRunning else { return }
        
        setupSession()
        
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        print("Started recording with format: \(inputFormat)")
        
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            self?.processBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            errorMessage = "Could not start audio engine: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        inputNode?.removeTap(onBus: 0)
        DispatchQueue.main.async { self.isRecording = false }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataValue = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        
        // Calculate RMS for debug display
        var rms: Float = 0.0
        if !channelDataValue.isEmpty {
            let sum = channelDataValue.reduce(0) { $0 + $1 * $1 }
            rms = sqrt(sum / Float(channelDataValue.count))
            if rms.isNaN { rms = 0.0 }
            
            DispatchQueue.main.async {
                self.debugRMS = "RMS: \(String(format: "%.4f", rms))"
            }
        }
        
        // WhisperKit can handle sample rate conversion internally if needed
        // Send raw audio data
        onAudioBuffer?(channelDataValue)
    }
}
