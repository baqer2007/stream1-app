import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class CinemanaPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final String? initialTitle;

  const CinemanaPlayerScreen({
    super.key,
    required this.movieData,
    this.initialTitle,
  });

  @override
  State<CinemanaPlayerScreen> createState() => _CinemanaPlayerScreenState();
}

class _CinemanaPlayerScreenState extends State<CinemanaPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  final Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Origin': 'https://cinemana.shabakaty.com',
    'Accept': 'application/json, text/plain, */*',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    _startResolution();
  }

  String? _scanForStreamUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      for (final key in [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'directUrl',
        'streamUrl',
        'url'
      ]) {
        if (data[key] != null) {
          final s = data[key].toString().trim();
          if (s.startsWith('http') &&
              (s.contains('.mp4') || s.contains('vascin') || s.contains('cndw1'))) {
            return s;
          }
        }
      }
      for (var val in data.values) {
        final res = _scanForStreamUrl(val);
        if (res != null) return res;
      }
    } else if (data is List) {
      for (var item in data) {
        final res = _scanForStreamUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  String? _extractRealVideoId(dynamic data, String postNb) {
    if (data == null) return null;

    if (data is List && data.isNotEmpty) {
      for (var item in data) {
        if (item is Map) {
          final candidate = item['nb'] ?? item['videoNb'] ?? item['id'];
          if (candidate != null &&
              candidate.toString() != postNb &&
              candidate.toString() != '3130532') {
            return candidate.toString();
          }
        }
      }
      if (data.first is Map) {
        final firstNb = data.first['nb'] ?? data.first['videoNb'] ?? data.first['id'];
        if (firstNb != null && firstNb.toString() != postNb) {
          return firstNb.toString();
        }
      }
    } else if (data is Map) {
      for (var k in ['videos', 'items', 'list']) {
        if (data[k] is List) {
          final res = _extractRealVideoId(data[k], postNb);
          if (res != null) return res;
        }
      }
    }
    return null;
  }

  Future<void> _startResolution() async {
    final postNb = (widget.movieData['nb'] ?? widget.movieData['id'] ?? '').toString();
    String? streamUrl;
    StringBuffer logs = StringBuffer();

    // 1. فحص كائن الفيلم الأساسي
    streamUrl = _scanForStreamUrl(widget.movieData);

    // 2. جلب videoNb التابع للـ postNb
    String? realVideoId;
    if (streamUrl == null && postNb.isNotEmpty) {
      final postEndpoints = [
        'https://cinemana.shabakaty.com/api/android/video/postNb/$postNb',
        'https://cinemana.shabakaty.com/api/android/allVideo/page/0?postNb=$postNb',
        'https://cinemana.shabakaty.com/api/android/postFiles/postNb/$postNb',
      ];

      for (var ep in postEndpoints) {
        try {
          final res = await http.get(Uri.parse(ep), headers: _browserHeaders);
          logs.writeln('$ep => ${res.statusCode}');
          if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
            final decoded = json.decode(res.body);
            streamUrl = _scanForStreamUrl(decoded);
            if (streamUrl != null) break;

            realVideoId = _extractRealVideoId(decoded, postNb);
            if (realVideoId != null) {
              logs.writeln('تم العثور على videoNb حقيقي: $realVideoId');
              break;
            }
          }
        } catch (e) {
          logs.writeln('خطأ $ep: $e');
        }
      }
    }

    // 3. طلب تفاصيل الفيديو بواسطة videoNb وعرض الاستجابة في حال عدم وجود رابط صريح
    final targetVideoId = realVideoId ?? postNb;
    if (streamUrl == null && targetVideoId.isNotEmpty) {
      try {
        final infoUri = Uri.parse(
            'https://cinemana.shabakaty.com/api/android/allVideoInfo/id/$targetVideoId');
        final res = await http.get(infoUri, headers: _browserHeaders);
        logs.writeln('allVideoInfo: ${res.statusCode}');

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
          final decoded = json.decode(res.body);
          streamUrl = _scanForStreamUrl(decoded);

          if (streamUrl == null) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = "استجابة allVideoInfo الناجحة (200 OK):\n\n" +
                    const JsonEncoder.withIndent('  ').convert(decoded);
              });
            }
            return;
          }
        }
      } catch (e) {
        logs.writeln('خطأ allVideoInfo: $e');
      }
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'تعذر الحصول على ملف الفيديو لهذا العمل.\n\nسجل العمليات:\n$logs';
        });
      }
      return;
    }

    String finalStreamUrl = streamUrl;

    if (finalStreamUrl.contains('response-content-disposition=attachment')) {
      finalStreamUrl = finalStreamUrl.replaceAll(
          'response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    try {
      final headRes = await http.head(Uri.parse(finalStreamUrl), headers: _browserHeaders);
      if (headRes.statusCode == 302 && headRes.headers['location'] != null) {
        finalStreamUrl = headRes.headers['location']!;
      }
    } catch (_) {}

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalStreamUrl),
        httpHeaders: _browserHeaders,
      );

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        fullScreenByDefault: false,
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'تعذر البث: $error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ مشغل الفيديو: $e\n\nالرابط المستخرج:\n$finalStreamUrl';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: Text(_movieTitle ?? 'مشغل سينمانا'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _errorMessage!,
                        style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.black,
                        child: AspectRatio(
                          aspectRatio: _videoPlayerController!.value.isInitialized
                              ? _videoPlayerController!.value.aspectRatio
                              : 16 / 9,
                          child: Chewie(controller: _chewieController!),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _movieTitle ?? 'بدون عنوان',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _movieDescription ?? 'لا يوجد وصف متاح.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
