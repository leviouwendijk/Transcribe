public enum SpeakerFeatureWeighting:
    String,
    Sendable,
    Codable,
    Hashable
{
    /// Each coordinate receives the complete configured family weight.
    /// This preserves the current production behavior.
    case perCoordinate

    /// The configured family weight is distributed across that
    /// family's coordinates independently for each acoustic view.
    case normalizedFamily

    public func apply(
        to coordinates: [SpeakerFeatureCoordinate],
        featureWeights: SpeakerFeatureWeights
    ) -> [SpeakerFeatureCoordinate] {
        let counts = Dictionary(
            grouping: coordinates
        ) { coordinate in
            SpeakerFeatureWeightGroup(
                view: coordinate.view,
                family: coordinate.family
            )
        }.mapValues(
            \.count
        )

        return coordinates.map { coordinate in
            let group = SpeakerFeatureWeightGroup(
                view: coordinate.view,
                family: coordinate.family
            )
            let coordinateCount = self == .normalizedFamily
                ? max(
                    1,
                    counts[group] ?? 1
                )
                : 1
            let viewWeight = coordinate.view == .enhanced
                ? featureWeights.enhancedView
                : 1
            let weight = featureWeights.weight(
                for: coordinate.family
            )
                * viewWeight
                / Double(coordinateCount)

            return .init(
                view: coordinate.view,
                family: coordinate.family,
                weight: weight
            )
        }
    }
}

private struct SpeakerFeatureWeightGroup: Hashable {
    let view: SpeakerFeatureView
    let family: SpeakerFeatureFamily
}

private extension SpeakerFeatureWeights {
    func weight(
        for family: SpeakerFeatureFamily
    ) -> Double {
        switch family {
        case .mfcc:
            mfcc
        case .logMel:
            logMel
        case .pitch:
            pitch
        case .spectral:
            spectral
        case .dynamics:
            dynamics
        case .consistency:
            consistency
        case .quality:
            quality
        }
    }
}
