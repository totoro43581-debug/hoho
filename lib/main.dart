import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ 수정1차: Firebase 옵션 로그 출력용

import 'firebase_options.dart';
import 'screen/login/login_screen_web.dart';
import 'screen/home/home_screen_web.dart';
import 'screen/reception/reception_register_screen_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ 수정1차: 집/회사/노트북이 "같은 Firebase 프로젝트"를 보는지 즉시 확정하는 로그
  // - 3대 기기에서 이 3줄이 100% 동일해야 "같은 DB"입니다.
  // ignore: avoid_print
  print('FIREBASE_PROJECT_ID = ${FirebaseFirestore.instance.app.options.projectId}');
  // ignore: avoid_print
  print('FIREBASE_APP_ID     = ${FirebaseFirestore.instance.app.options.appId}');
  // ignore: avoid_print
  print('FIREBASE_API_KEY    = ${FirebaseFirestore.instance.app.options.apiKey}');

  // 로그인 세션 유지 설정
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hoho ERP',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',

        // ============================================================
        // 수정1차(누적): 팝업/다이얼로그 배경을 항상 White로 고정(에러 없는 안전 버전)
        // ============================================================
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.light,
        ).copyWith(
          surface: Colors.white,
        ),

        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
        ),

        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
        ),

        // DropdownMenu(Material3) 계열
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.white),
          ),
        ),
      ),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [RouteTrackingObserver()],

      // ✅ 로그인 분기 로직
      home: const AuthGate(),

      // ✅ 명시적인 라우트 등록
      routes: {
        '/home': (context) => const HomeScreenWeb(),
        '/reception-register': (context) => ReceptionRegisterScreenWeb(
          onCancel: () => Navigator.of(context).pushReplacementNamed('/home'),
        ),
      },
    );
  }
}

// ✅ 로그인 여부 확인 위젯
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: FirebaseAuth.instance.authStateChanges().first,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreenWeb();
        } else {
          return const RouteRestorer(); // ✅ 로그인 상태면 복원 시도
        }
      },
    );
  }
}

// ✅ 마지막 경로 복원 위젯
class RouteRestorer extends StatefulWidget {
  const RouteRestorer({super.key});

  @override
  State<RouteRestorer> createState() => _RouteRestorerState();
}

class _RouteRestorerState extends State<RouteRestorer> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _restoreLastRoute();
  }

  Future<void> _restoreLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString('last_route') ?? '/home';

    setState(() {
      switch (route) {
        case '/home':
          _screen = const HomeScreenWeb();
          break;
        case '/reception-register':
          _screen = ReceptionRegisterScreenWeb(
            onCancel: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreenWeb()),
              );
            },
          );
          break;
        default:
          _screen = const HomeScreenWeb(); // fallback
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _screen ??
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
  }
}

// ✅ 현재 라우트 기억용
class RouteTrackingObserver extends NavigatorObserver {
  void _saveRoute(String? name) async {
    if (name == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_route', name);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    // 🔴 push가 발생하면 무조건 콘솔에 출력 (원인 파일 찾기용)
    // ignore: avoid_print
    print('🔴 didPush: ${route.settings.name ?? route}');
    _saveRoute(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _saveRoute(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    // ignore: avoid_print
    print('🟠 didPop: ${route.settings.name ?? route}');
    super.didPop(route, previousRoute);
  }
}
