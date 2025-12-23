// lib/app.dart
import 'package:flutter/material.dart';
import 'screen/reception/reception_register_screen_web.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hoho',
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          return ReceptionRegisterScreenWeb(
            // 샘플 onCancel: 뒤로가기 또는 안내
            onCancel: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('닫기 동작 예시입니다.')),
                );
              }
            },
          );
        },
      ),
    );
  }
}
