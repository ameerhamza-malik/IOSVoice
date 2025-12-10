import Foundation

struct TranscriptionItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFinal: Bool
    let timestamp: Date = Date()
}
