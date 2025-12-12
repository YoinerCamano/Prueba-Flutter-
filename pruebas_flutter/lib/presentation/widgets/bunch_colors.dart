import 'package:flutter/material.dart';

/// Definición de colores de cinta para racimos
/// Código numérico y nombre de color
class BunchColors {
  static const Map<int, String> colorMap = {
    7: 'Rojo',
    8: 'Marrón',
    12: 'Azul oscuro',
    11: 'Verde',
    10: 'Cian',
  };

  static const String white = 'Blanco';

  static List<int> get codes => colorMap.keys.toList();

  static String getColorName(String? colorCode) {
    if (colorCode == null || colorCode.isEmpty) return '';
    if (colorCode == white) return white;
    try {
      final code = int.parse(colorCode);
      return colorMap[code] ?? colorCode;
    } catch (e) {
      return colorCode;
    }
  }

  static Color getColorWidget(String? colorCode) {
    if (colorCode == null || colorCode.isEmpty) return Colors.grey;
    try {
      final code = int.parse(colorCode);
      switch (code) {
        case 7:
          return Colors.red;
        case 8:
          return Colors.brown;
        case 12:
          return Colors.blue.shade900;
        case 11:
          return Colors.green;
        case 10:
          return Colors.cyan;
        default:
          return Colors.grey;
      }
    } catch (e) {
      if (colorCode == white) return Colors.white;
      return Colors.grey;
    }
  }
}

/// Widget selector de colores con botones visuales
class ColorPickerWidget extends StatefulWidget {
  final String? initialColor;
  final ValueChanged<String> onColorSelected;

  const ColorPickerWidget({
    super.key,
    this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  late String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Color de cinta',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Opciones numéricas
            ...BunchColors.codes.map((code) {
              final name = BunchColors.colorMap[code]!;
              final isSelected = _selectedColor == code.toString();
              return FilterChip(
                label: Text(name),
                selected: isSelected,
                backgroundColor: BunchColors.getColorWidget(code.toString()),
                selectedColor: BunchColors.getColorWidget(code.toString()),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  setState(() => _selectedColor = code.toString());
                  widget.onColorSelected(code.toString());
                },
              );
            }),
            // Opción Blanco
            FilterChip(
              label: const Text('Blanco'),
              selected: _selectedColor == BunchColors.white,
              backgroundColor: Colors.white,
              selectedColor: Colors.white70,
              side: BorderSide(
                color: _selectedColor == BunchColors.white
                    ? Colors.blue
                    : Colors.grey,
                width: _selectedColor == BunchColors.white ? 2 : 1,
              ),
              labelStyle: TextStyle(
                color: Colors.black,
                fontWeight: _selectedColor == BunchColors.white
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              onSelected: (_) {
                setState(() => _selectedColor = BunchColors.white);
                widget.onColorSelected(BunchColors.white);
              },
            ),
          ],
        ),
      ],
    );
  }
}
