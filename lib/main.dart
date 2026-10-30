import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/auth_cubit.dart';
import 'app/devices_cubit.dart';
import 'app/devices_page.dart';
import 'app/login_page.dart';
import 'app/theme.dart';
import 'demo/demo_repository.dart';
import 'router/router_repository.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const RouterControlApp());
}

class RouterControlApp extends StatefulWidget {
  const RouterControlApp({super.key});

  @override
  State<RouterControlApp> createState() => _RouterControlAppState();
}

class _RouterControlAppState extends State<RouterControlApp> {
  final RouterRepository _repository = const bool.fromEnvironment('DEMO')
      ? DemoRouterRepository()
      : RouterRepository();
  late final _auth = AuthCubit(_repository)..restore();

  @override
  void dispose() {
    _auth.close();
    _repository.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [RepositoryProvider.value(value: _repository)],
      child: BlocProvider.value(
        value: _auth,
        child: MaterialApp(
          title: 'Router Control',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: BlocBuilder<AuthCubit, AuthState>(
            buildWhen: (previous, current) =>
                (previous.status == AuthStatus.loggedIn) !=
                    (current.status == AuthStatus.loggedIn) ||
                previous.status == AuthStatus.checking,
            builder: (context, state) => switch (state.status) {
              AuthStatus.checking => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              AuthStatus.loggedIn => BlocProvider(
                create: (_) => DevicesCubit(_repository),
                child: const DevicesPage(),
              ),
              _ => const LoginPage(),
            },
          ),
        ),
      ),
    );
  }
}
