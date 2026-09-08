import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'services/storage_service.dart';
import 'services/stream_service.dart';
import 'screens/main_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await StorageService.init();

  final devId = StorageService.get('device_id', defaultValue: 'dev_${DateTime.now().millisecondsSinceEpoch}');
  StorageService.put('device_id', devId);
  StreamService.sendHeartbeat(devId);
  Timer.periodic(const Duration(minutes: 4), (_) => StreamService.sendHeartbeat(devId));

  runApp(const OnebrTvApp());
}

class OnebrTvApp extends StatelessWidget {
  const OnebrTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ONEBR TV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        primaryColor: const Color(0xFFE50914),
        cardColor: const Color(0xFF111726),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF111726),
          secondary: Color(0xFF00F0FF),
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}
