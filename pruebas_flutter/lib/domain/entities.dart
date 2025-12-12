import 'package:equatable/equatable.dart';

class BtDevice extends Equatable {
  final String id; // MAC (SPP) o deviceId (BLE)
  final String name;
  const BtDevice({required this.id, required this.name});
  @override
  List<Object?> get props => [id, name];
}

enum WeightStatus { stable, unstable, negative, overload }

class WeightReading extends Equatable {
  final double? kg;
  final DateTime at;
  final WeightStatus status;
  const WeightReading(
      {required this.kg, required this.at, this.status = WeightStatus.stable});
  @override
  List<Object?> get props => [kg, at, status];
}

class BatteryStatus extends Equatable {
  final double? volts;
  final double? percent;
  final DateTime at;
  const BatteryStatus({this.volts, this.percent, required this.at});
  @override
  List<Object?> get props => [volts, percent, at];
}

// ================== MODELOS BD NORMALIZADA ==================

class Cuadrilla extends Equatable {
  final int? idCuadrilla;
  final String nombre;
  const Cuadrilla({this.idCuadrilla, required this.nombre});
  @override
  List<Object?> get props => [idCuadrilla, nombre];

  factory Cuadrilla.fromMap(Map<String, dynamic> map) {
    return Cuadrilla(
      idCuadrilla: map['id_cuadrilla'] as int?,
      nombre: map['nombre'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        if (idCuadrilla != null) 'id_cuadrilla': idCuadrilla,
        'nombre': nombre,
      };
}

class Operario extends Equatable {
  final int? idOperario;
  final String nombreCompleto;
  final int idCuadrilla;
  const Operario(
      {this.idOperario,
      required this.nombreCompleto,
      required this.idCuadrilla});
  @override
  List<Object?> get props => [idOperario, nombreCompleto, idCuadrilla];

  factory Operario.fromMap(Map<String, dynamic> map) {
    return Operario(
      idOperario: map['id_operario'] as int?,
      nombreCompleto: map['nombre_completo'] as String,
      idCuadrilla: map['id_cuadrilla'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        if (idOperario != null) 'id_operario': idOperario,
        'nombre_completo': nombreCompleto,
        'id_cuadrilla': idCuadrilla,
      };
}

class Bascula extends Equatable {
  final int? idBascula;
  final String nombre;
  final String? modelo;
  final String? numeroSerie;
  final String? mac;
  final String? ubicacion;
  const Bascula({
    this.idBascula,
    required this.nombre,
    this.modelo,
    this.numeroSerie,
    this.mac,
    this.ubicacion,
  });
  @override
  List<Object?> get props =>
      [idBascula, nombre, modelo, numeroSerie, mac, ubicacion];

  factory Bascula.fromMap(Map<String, dynamic> map) {
    return Bascula(
      idBascula: map['id_bascula'] as int?,
      nombre: map['nombre'] as String,
      modelo: map['modelo'] as String?,
      numeroSerie: map['numero_serie'] as String?,
      mac: map['mac'] as String?,
      ubicacion: map['ubicacion'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (idBascula != null) 'id_bascula': idBascula,
        'nombre': nombre,
        'modelo': modelo,
        'numero_serie': numeroSerie,
        'mac': mac,
        'ubicacion': ubicacion,
      };
}

class Pesaje extends Equatable {
  final int? idPesaje;
  final int idCuadrilla;
  final int idOperario;
  final int idBascula;
  final double peso;
  final DateTime fechaHora; // almacenado como TEXT ISO8601 en SQLite
  final String? colorCinta;
  final String? lote;
  final bool recusado;
  const Pesaje({
    this.idPesaje,
    required this.idCuadrilla,
    required this.idOperario,
    required this.idBascula,
    required this.peso,
    required this.fechaHora,
    this.colorCinta,
    this.lote,
    this.recusado = false,
  });
  @override
  List<Object?> get props => [
        idPesaje,
        idCuadrilla,
        idOperario,
        idBascula,
        peso,
        fechaHora,
        colorCinta,
        lote,
        recusado
      ];

  factory Pesaje.fromMap(Map<String, dynamic> map) {
    return Pesaje(
      idPesaje: map['id_pesaje'] as int?,
      idCuadrilla: map['id_cuadrilla'] as int,
      idOperario: map['id_operario'] as int,
      idBascula: map['id_bascula'] as int,
      peso: (map['peso'] as num).toDouble(),
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
      colorCinta: map['color_cinta'] as String?,
      lote: map['lote'] as String?,
      recusado: (map['recusado'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        if (idPesaje != null) 'id_pesaje': idPesaje,
        'id_cuadrilla': idCuadrilla,
        'id_operario': idOperario,
        'id_bascula': idBascula,
        'peso': peso,
        'fecha_hora': fechaHora.toIso8601String(),
        'color_cinta': colorCinta,
        'lote': lote,
        'recusado': recusado ? 1 : 0,
      };
}
