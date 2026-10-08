public protocol EqualizerResponse {
    func decibels(at frequency: Double) -> Double
}
