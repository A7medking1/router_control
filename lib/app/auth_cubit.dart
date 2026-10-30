import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../router/router_client.dart';
import '../router/router_repository.dart';
import '../router/secure_store.dart';

enum AuthStatus { checking, loggedOut, submitting, loggedIn }

class AuthState extends Equatable {
  const AuthState(this.status, {this.error});

  final AuthStatus status;
  final String? error;

  @override
  List<Object?> get props => [status, error];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState(AuthStatus.checking));

  final RouterRepository _repository;

  /// One automatic attempt only: a repeated wrong password locks the login.
  Future<void> restore() async {
    final saved = await _repository.store.readCredentials();
    if (saved == null) {
      emit(const AuthState(AuthStatus.loggedOut));
      return;
    }
    await _login(saved, remember: true);
  }

  Future<void> login(
    String username,
    String password, {
    required bool remember,
  }) => _login(Credentials(username, password), remember: remember);

  Future<void> logout() async {
    await _repository.logout();
    emit(const AuthState(AuthStatus.loggedOut));
  }

  Future<void> _login(Credentials credentials, {required bool remember}) async {
    emit(const AuthState(AuthStatus.submitting));
    try {
      await _repository.login(credentials, remember: remember);
      emit(const AuthState(AuthStatus.loggedIn));
    } on LoginFailedException catch (error) {
      await _repository.store.clearCredentials();
      emit(AuthState(AuthStatus.loggedOut, error: error.message));
    } on Exception {
      emit(
        const AuthState(
          AuthStatus.loggedOut,
          error: 'مش قادر أوصل للراوتر، تأكد إنك على واي فاي البيت',
        ),
      );
    }
  }
}
