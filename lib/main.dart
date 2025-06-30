import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDfuAPKb2WdK2D4jUhVPFNajNacsv0B_PA",
        authDomain: "find-74ab9.firebaseapp.com",
        projectId: "find-74ab9",
        storageBucket:
            "find-74ab9.appspot.com", // Fixed typo: .app to .appspot.com
        messagingSenderId: "589831949774",
        appId: "1:589831949774:web:81f391fe1859731177ef9f",
        measurementId: "G-NE3ECSQV54",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        // '/home': (context) => const HomePage(), // Add if HomePage is defined
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Responsive logo sizing
    final width = MediaQuery.of(context).size.width;
    double logoHeight = width < 600 ? 180 : 260;
    return Scaffold(
      backgroundColor: const Color(0xFF000B8C),
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          height: logoHeight,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
