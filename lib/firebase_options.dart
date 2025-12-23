// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'This platform is not supported for Firebase configuration.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD4Q2VBUlcf1Lq65sh8LLI9687TTOUFDzE',
    authDomain: 'hoapp-9b261.firebaseapp.com',
    projectId: 'hoapp-9b261',
    storageBucket: 'hoapp-9b261.firebasestorage.app',
    messagingSenderId: '214231682794',
    appId: '1:214231682794:web:8dd1ea493c2fd9f7f39193',
    measurementId: 'G-HE90HZWY9W',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD4Q2VBUlcf1Lq65sh8LLI9687TTOUFDzE',
    appId: '1:214231682794:web:8dd1ea493c2fd9f7f39193',
    messagingSenderId: '214231682794',
    projectId: 'hoapp-9b261',
    storageBucket: 'hoapp-9b261.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD4Q2VBUlcf1Lq65sh8LLI9687TTOUFDzE',
    appId: '1:214231682794:web:8dd1ea493c2fd9f7f39193',
    messagingSenderId: '214231682794',
    projectId: 'hoapp-9b261',
    storageBucket: 'hoapp-9b261.firebasestorage.app',
    iosBundleId: 'com.example.hoapp', // ⚠️ 실제 등록된 iOS Bundle ID로 수정 필요
  );
}
