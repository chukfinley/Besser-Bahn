import '../models/journey.dart';

enum JourneyReliabilityLevel {
  veryReliable,
  reliable,
  moderate,
  risky,
  veryRisky,
}

class JourneyReliability {
  final int score;
  final JourneyReliabilityLevel level;
  final List<String> reasons;

  const JourneyReliability({
    required this.score,
    required this.level,
    required this.reasons,
  });
}

class JourneyReliabilityAnalyzer {
  const JourneyReliabilityAnalyzer._();

  static JourneyReliability analyze(Journey journey) {
    var score = 100;
    final reasons = <String>[];

    if (journey.hasCancelledLeg) {
      score -= 60;
      reasons.add('Cancelled train');
    } else if (journey.hasPartialCancellation) {
      score -= 30;
      reasons.add('Partial cancellation');
    }

    final delays = journey.legs
        .where((leg) => !leg.isWalking)
        .expand<int>(
          (leg) => [leg.departureDelayMinutes, leg.arrivalDelayMinutes],
        );

    final maxDelay = delays.fold<int>(0, (max, delay) {
      return delay > max ? delay : max;
    });

    if (maxDelay > 10) {
      score -= 15;
      reasons.add('Significant delay');
    } else if (maxDelay >= 5) {
      score -= 8;
      reasons.add('Delay');
    }

    if (journey.legs.any((leg) => leg.endsEarly)) {
      score -= 35;
      reasons.add('Train ends early');
    }

    if (journey.legs.any((leg) => leg.disruptions.isNotEmpty) ||
        journey.disruptions.isNotEmpty) {
      score -= 10;
      reasons.add('Service disruption');
    }

    for (final leg in journey.legs) {
      if (leg.hasDeparturePlatformChange || leg.hasArrivalPlatformChange) {
        score -= 8;
        reasons.add('Platform change');
        break;
      }
    }

    for (final leg in journey.legs) {
      final buffer = leg.transferBufferMinutes;
      if (buffer == null) continue;

      if (buffer < 5) {
        score -= 25;
        reasons.add('Short transfer buffer');
      } else if (buffer < 10) {
        score -= 12;
        reasons.add('Limited transfer buffer');
      } else if (buffer >= 15) {
        score += 3;
      }
    }

    final transferCount = journey.transfers;
    if (transferCount > 1) {
      score -= (transferCount - 1) * 5;
      reasons.add('Multiple transfers');
    }

    score = score.clamp(0, 100);

    return JourneyReliability(
      score: score,
      level: _levelFor(score),
      reasons: List.unmodifiable(reasons),
    );
  }

  static JourneyReliabilityLevel _levelFor(int score) {
    if (score >= 90) return JourneyReliabilityLevel.veryReliable;
    if (score >= 75) return JourneyReliabilityLevel.reliable;
    if (score >= 50) return JourneyReliabilityLevel.moderate;
    if (score >= 25) return JourneyReliabilityLevel.risky;
    return JourneyReliabilityLevel.veryRisky;
  }
}
