import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:router_control/app/auth_cubit.dart';
import 'package:router_control/app/login_page.dart';
import 'package:router_control/app/theme.dart';
import 'package:router_control/router/router_repository.dart';

void main() {
  testWidgets('LoginPage lays out on a phone in RTL', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repository = RouterRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: BlocProvider(
          create: (_) => AuthCubit(repository),
          child: const LoginPage(),
        ),
      ),
    );

    expect(find.text('دخول'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
