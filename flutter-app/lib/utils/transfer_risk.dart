/// The tightest transfer in a connection, in minutes, from the times the caller
/// supplies (live where it has them). This is what lets the trip detail show a
/// live "Anschluss nicht erreichbar" instead of a stale search-time score
/// (#live): the model's percentage is computed once at search from planned
/// times, so once a train runs late the live gap is the honest truth.
///
/// Each entry is one boarded leg's (arrival, departure). The gap before a change
/// is `next.departure − this.arrival`; the worst (smallest) of them is returned.
/// Negative means a change is already missed. Null when there is no change or a
/// needed time is missing.
library;

int? worstTransferGapMinutes(List<({DateTime? arr, DateTime? dep})> legs) {
  int? worst;
  for (var i = 0; i + 1 < legs.length; i++) {
    final a = legs[i].arr;
    final d = legs[i + 1].dep;
    if (a == null || d == null) continue;
    final gap = d.difference(a).inMinutes;
    if (worst == null || gap < worst) worst = gap;
  }
  return worst;
}
