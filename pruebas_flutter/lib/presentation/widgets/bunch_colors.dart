import 'package:flutter/material.dart';

import '../../core/database_provider.dart';

/// Definición de colores de cinta para racimos
/// Basado en nombres (sin dependencia de códigos numéricos).
class BunchColors {
  static const List<String> defaultColors = [
    'Amarillo',
    'Rojo',
    'Marrón',
    'Blanco',
    'Negro',
    'Morado',
    'Azul',
    'Verde',
    'Naranja',
  ];

  static const String white = 'Blanco';

  static String _normalizeKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .trim();
  }

  static String _capitalizeWords(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
      if (part.length == 1) return part.toUpperCase();
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static String getColorName(String? colorValue) {
    if (colorValue == null || colorValue.trim().isEmpty) return '';
    final key = _normalizeKey(colorValue);
    const canonical = {
      'amarillo': 'Amarillo',
      'rojo': 'Rojo',
      'marron': 'Marrón',
      'blanco': 'Blanco',
      'negro': 'Negro',
      'morado': 'Morado',
      'azul': 'Azul',
      'verde': 'Verde',
      'naranja': 'Naranja',
      'white': 'Blanco',
      'black': 'Negro',
      'brown': 'Marrón',
      'purple': 'Morado',
      'orange': 'Naranja',
      'blue': 'Azul',
      '7': 'Rojo',
      '8': 'Marrón',
      '10': 'Azul',
      '11': 'Verde',
      '12': 'Azul',
      'azul oscuro': 'Azul',
      'cian': 'Azul',
    };
    return canonical[key] ?? _capitalizeWords(colorValue);
  }

  static Color getColorWidget(String? colorValue) {
    final colorName = getColorName(colorValue);
    switch (colorName) {
      case 'Amarillo':
        return const Color.fromARGB(255, 246, 255, 0);
      case 'Rojo':
        return Colors.red;
      case 'Marrón':
        return Colors.brown;
      case 'Blanco':
        return Colors.white;
      case 'Negro':
        return Colors.black87;
      case 'Morado':
        return Colors.deepPurple;
      case 'Azul':
        return const Color.fromARGB(255, 0, 17, 255);
      case 'Verde':
        return const Color.fromARGB(255, 0, 128, 4);
      case 'Naranja':
        return Colors.orange;
      default:
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
  List<String> _availableColors = BunchColors.defaultColors;

  bool _isDarkColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
  }

  Future<void> _loadCatalogColors() async {
    final db = DatabaseProvider.of(context);
    try {
      final colors = await db.getCintaColors();
      if (!mounted) return;
      setState(() {
        _availableColors = colors.isEmpty ? BunchColors.defaultColors : colors;
        if (_selectedColor == null || _selectedColor!.trim().isEmpty) {
          _selectedColor = _availableColors.first;
          widget.onColorSelected(_selectedColor!);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availableColors = BunchColors.defaultColors;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedColor = BunchColors.getColorName(widget.initialColor);
    if (_selectedColor != null && _selectedColor!.trim().isEmpty) {
      _selectedColor = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCatalogColors();
      }
    });
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
            ..._availableColors.map((colorName) {
              final isSelected = _selectedColor == colorName;
              final color = BunchColors.getColorWidget(colorName);
              return FilterChip(
                label: Text(colorName),
                selected: isSelected,
                backgroundColor: color,
                selectedColor: color,
                side: BorderSide(
                  color: colorName == BunchColors.white
                      ? Colors.grey.shade500
                      : Colors.transparent,
                ),
                labelStyle: TextStyle(
                  color: _isDarkColor(color) ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  setState(() => _selectedColor = colorName);
                  widget.onColorSelected(colorName);
                },
              );
            }),
          ],
        ),
      ],
    );
  }
}
