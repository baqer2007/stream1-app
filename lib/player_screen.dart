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
  String _rawResponseDump = '';

  final Map<String, String> _networkHeaders = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _fetchStreamData();
  }

  // استخراج الروابط بالبحث الذكي داخل أي خريطة أو قائمة
  String? _searchForStream(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      // فحص الحقول المعتادة
      final keys = [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'directUrl',
        'url',
        'stream_url',
        'streamUrl'
      ];
      for (var k in keys) {
        if (data[k] != null) {
          final val = data[k].toString().trim();
          if (val.startsWith('http')) return val;
        }
      }

      // البحث في العناصر الداخلية
      for (var val in data.values) {
        if (val is Map || val is List) {
          final res = _searchForStream(val);
          if (res != null) return res;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        final res = _searchForStream(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _fetchStreamData() async {
    String? finalStreamUrl;
    String inspectedApi = '';

    // نقاط نهاية سينمانا لجلب الملفات وروابط المشاهدة
    final endpoints = [
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
    ];

    for (final api in endpoints) {
      inspectedApi = api;
      try {
        final res = await http.get(Uri.parse(api), headers: _networkHeaders);
        _rawResponseDump = '[$api]\nكود الاستجابة: ${res.statusCode}\nالمحتوى:\n${res.body.length > 500 ? res.body.substring(0, 500) + '...' : res.body}';

        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final decoded = json.decode(res.body);
          finalStreamUrl = _searchForStream(decoded);

          if (finalStreamUrl != null && finalStreamUrl.isNotEmpty) {
            break;
          }
        }
      } catch (e) {
        _rawResponseDump = 'خطأ اتصال بالمسار $api: $e';
      }
    }

    if (finalStreamUrl == null || finalStreamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _rawResponseDump;
        });
      }
      return;
    }

    // تعديل معامل التنزيل إلى بث مباشر
    if (finalStreamUrl.contains('response-content-disposition=attachment')) {
      finalStreamUrl = finalStreamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!finalStreamUrl.contains('response-content-disposition=')) {
      final sep = finalStreamUrl.contains('?') ? '&' : '?';
      finalStreamUrl = '$finalStreamUrl${sep}response-content-disposition=inline';
    }

    // تشغيل الفيديو عبر المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalStreamUrl),
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
                'تعذر استلام البث:\n$error',
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
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'بيانات الخادم المستلمة:',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
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
