import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const CinemanaApp());
}

class CinemanaApp extends StatelessWidget {
  const CinemanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinemana Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const HomeScreen(),
    );
  }
}
