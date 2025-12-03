import 'package:bloc/bloc.dart';

enum WeighingSessionStatus { idle, active, paused, stopped }

class WeighingSessionState {
  final WeighingSessionStatus status;
  final int count;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? sessionId;

  const WeighingSessionState({
    this.status = WeighingSessionStatus.idle,
    this.count = 0,
    this.startTime,
    this.endTime,
    this.sessionId,
  });

  WeighingSessionState copyWith({
    WeighingSessionStatus? status,
    int? count,
    DateTime? startTime,
    DateTime? endTime,
    String? sessionId,
  }) =>
      WeighingSessionState(
        status: status ?? this.status,
        count: count ?? this.count,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        sessionId: sessionId ?? this.sessionId,
      );
}

class WeighingSessionCubit extends Cubit<WeighingSessionState> {
  WeighingSessionCubit() : super(const WeighingSessionState());

  void start({String? sessionId}) {
    emit(WeighingSessionState(
      status: WeighingSessionStatus.active,
      count: 0,
      startTime: DateTime.now(),
      endTime: null,
      sessionId: sessionId,
    ));
  }

  void pause() {
    if (state.status == WeighingSessionStatus.active) {
      emit(state.copyWith(status: WeighingSessionStatus.paused));
    }
  }

  void resume() {
    if (state.status == WeighingSessionStatus.paused) {
      emit(state.copyWith(status: WeighingSessionStatus.active));
    }
  }

  void stop() {
    emit(state.copyWith(
      status: WeighingSessionStatus.stopped,
      endTime: DateTime.now(),
    ));
  }

  void increment() {
    if (state.status == WeighingSessionStatus.active) {
      emit(state.copyWith(count: state.count + 1));
    }
  }
}
