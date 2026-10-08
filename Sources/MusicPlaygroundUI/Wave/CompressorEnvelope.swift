public protocol CompressorEnvelope {
    var inputEnvelope: [Float] { get }
    var outputEnvelope: [Float] { get }
    var gainReduction: Double { get }
}
