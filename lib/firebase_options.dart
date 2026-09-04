import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'check you initialised Firebase for your platform.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'check you initialised Firebase for your platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: '1:123456789:web:abcdef',
    messagingSenderId: '123456789',
    projectId: 'agenta-ai-coach',
    authDomain: 'agenta-ai-coach.firebaseapp.com',
    storageBucket: 'agenta-ai-coach.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBTKSqd38JhQj4mBEYH8YQ3FzY4vlUjtBA',
    appId: '1:256855734037:android:15f6a13398db82bad39b1c',
    messagingSenderId: '256855734037',
    projectId: 'agenta-d6ab4',
    authDomain: 'agenta-d6ab4.firebaseapp.com',
    storageBucket: 'agenta-d6ab4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:123456789:ios:abcdef',
    messagingSenderId: '123456789',
    projectId: 'agenta-ai-coach',
    authDomain: 'agenta-ai-coach.firebaseapp.com',
    storageBucket: 'agenta-ai-coach.appspot.com',
    iosClientId: '123456789-abcdef.apps.googleusercontent.com',
    iosBundleId: 'com.example.aiproject',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:123456789:macos:abcdef',
    messagingSenderId: '123456789',
    projectId: 'agenta-ai-coach',
    authDomain: 'agenta-ai-coach.firebaseapp.com',
    storageBucket: 'agenta-ai-coach.appspot.com',
    iosClientId: '123456789-abcdef.apps.googleusercontent.com',
    iosBundleId: 'com.example.aiproject',
  );
}