import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/utils/connectivity_service.dart';

class ConnectivityState {
  final InternetStatus status;
  final bool isOnline;
  final bool hasNoInternet;
  final bool isLimited;

  const ConnectivityState({
    required this.status,
    required this.isOnline,
    required this.hasNoInternet,
    required this.isLimited,
  });

  factory ConnectivityState.offline() => const ConnectivityState(
    status: InternetStatus.offline,
    isOnline: false,
    hasNoInternet: true,
    isLimited: false,
  );

  factory ConnectivityState.online() => const ConnectivityState(
    status: InternetStatus.online,
    isOnline: true,
    hasNoInternet: false,
    isLimited: false,
  );

  factory ConnectivityState.limited() => const ConnectivityState(
    status: InternetStatus.limited,
    isOnline: false,
    hasNoInternet: false,
    isLimited: true,
  );

  ConnectivityState copyWith({
    InternetStatus? status,
    bool? isOnline,
    bool? hasNoInternet,
    bool? isLimited,
  }) {
    return ConnectivityState(
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      hasNoInternet: hasNoInternet ?? this.hasNoInternet,
      isLimited: isLimited ?? this.isLimited,
    );
  }
}

class ConnectivityCubit extends Cubit<ConnectivityState> {
  final ConnectivityService _connectivityService;
  StreamSubscription<InternetStatus>? _subscription;

  ConnectivityCubit(this._connectivityService)
    : super(ConnectivityState.offline()) {
    _init();
  }

  void _init() {
    final lastStatus = _connectivityService.lastStatus;
    _emitFromStatus(lastStatus);

    _subscription = _connectivityService.statusStream.listen((status) {
      _emitFromStatus(status);
    });
  }

  void _emitFromStatus(InternetStatus status) {
    switch (status) {
      case InternetStatus.online:
        emit(ConnectivityState.online());
      case InternetStatus.offline:
        emit(ConnectivityState.offline());
      case InternetStatus.limited:
        emit(ConnectivityState.limited());
    }
  }

  Stream<InternetStatus> get statusStream => _connectivityService.statusStream;

  @override
  Future<void> close() {
    unawaited(_subscription?.cancel());
    return super.close();
  }
}
