import 'dart:math' as math;

/// Allows a few insertions, deletions, substitutions or adjacent transpositions
/// when a source proposes a correction. Sequel and model numbers must agree.
bool isCloseSearchSpelling(String original, String suggested) {
  String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  final a = normalize(original);
  final b = normalize(suggested);
  if (a.isEmpty || b.isEmpty || a.length > 120 || b.length > 120) return false;
  if (a == b) return true;
  final limit = (a.length ~/ 4).clamp(1, 4);
  if ((a.length - b.length).abs() > limit) return false;
  final nonDigits = RegExp(r'[^0-9]');
  if (a.replaceAll(nonDigits, '') != b.replaceAll(nonDigits, '')) return false;
  var row = List.generate(b.length + 1, (i) => i);
  var previous = row;
  for (var i = 1; i <= a.length; i++) {
    final next = [i];
    for (var j = 1; j <= b.length; j++) {
      final substitution = row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      var cost = math.min<int>(
        substitution,
        1 + math.min<int>(row[j], next[j - 1]),
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        cost = math.min<int>(cost, previous[j - 2] + 1);
      }
      next.add(cost);
    }
    previous = row;
    row = next;
  }
  return row.last <= limit;
}
