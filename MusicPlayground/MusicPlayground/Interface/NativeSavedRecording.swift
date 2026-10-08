import Foundation

struct NativeSavedRecording: Identifiable {
    let destination: URL
    var id: URL { destination }
}
