import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/purchased_split.dart';

/// Locally stored list of split-tickets the user confirmed buying, newest
/// first. Feeds the "Gespart"-counter in the travel statistics (#70).
///
/// Purely local, DB-account-independent: the user taps "gekauft" on a split
/// analysis and we remember the direct-vs-split difference. Nothing is fetched
/// or synced.
class PurchasedSplitsNotifier extends Notifier<List<PurchasedSplit>> {
  static const _kKey = 'purchased_splits_v1';

  @override
  List<PurchasedSplit> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => PurchasedSplit.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.purchasedAtMs.compareTo(a.purchasedAtMs));
      state = list;
    } catch (_) {
      // Corrupt payload — start clean rather than crash the stats screen.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kKey, jsonEncode(state.map((s) => s.toJson()).toList()));
  }

  /// Record a confirmed purchase. A repeat confirmation of the same connection
  /// (same route + departure) replaces the earlier one instead of double-
  /// counting the saving.
  Future<void> add(PurchasedSplit split) async {
    final rest =
        state.where((s) => s.dedupeKey != split.dedupeKey).toList();
    state = [split, ...rest]
      ..sort((a, b) => b.purchasedAtMs.compareTo(a.purchasedAtMs));
    await _save();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.length) return;
    final list = List<PurchasedSplit>.from(state)..removeAt(index);
    state = list;
    await _save();
  }

  /// True once this route+departure has already been marked as bought — lets
  /// the UI show "gekauft ✓" instead of the confirm button.
  bool contains(String dedupeKey) =>
      state.any((s) => s.dedupeKey == dedupeKey);

  Future<void> reset() async {
    state = const [];
    await _save();
  }

  /// Total money the user actually saved via bought split-tickets.
  double get totalSavings => state.fold(0.0, (sum, s) => sum + s.savings);

  int get count => state.length;
}

final purchasedSplitsProvider =
    NotifierProvider<PurchasedSplitsNotifier, List<PurchasedSplit>>(
        PurchasedSplitsNotifier.new);
