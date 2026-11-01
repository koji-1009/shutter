/// Whether [a] and [b] hold equal elements in the same order.
bool sameElements(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// `Type(name: value, ...)`, leaving out the fields that are null.
String describe(String type, Map<String, Object?> fields) {
  final shown = [
    for (final MapEntry(:key, :value) in fields.entries)
      if (value != null) '$key: $value',
  ];
  return '$type(${shown.join(', ')})';
}
