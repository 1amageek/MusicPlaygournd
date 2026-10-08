import Foundation

struct CleanupFailure: Error, LocalizedError {
    let original: any Error
    let cleanup: any Error
    var errorDescription: String? {
        "\(original.localizedDescription); audio cleanup also failed: \(cleanup.localizedDescription)"
    }
}
