import Foundation
import Accelerate

protocol SpeechBufferDelegate: AnyObject {
    func didUpdateAudioLevels(level: Float) // For visualizer
    func didDetectSpeechStart()
    func didDetectSpeechEnd(segment: [Float]) // Finalized segment
    func didUpdatePartialBuffer(buffer: [Float]) // For partial real-time inference
}

class SpeechBufferManager {
    weak var delegate: SpeechBufferDelegate?
    
    // Configuration
    private let sampleRate: Double = 16000.0 // Whisper standard
    private let silenceThreshold: Float = 0.02 // Adjust based on env
    private let minSpeechDuration: Double = 0.5 // Seconds
    private let maxSilenceDuration: Double = 0.8 // Wait 800ms of silence to finalize
    
    // State
    private var isSpeechActive = false
    private var silenceDuration: Double = 0
    private var speechDuration: Double = 0
    
    // Buffers
    private var audioBuffer: [Float] = []
    
    // Audio Level for UI
    private var currentLevel: Float = 0.0
    
    func process(buffer: [Float]) {
        // 1. Calculate Energy (RMS)
        let rms = calculateRMS(buffer)
        
        // Notify UI of level
        delegate?.didUpdateAudioLevels(level: rms)
        
        // 2. VAD Logic
        let isLoud = rms > silenceThreshold
        let chunkDuration = Double(buffer.count) / sampleRate
        
        if isLoud {
            if !isSpeechActive {
                isSpeechActive = true
                delegate?.didDetectSpeechStart()
            }
            speechDuration += chunkDuration
            silenceDuration = 0
            
            // Append to main buffer
            audioBuffer.append(contentsOf: buffer)
            
            // Trigger partial update roughly every 0.5s or on every chunk if efficient enough
            // For robustness, throttle this in the Manager, but we'll send it here.
            delegate?.didUpdatePartialBuffer(buffer: audioBuffer)
            
        } else {
            // Silence
            if isSpeechActive {
                silenceDuration += chunkDuration
                
                // Still append silence to provide context, but limit it?
                // Whisper likes some context. We append.
                audioBuffer.append(contentsOf: buffer)
                
                if silenceDuration > maxSilenceDuration {
                    // SPEECH ENDED
                    finalizeSegment()
                }
            }
        }
    }
    
    private func finalizeSegment() {
        guard isSpeechActive else { return }
        
        if speechDuration > minSpeechDuration {
            // Valid Segment
            delegate?.didDetectSpeechEnd(segment: audioBuffer)
        }
        
        // Reset
        isSpeechActive = false
        silenceDuration = 0
        speechDuration = 0
        audioBuffer.removeAll()
    }
    
    private func calculateRMS(_ buffer: [Float]) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(buffer, 1, &rms, vDSP_Length(buffer.count))
        return rms
    }
    
    func reset() {
        audioBuffer.removeAll()
        isSpeechActive = false
        silenceDuration = 0
        speechDuration = 0
    }
}
