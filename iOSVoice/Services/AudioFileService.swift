import Foundation
import AVFoundation

class AudioFileService {
    
    // Target format: 16kHz, Mono, Float32
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    
    func loadAudio(url: URL) async throws -> [Float] {
        // Read file
        let file = try AVAudioFile(forReading: url)
        
        // Create converter
        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw NSError(domain: "AudioFileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        
        // Calculate output size
        let inputFrameCount = AVAudioFrameCount(file.length)
        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw NSError(domain: "AudioFileService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not create output buffer"])
        }
        
        // Convert
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
             if inNumPackets == 0 {
                 outStatus.pointee = .endOfStream
                 return nil
             }
             
             let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inNumPackets)!
             do {
                 try file.read(into: buffer)
                 outStatus.pointee = .haveData
                 return buffer
             } catch {
                 outStatus.pointee = .endOfStream
                 return nil
             }
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            throw error
        }
        
        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioFileService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not extract float data"])
        }
        
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }
}
