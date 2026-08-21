import 'package:flutter/material.dart';

import '../models/coach_sequence.dart';
import '../theme/app_colors.dart';

/// Real-world size of a train, in metres, for drawing it to scale on a map.
///
/// When a Wagenreihung is available we know the exact platform length and every
/// car's start/end offset, so we use those. When we only know the product
/// category (on the route map, before any coach data) we fall back to these
/// typical figures — close enough for a believable silhouette that bends along
/// the rails. Values are realistic averages for German stock (see
/// [TrainDimensions.forProduct]).
class TrainDimensions {
  /// Whole-train length over the buffers.
  final double totalLengthM;

  /// A single coach/car length (used to segment a fallback silhouette).
  final double carLengthM;

  /// Car-body width.
  final double widthM;

  /// Aerodynamic snout length at a driving end (0 = blunt cab / loco front).
  final double noseLenM;

  /// Whether both ends taper into a nose (a symmetric EMU like the ICE 3/4) or
  /// just the front (loco-hauled / push-pull sets).
  final bool noseBothEnds;

  const TrainDimensions({
    required this.totalLengthM,
    required this.carLengthM,
    required this.widthM,
    required this.noseLenM,
    required this.noseBothEnds,
  });

  double get halfWidthM => widthM / 2;

  /// Typical figures keyed by the bahn.de product category. Sources confirmed
  /// against published rolling-stock specs (ICE 3/4, UIC coaches, Dosto, ET 423).
  static TrainDimensions forProduct(String? product) {
    // Figures from DB/Siemens datasheets & German Wikipedia (ICE 3/4, UIC
    // coach 26.4 m × 2.825 m, Dosto 26.8 m × 2.784 m, ET 423 67 m × 3.02 m).
    switch (product) {
      case 'nationalExpress': // ICE — streamlined high-speed unit
        return const TrainDimensions(
          totalLengthM: 250,
          carLengthM: 26.5,
          widthM: 2.95,
          noseLenM: 5,
          noseBothEnds: true,
        );
      case 'national': // IC/EC — blunt loco + UIC coaches (26.4 m)
        return const TrainDimensions(
          totalLengthM: 260,
          carLengthM: 26.4,
          widthM: 2.825,
          noseLenM: 0,
          noseBothEnds: false,
        );
      case 'regionalExpress': // RE — push-pull double-deck (Dosto 26.8 m)
        return const TrainDimensions(
          totalLengthM: 155,
          carLengthM: 26.8,
          widthM: 2.80,
          noseLenM: 0,
          noseBothEnds: false,
        );
      case 'regional': // RB — regional EMU (BR 425/440), rounded cab
        return const TrainDimensions(
          totalLengthM: 70,
          carLengthM: 23,
          widthM: 2.92,
          noseLenM: 3,
          noseBothEnds: true,
        );
      case 'suburban': // S-Bahn EMU (BR 423/430), rounded cab
        return const TrainDimensions(
          totalLengthM: 70,
          carLengthM: 17,
          widthM: 3.02,
          noseLenM: 3,
          noseBothEnds: true,
        );
      default:
        return const TrainDimensions(
          totalLengthM: 120,
          carLengthM: 25,
          widthM: 2.9,
          noseLenM: 2.5,
          noseBothEnds: true,
        );
    }
  }
}

/// True for a symmetric high-speed unit (ICE/ECE) — both ends are snouts.
bool isHighSpeedCoach(CoachSequence s) {
  for (final g in s.groups) {
    final c = g.transport.category.toUpperCase();
    if (c == 'ICE' || c == 'ECE') return true;
    if (g.transport.type.toUpperCase().contains('HIGH_SPEED')) return true;
  }
  return false;
}

/// Fill colour for a single car by its class/role — shared by the platform
/// top-down train and the route-map train so they read the same.
Color coachColor(Coach c) {
  if (!c.isOpen) return AppColors.closedCoach;
  if (c.isLocomotive) return AppColors.locomotive;
  if (c.isRestaurant) return AppColors.restaurant;
  if (c.isFirstClass || c.isMixed) return AppColors.firstClass;
  return AppColors.secondClass;
}
