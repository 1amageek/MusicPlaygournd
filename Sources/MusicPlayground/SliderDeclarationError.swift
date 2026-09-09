import Foundation

public enum SliderDeclarationError: Error, LocalizedError, Sendable {
    case invalidRange(String)
    case invalidValue(String)
    case duplicateID(String)
    case unknownID(String)
    case tooManyControls

    public var errorDescription: String? {
        switch self {
        case .invalidRange(let id): "Invalid slider range: \(id)"
        case .invalidValue(let id): "Slider value is outside its range: \(id)"
        case .duplicateID(let id): "Duplicate slider identity: \(id). Supply distinct explicit IDs."
        case .unknownID(let id): "Unknown slider: \(id)"
        case .tooManyControls: "A session supports at most 32 inline sliders."
        }
    }
}
