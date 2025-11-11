/// Extrae el primer número encontrado en la cadena dada.
///
/// Esta función busca la primera ocurrencia de un número en la cadena de entrada,
/// soportando tanto enteros como decimales positivos y negativos. Maneja tanto
/// coma como punto como separadores decimales normalizando las comas a puntos antes del análisis.
///
/// El patrón regex coincide con:
/// - Signo opcional (+ o -)
/// - Uno o más dígitos
/// - Parte decimal opcional con separador de coma o punto seguido de dígitos
///
/// Parámetros:
///   [input] - La cadena en la que buscar un número
///
/// Retorna:
///   Un [double] que contiene el primer número encontrado, o `null` si no se
///   encuentra un número válido en la cadena de entrada.
///
/// Ejemplo:
/// ```dart
/// extractFirstNumber("Precio: $25.99") // Retorna 25.99
/// extractFirstNumber("Temperatura: -10,5°C") // Retorna -10.5
/// extractFirstNumber("Sin números aquí") // Retorna null
/// ```
double? extractFirstNumber(String input) {
  final reg = RegExp(r'[-+]?\d+(?:[.,]\d+)?');
  final m = reg.firstMatch(input);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', '.'));
}
