void main() {
  // Test del regex corregido
  final weightRegex = RegExp(r'\[(U?-?\d+\.?\d*\s*)\]');

  final testCases = [
    '[U94.8 ]', // Peso inestable con espacio
    '[U94.8]', // Peso inestable sin espacio
    '[79 ]', // Peso estable con espacio
    '[79]', // Peso estable sin espacio
    '[3.85]', // Voltaje
    '[-0.5]', // Peso negativo
    '[U0.0 ]', // Peso inestable cero con espacio
  ];

  print('=== TEST REGEX PESO CORREGIDO ===');

  for (final test in testCases) {
    final match = weightRegex.firstMatch(test);
    if (match != null) {
      final rawValue = match.group(1) ?? '';
      final cleanValue = rawValue.trim();

      String status = 'ESTABLE';
      String processedValue = cleanValue;

      if (cleanValue.startsWith('U')) {
        status = 'INESTABLE';
        processedValue = cleanValue.substring(1).trim();
      } else if (cleanValue.startsWith('-')) {
        status = 'NEGATIVO';
        processedValue = cleanValue.trim();
      }

      final numValue = double.tryParse(processedValue);

      print('Input: "$test"');
      print('  Raw: "$rawValue"');
      print('  Clean: "$cleanValue"');
      print('  Status: $status');
      print('  Value: $numValue');
      print('  ✅ MATCH\n');
    } else {
      print('Input: "$test" → ❌ NO MATCH\n');
    }
  }
}
