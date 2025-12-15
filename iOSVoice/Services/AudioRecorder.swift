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
        let frameLength = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        
        var samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        // Resample to 16kHz if needed (Whisper requirement)
        let targetSampleRate: Double = 16000.0
        if inputSampleRate != targetSampleRate {
            samples = resample(samples: samples, from: inputSampleRate, to: targetSampleRate)
            print("Resampled: \(inputSampleRate)Hz -> \(targetSampleRate)Hz, samples: \(samples.count)")
        }
        
        // Calculate RMS for debug display
        var rms: Float = 0.0
        if !samples.isEmpty {
            let sum = samples.reduce(0) { $0 + $1 * $1 }
            rms = sqrt(sum / Float(samples.count))
            if rms.isNaN { rms = 0.0 }
            
            DispatchQueue.main.async {
                self.debugRMS = "RMS: \(String(format: "%.4f", rms))"
            }
        }
        
        onAudioBuffer?(samples)
    }
    
    private func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate != outputRate else { return samples }
        
        let ratio = outputRate / inputRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)
        
        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let inputIndex = Double(i) / ratio
            let index0 = Int(floor(inputIndex))
            let index1 = min(index0 + 1, samples.count - 1)
            let fraction = Float(inputIndex - Double(index0))
            
            if index0 < samples.count {
                output[i] = samples[index0] * (1.0 - fraction) + samples[index1] * fraction
            }
        }
        
        return output
    }
}
