import Foundation
import Accelerate

class AudioProcessor {
    let sampleRate: Int = 16000
    let nMels: Int = 80
    let frameLength: Int = 400 // 25ms
    let frameShift: Int = 160  // 10ms
    let lfr_m: Int = 7
    let lfr_n: Int = 6
    
    // Mel filterbank
    private var filterBank: [Float] = []
    
    init() {
        buildMelFilterBank()
    }
    
    func computeLogMelSpectrogram(audioSamples: [Float]) -> [[Float]]? {
        // 1. Pre-emphasis (optional, Kaldi usually doesn't need it if not specified)
        // 2. Framing
        let numFrames = (audioSamples.count - frameLength) / frameShift + 1
        if numFrames <= 0 { return nil }
        
        var spectrogram: [[Float]] = []
        var window = [Float](repeating: 0, count: frameLength)
        vDSP_hamm_window(&window, vDSP_Length(frameLength), 0)
        
        // FFT setup
        let log2n = UInt(round(log2(Double(frameLength))))
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        defer {
             vDSP_destroy_fftsetup(fftSetup)
        }

        for i in 0..<numFrames {
            let start = i * frameShift
            let end = start + frameLength
            // Apply window
            var frame = Array(audioSamples[start..<end])
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))
            
            // FFT
            // Pack real data into even/odd for Accelerate FFT
            var real = [Float](repeating: 0, count: frameLength/2)
            var imag = [Float](repeating: 0, count: frameLength/2)
            
            frame.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frameLength/2) { dspPtr in
                    var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
                    vDSP_ctoz(dspPtr, 2, &splitComplex, 1, vDSP_Length(frameLength/2))
                    
                    // Perform FFT
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                    
                    // Compute magnitude squared (Power Spectrum)
                    // vDSP_zvmags(&splitComplex, 1, &real, 1, vDSP_Length(frameLength/2))
                    // Kaldi uses power spectrum? Fbank options usually use power.
                    // Let's assume magnitude for now if unsure, but typically power.
                    
                    // Get magnitude
                     var magnitudes = [Float](repeating: 0, count: frameLength/2)
                     vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(frameLength/2))
                     
                     // Apply Mel Filterbank
                     // Simple matrix multiplication: (1 x 257) * (257 x 80)
                     // Implemented simplified below
                     let mels = applyFilterBank(powerSpectrum: magnitudes)
                     
                     // Log (avoid log(0))
                     let logMels = mels.map { log(max($0, 1e-7)) }
                     spectrogram.append(logMels)
                }
            }
        }
        
        // Apply LFR
        return applyLFR(inputs: spectrogram)
    }
    
    private func buildMelFilterBank() {
        // Placeholder: Needs actual Mel filterbank construction logic matching Kaldi/Torchaudio
        // This is complex to write from scratch in one go. 
        // For now, initializing with random to allow compilation, but this MUST be implemented correctly.
        // In a real scenario, I might load a pre-computed matrix from a file.
    }
    
    private func applyFilterBank(powerSpectrum: [Float]) -> [Float] {
        // Placeholder for matrix multiplication (Modules x Filters)
        return [Float](repeating: 0.0, count: nMels) 
    }
    
    private func applyLFR(inputs: [[Float]]) -> [[Float]] {
        let T = inputs.count
        if T == 0 { return [] }
        let dim = inputs[0].count
        
        // lfr_m = 7, lfr_n = 6
        // Left padding: repeat first frame (m-1)/2 = 3 times
        let leftPadCount = (lfr_m - 1) / 2
        var paddedValues = Array(repeating: inputs[0], count: leftPadCount)
        paddedValues.append(contentsOf: inputs)
        
        let paddedCount = paddedValues.count
        var output: [[Float]] = []
        
        // Loop: logic matches utils/frontend.py
        // We want T_lfr = ceil(T / lfr_n) frames
        // But simply iterating i * lfr_n is easier
        
        var i = 0
        while true {
            let startIndex = i * lfr_n
            if startIndex >= T { break } // Logic based on original T, but accessing padded
            
            // We need to gather 'lfr_m' (7) frames starting at startIndex
            var stackedFrame: [Float] = []
            
            // Check if we have enough frames from startIndex in 'paddedValues'
            // We need indices: startIndex to startIndex + lfr_m
            // Actually in frontend.py: inputs is already padded.
            // i goes from 0 to T_lfr.
            // inputs[i * lfr_n : i * lfr_n + lfr_m]
            
            let endNeeded = startIndex + lfr_m
            
            if endNeeded <= paddedCount {
                // Sufficient frames
                for j in 0..<lfr_m {
                    stackedFrame.append(contentsOf: paddedValues[startIndex + j])
                }
            } else {
                // Not enough frames, replicate last frame
                // 1. Append valid frames
                for j in startIndex..<paddedCount {
                    stackedFrame.append(contentsOf: paddedValues[j])
                }
                // 2. Pad with last frame of paddedValues
                let missing = lfr_m - (paddedCount - startIndex)
                let lastFrame = paddedValues.last!
                for _ in 0..<missing {
                    stackedFrame.append(contentsOf: lastFrame)
                }
            }
            
            output.append(stackedFrame)
            i += 1
        }
        
        return output
    }
}
