import 'package:flutter/material.dart';
import 'player_screen.dart';

void main() {
  runApp(const CinemanaApp());
}

class CinemanaApp extends StatelessWidget {
  const CinemanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinemana Stream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
      ),
      home: const CinemanaPlayerScreen(videoId: '99956'),
    );
  }
}
