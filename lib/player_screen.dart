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
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _initPlayer();
  }

  // استخراج رابط التشغيل
  String? _findStreamUrl(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      for (var k in ['videoUrl', 'containerUrl', 'fileUrl', 'url', 'directUrl', 'streamUrl']) {
        if (data[k] != null && data[k].toString().trim().startsWith('http')) {
          return data[k].toString().trim();
        }
      }
      for (var val in data.values) {
        if (val is Map || val is List) {
          final res = _findStreamUrl(val);
          if (res != null) return res;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        final res = _findStreamUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _initPlayer() async {
    String? streamUrl;
    String realVideoNb = widget.videoId;

    // 1. قراءة الرد الأولي لاستخراج nb الخاص بالفيديو وبيانات العنوان والوصف
    try {
      final initialUrl = Uri.parse(
          'https://cinemana.shabakaty.com/api/android/video/servers?videoNb=${widget.videoId}&level=0');
      final initRes = await http.get(initialUrl, headers: _networkHeaders);

      if (initRes.statusCode == 200 && initRes.body.isNotEmpty) {
        final decoded = json.decode(initRes.body);
        if (decoded is List && decoded.isNotEmpty && decoded[0] is Map) {
          final item = decoded[0];
          _movieTitle = item['ar_title'] ?? item['en_title'] ?? _movieTitle;
          _movieDescription = item['ar_content'] ?? item['en_content'];
          if (item['nb'] != null) {
            realVideoNb = item['nb'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Initial servers query error: $e');
    }

    // 2. طلب روابط البث الموقعة باستخدام المعرف الدقيق
    final candidateEndpoints = [
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/$realVideoNb/level/0',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/$realVideoNb',
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/$realVideoNb',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/$realVideoNb/level/0',
    ];

    for (final ep in candidateEndpoints) {
      try {
        final res = await http.get(Uri.parse(ep), headers: _networkHeaders);
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final data = json.decode(res.body);
          streamUrl = _findStreamUrl(data);
          if (streamUrl != null && streamUrl.isNotEmpty) break;
        }
      } catch (e) {
        debugPrint('Endpoint error $ep: $e');
      }
    }

    if (streamUrl == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'تعذر الحصول على رابط بث موقّع لهذا الفيلم (ID: $realVideoNb).\nتأكد من دعم مزود الخدمة للعمل.';
        });
      }
      return;
    }

    // تحويل الرابط إلى وضع العرض المباشر (inline)
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

    // 3. تهيئة وتشغيل المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
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
      _errorMessage = 'خطأ أثناء تهيئة المشغل:\n$e';
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
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
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
