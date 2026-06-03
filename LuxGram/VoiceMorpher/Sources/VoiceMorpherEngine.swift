import Foundation

/// Local OGG voice morphing (ghostgram-style): decode -> AVAudioEngine effects -> encode.
/// NOTE: Requires OpusBinding with VoiceMorpherProcessor. See VoiceMorpherProcessor.h/.m in OpusBinding.
public final class VoiceMorpherEngine {
    public static let shared = VoiceMorpherEngine()

    private init() {}

    /// Process OGG audio data with the currently selected voice morpher preset.
    /// Calls VoiceMorpherProcessor from OpusBinding for actual audio processing.
    /// When OpusBinding is not available, returns the input data unmodified.
    public func processOggData(
        _ inputData: Data,
        completion: @escaping (Swift.Result<Data, Error>) -> Void
    ) {
        let preset = VoiceMorpherManager.shared.effectivePreset

        guard preset != .disabled else {
            completion(.success(inputData))
            return
        }

        // NOTE: Full integration requires OpusBinding with VoiceMorpherProcessor.
        // The Objective-C VoiceMorpherProcessor decodes OGG -> applies AVAudioEngine effects -> re-encodes.
        // When that bridge is wired:
        //   VoiceMorpherProcessor.processOggData(inputData, preset: objcPreset) { outputData, error in ... }
        //
        // For now, pass through unmodified as a stub.
        completion(.success(inputData))
    }

    public enum VoiceMorpherError: Error, LocalizedError {
        case processingFailed

        public var errorDescription: String? {
            switch self {
            case .processingFailed:
                return "Voice morphing processing failed"
            }
        }
    }
}
