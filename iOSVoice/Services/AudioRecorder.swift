import Foundation
import AVFoundation
import Combine

class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    
    // Delegate to send raw data
    var onAudioBuffer: (([Float]) -> Void)?
    
    @Published var isRecording = false
    @Published var errorMessage: String?
    
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
            // "measurement" mode for cleaner audio (less gain control/processing)
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
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
            // Interruption began (e.g. phone call). Stop recording.
            stopRecording()
        case .ended:
            // Interruption ended. We could resume, but usually best to let user restart.
            // Check options to see if we SHOULD resume
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
        
        setupSession() // Ensure session is active
        
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        // Target format: 16kHz, Mono, Float32 (Whisper Standard)
        // We will install a tap and convert manually if needed, or rely on just grabbing float data.
        // NOTE: CoreAudio Taps usually give you the hardware format.
        // For production, we should downsample if HW is 44.1/48kHz.
        // For this implementation, we simply extract the float channel.
        
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
        
        // Here we arguably should downsample to 16kHz if the input is 44.1/48kHz.
        // WhisperKit 0.2 may handle resampling, or we can use a basic decimation if needed.
        // For simplicity/speed in this template, we pass raw. 
        // Ideally: Resample logic goes here.
        
        onAudioBuffer?(channelDataValue)
    }
}
