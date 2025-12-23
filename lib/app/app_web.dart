// lib/app/app_web.dart
import 'package:flutter/material.dart';
import '../screen/login/login_screen_web.dart'; // 웹용 로그인 화면

class AppWeb extends StatelessWidget {
  const AppWeb({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hoho 웹',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginScreenWeb(), // 웹 로그인 첫 화면
    );
  }
}
