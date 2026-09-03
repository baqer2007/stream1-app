import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  final Map<String, String> _networkHeaders = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Origin': 'https://cinemana.shabakaty.com',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _setupVideo();
  }

  // البحث في كائن الاستجابة عن أي رابط كامل موقّع أو رابط CDN
  String? _scanForUrl(dynamic obj) {
    if (obj == null) return null;

    if (obj is Map) {
      for (var k in ['videoUrl', 'containerUrl', 'fileUrl', 'url', 'directUrl', 'streamUrl']) {
        if (obj[k] != null) {
          final s = obj[k].toString().trim();
          if (s.startsWith('http') && s.contains('.mp4')) {
            return s;
          }
        }
      }
      for (var v in obj.values) {
        final found = _scanForUrl(v);
        if (found != null) return found;
      }
    } else if (obj is List) {
      for (var item in obj) {
        final found = _scanForUrl(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _setupVideo() async {
    String? streamUrl;
    StringBuffer logs = StringBuffer();

    // 1. المسار الرسمي لجلب التفاصيل
    final videoInfoUrl = 'https://cinemana.shabakaty.com/api/android/allVideoInfo/id/${widget.videoId}';

    try {
      final res = await http.get(Uri.parse(videoInfoUrl), headers: {
        'User-Agent': 'Cinemana/3.0.0 (Android)',
        'Referer': 'https://cinemana.shabakaty.com/',
        'Accept': 'application/json',
      });

      logs.writeln('طلب allVideoInfo: ${res.statusCode}');

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final dynamic data = json.decode(res.body);

        if (data is Map) {
          _movieTitle ??= data['ar_title'] ?? data['en_title'];
          _movieDescription ??= data['ar_content'] ?? data['en_content'];
        }

        streamUrl = _scanForUrl(data);
      }
    } catch (e) {
      logs.writeln('فشل في allVideoInfo: $e');
    }

    // 2. فحص مسار الملفات البديل إن لم يظهر الرابط
    if (streamUrl == null) {
      final candidateEndpoints = [
        'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
        'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}/level/0',
      ];

      for (var ep in candidateEndpoints) {
        try {
          final r = await http.get(Uri.parse(ep), headers: _networkHeaders);
          logs.writeln('[$ep] => ${r.statusCode}');
          if (r.statusCode == 200 && r.body.isNotEmpty) {
            final decoded = json.decode(r.body);
            streamUrl = _scanForUrl(decoded);
            if (streamUrl != null) break;
          }
        } catch (e) {
          logs.writeln('خطأ $ep: $e');
        }
      }
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم نتمكن من الحصول على رابط البث المباشر.\n\nالسجلات:\n$logs';
        });
      }
      return;
    }

    // تعديل الترويسة لتعمل بوضع inline للبث المباشر بدلاً من attachment
    String finalUrl = streamUrl;
    if (finalUrl.contains('response-content-disposition=attachment')) {
      finalUrl = finalUrl.replaceAll('response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    // حل الـ Redirect (302) المباشر إلى cndw1 إن وُجد
    try {
      final headRes = await http.head(Uri.parse(finalUrl), headers: _networkHeaders);
      if (headRes.statusCode == 302 && headRes.headers['location'] != null) {
        finalUrl = headRes.headers['location']!;
      }
    } catch (_) {}

    // 3. تهيئة وتشغيل المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalUrl),
        httpHeaders: _networkHeaders,
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
      _errorMessage = 'خطأ مشغل الفيديو: $e\n\nالرابط المستخرج:\n$finalUrl';
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
                    padding: const EdgeInsets.all(20.0),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
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
