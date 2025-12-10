import SwiftUI

struct AudioVisualizerView: View {
    var level: Float // 0.0 to 1.0 (approximated)
    
    // Create a few bars that bounce
    // We'll simulate a frequency spectrum by using one level and randomizing slightly or mirroring
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.gradient)
                    .frame(width: 4, height: heightForBar(index: index))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
    
    func heightForBar(index: Int) -> CGFloat {
        // Simple visualizer logic
        // Center bars are taller
        let baseHeight: CGFloat = 10
        let maxHeight: CGFloat = 50
        
        // Normalize level
        let normalized = CGFloat(min(max(level * 5, 0), 1)) 
        
        // Randomize slightly for "alive" look
        let randomFactor = CGFloat.random(in: 0.8...1.2)
        
        return baseHeight + (maxHeight * normalized * randomFactor)
    }
}
