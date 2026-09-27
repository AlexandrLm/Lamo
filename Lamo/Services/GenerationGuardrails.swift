import Foundation
@preconcurrency import LiteRTLM

/// Sampling-side guardrails applied to every generation.
///
/// Native repetition penalties prevent output loops at decode time — the
/// `RepetitionDetector` stays as a post-hoc safety net for the rare cases the
/// penalties don't catch. `maxOutputTokens` bounds runaway generations and
/// protects the KV-cache budget.
///
/// Stored as plain values so tests don't need LiteRTLM types; engine configs
/// are derived in computed properties. Values are deliberately conservative
/// for Gemma 4-class models.
struct GenerationGuardrails: Sendable {
    let repetitionPenalty: Float
    let presencePenalty: Float
    let frequencyPenalty: Float
    let repetitionWindowSize: Int
    let noRepeatNgramSize: Int
    let ngramWindowSize: Int
    let maxOutputTokens: Int

    /// Shared loop-protection penalties — single source so `main` and
    /// `summarization` can't drift apart.
    private static let basePenalties = (
        repetitionPenalty: Float(1.1),
        presencePenalty: Float(0.3),
        frequencyPenalty: Float(0.3),
        repetitionWindowSize: 256,
        noRepeatNgramSize: 5,
        ngramWindowSize: 1024
    )

    /// Main chat responses.
    static let main = GenerationGuardrails(
        repetitionPenalty: basePenalties.repetitionPenalty,
        presencePenalty: basePenalties.presencePenalty,
        frequencyPenalty: basePenalties.frequencyPenalty,
        repetitionWindowSize: basePenalties.repetitionWindowSize,
        noRepeatNgramSize: basePenalties.noRepeatNgramSize,
        ngramWindowSize: basePenalties.ngramWindowSize,
        maxOutputTokens: 2048
    )

    /// Context summarization — same loop protection, tighter output cap.
    static let summarization = GenerationGuardrails(
        repetitionPenalty: basePenalties.repetitionPenalty,
        presencePenalty: basePenalties.presencePenalty,
        frequencyPenalty: basePenalties.frequencyPenalty,
        repetitionWindowSize: basePenalties.repetitionWindowSize,
        noRepeatNgramSize: basePenalties.noRepeatNgramSize,
        ngramWindowSize: basePenalties.ngramWindowSize,
        maxOutputTokens: 1024
    )

    /// Output cap bounded by live KV-cache headroom: never promise more
    /// tokens than the budget can hold.
    static func maxOutputTokens(headroom: Int) -> Int {
        max(0, min(main.maxOutputTokens, headroom))
    }

    var repetitionPenaltyConfig: LiteRTLM.RepetitionPenaltyConfig {
        .init(
            repetitionPenalty: repetitionPenalty,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            windowSize: repetitionWindowSize
        )
    }

    var noRepeatNgramConfig: LiteRTLM.NoRepeatNgramConfig {
        .init(noRepeatNgramSize: noRepeatNgramSize, windowSize: ngramWindowSize)
    }
}
