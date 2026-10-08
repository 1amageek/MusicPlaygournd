public protocol CompressorSettings {
    var enabled: Bool { get set }
    var threshold: Double { get set }
    var ratio: Double { get set }
    var attackMilliseconds: Double { get set }
    var releaseMilliseconds: Double { get set }
    static var defaults: Self { get }
}
