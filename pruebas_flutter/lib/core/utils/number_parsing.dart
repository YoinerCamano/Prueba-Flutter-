double? extractFirstNumber(String input) {
  final reg = RegExp(r'[-+]?\d+(?:[.,]\d+)?');
  final m = reg.firstMatch(input);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', '.'));
}
