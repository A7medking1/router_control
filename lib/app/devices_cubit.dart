import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../router/filter_plan.dart';
import '../router/models.dart';
import '../router/router_client.dart';
import '../router/router_repository.dart';

class DevicesState extends Equatable {
  const DevicesState({
    this.snapshot,
    this.loading = false,
    this.busyMac,
    this.error,
  });

  final RouterSnapshot? snapshot;
  final bool loading;
  final String? busyMac;
  final String? error;

  @override
  List<Object?> get props => [snapshot, loading, busyMac, error];
}

class DevicesCubit extends Cubit<DevicesState> {
  DevicesCubit(this._repository) : super(const DevicesState());

  static const allowOnlyBusyKey = 'allow_only';

  final RouterRepository _repository;

  /// [silent] hides failures, for polling while Wi-Fi may be restarting.
  Future<void> refresh({bool silent = false}) async {
    if (state.loading || state.busyMac != null) {
      return;
    }
    emit(DevicesState(snapshot: state.snapshot, loading: true));
    try {
      emit(DevicesState(snapshot: await _repository.load()));
    } on Exception catch (error) {
      emit(
        DevicesState(
          snapshot: state.snapshot,
          error: silent ? null : _message(error),
        ),
      );
    }
  }

  /// Runs before the confirmation dialog, so the user sees what will happen.
  FilterPlan? previewBlock(Host host) {
    final snapshot = state.snapshot;
    final filter = snapshot?.filterFor(host);
    if (snapshot == null || filter == null) {
      return null;
    }
    try {
      return planBlock(filter, host.mac, selfMac: snapshot.selfMac);
    } on FilterPlanException catch (error) {
      emit(DevicesState(snapshot: snapshot, error: error.message));
      return null;
    }
  }

  Future<void> block(Host host, FilterPlan plan) => _apply(host, plan);

  Future<void> unblock(Host host) async {
    final filter = state.snapshot?.filterFor(host);
    if (filter != null) {
      await _apply(host, planUnblock(filter, host.mac));
    }
  }

  /// A typed MAC of a device the router may not know about yet.
  Host hostForMac(String mac) {
    final snapshot = state.snapshot;
    final host = snapshot?.hosts.where((h) => h.mac == mac).firstOrNull;
    return host ?? Host.listed(mac, snapshot?.mainFilter?.name ?? '');
  }

  Future<void> rename(Host host, String name) async {
    if (state.busyMac != null) {
      return;
    }
    emit(DevicesState(snapshot: state.snapshot, busyMac: host.mac));
    try {
      await _repository.renameHost(host, name);
      final snapshot = await _repository.load();
      final saved = snapshot.hosts.where((h) => h.mac == host.mac).firstOrNull;
      emit(
        DevicesState(
          snapshot: snapshot,
          error: saved?.name == name ? null : 'الراوتر ما حفظش الاسم الجديد',
        ),
      );
    } on Exception catch (error) {
      emit(DevicesState(snapshot: state.snapshot, error: _message(error)));
    }
  }

  Future<void> forget(Host host) async {
    if (state.busyMac != null) {
      return;
    }
    emit(DevicesState(snapshot: state.snapshot, busyMac: host.mac));
    try {
      await _repository.forgetHost(host);
      final snapshot = await _repository.load();
      final removed = !snapshot.hosts.any(
        (h) => h.mac == host.mac && h.canRename,
      );
      emit(
        DevicesState(
          snapshot: snapshot,
          error: removed ? null : 'الراوتر ما حذفش الجهاز',
        ),
      );
    } on Exception catch (error) {
      emit(DevicesState(snapshot: state.snapshot, error: _message(error)));
    }
  }

  /// Returns false when the plan was refused or failed.
  Future<bool> enableAllowOnly(Set<String> macs) async {
    final snapshot = state.snapshot;
    final filter = snapshot?.mainFilter;
    if (snapshot == null || filter == null) {
      return false;
    }
    try {
      final plan = planAllowOnly(filter, macs, selfMac: snapshot.selfMac);
      return await _applyTo(filter, plan, busyKey: allowOnlyBusyKey);
    } on FilterPlanException catch (error) {
      emit(DevicesState(snapshot: snapshot, error: error.message));
      return false;
    }
  }

  Future<bool> disableAllowOnly() async {
    final filter = state.snapshot?.mainFilter;
    if (filter == null) {
      return false;
    }
    return _applyTo(
      filter,
      planDisableAllowOnly(filter),
      busyKey: allowOnlyBusyKey,
    );
  }

  Future<void> _apply(Host host, FilterPlan plan) async {
    final filter = state.snapshot?.filterFor(host);
    if (filter != null) {
      await _applyTo(filter, plan, busyKey: host.mac);
    }
  }

  Future<bool> _applyTo(
    WlanFilter filter,
    FilterPlan plan, {
    required String busyKey,
  }) async {
    if (state.busyMac != null) {
      return false;
    }
    emit(DevicesState(snapshot: state.snapshot, busyMac: busyKey));
    try {
      await _repository.applyFilter(filter, plan);
      emit(DevicesState(snapshot: await _repository.load()));
      return true;
    } on Exception catch (error) {
      emit(DevicesState(snapshot: state.snapshot, error: _message(error)));
      return false;
    }
  }

  String _message(Exception error) => error is RouterException
      ? error.message
      : 'الاتصال بالراوتر فشل، حدث القائمة وجرب تاني';
}
