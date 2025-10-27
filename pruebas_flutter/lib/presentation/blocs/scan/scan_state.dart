part of 'scan_cubit.dart';

class ScanState extends Equatable {
  final bool loading;
  final bool scanning;
  final List<BtDevice> bonded;
  final List<BtDevice> found;
  final String? error;

  const ScanState({
    required this.loading,
    required this.scanning,
    required this.bonded,
    required this.found,
    this.error,
  });

  const ScanState.initial()
      : loading = false,
        scanning = false,
        bonded = const [],
        found = const [],
        error = null;

  ScanState copyWith({
    bool? loading,
    bool? scanning,
    List<BtDevice>? bonded,
    List<BtDevice>? found,
    String? error,
  }) {
    return ScanState(
      loading: loading ?? this.loading,
      scanning: scanning ?? this.scanning,
      bonded: bonded ?? this.bonded,
      found: found ?? this.found,
      error: error,
    );
  }

  @override
  List<Object?> get props => [loading, scanning, bonded, found, error];
}
