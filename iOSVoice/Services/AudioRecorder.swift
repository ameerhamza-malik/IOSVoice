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
    
    // Converter
    private var audioConverter: AVAudioConverter?
    private var targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    
    func startRecording() {
        guard !audioEngine.isRunning else { return }
        
        setupSession() // Ensure session is active
        
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        // Setup Converter
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
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
        guard let converter = audioConverter else { return }
        
        let inputFrameCount = AVAudioFrameCount(buffer.frameLength)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        // Safety check for empty buffer
        if targetFrameCount == 0 { return }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else { return }
        
        var error: NSError? = nil
        
        // Has-supplied state for the block
        var haveSuppliedData = false
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if !haveSuppliedData {
                haveSuppliedData = true
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataEndOfStream
                return nil
            }
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Conversion error: \(error.localizedDescription)")
            return
        }
        
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let channelDataValue = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        
        onAudioBuffer?(channelDataValue)
    }
}
