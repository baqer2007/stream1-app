import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CinemanaPlayerScreen extends StatefulWidget {
  final String videoId;
  final String? initialTitle;

  const CinemanaPlayerScreen({
    super.key,
    required this.videoId,
    this.initialTitle,
  });

  @override
  State<CinemanaPlayerScreen> createState() => _CinemanaPlayerScreenState();
}

class _CinemanaPlayerScreenState extends State<CinemanaPlayerScreen> {
  bool _isLoading = true;
  String _rawJsonText = '';

  final Map<String, String> _networkHeaders = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _fetchRawData();
  }

  Future<void> _fetchRawData() async {
    final targetUrl = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/video/servers?videoNb=${widget.videoId}&level=0');

    try {
      final res = await http.get(targetUrl, headers: _networkHeaders);
      if (res.statusCode == 200) {
        final parsed = json.decode(res.body);
        _rawJsonText = const JsonEncoder.withIndent('  ').convert(parsed);
      } else {
        _rawJsonText = 'رمز الاستجابة: ${res.statusCode}\nالمحتوى: ${res.body}';
      }
    } catch (e) {
      _rawJsonText = 'خطأ اتصال: $e';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: Text(widget.initialTitle ?? 'فحص السيرفر'),
        backgroundColor: const Color(0xFF111827),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: SingleChildScrollView(
                child: SelectableText(
                  _rawJsonText,
                  style: const TextStyle(
                    color: Colors.lightGreenAccent,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
    );
  }
}
