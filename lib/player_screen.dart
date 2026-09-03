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

  final Map<String, String> _headers = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _resolveAndPlay();
  }

  Future<void> _resolveAndPlay() async {
    String? streamUrl;

    // مسارات سينمانا الرسمية للحصول على روابط البث الموقعة ديناميكياً
    final List<String> endpoints = [
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(Uri.parse(endpoint), headers: _headers);

        if (response.statusCode == 200) {
          final dynamic data = json.decode(response.body);

          List candidates = [];
          if (data is List) {
            candidates = data;
          } else if (data is Map) {
            if (data['files'] is List) candidates = data['files'];
            else if (data['videos'] is List) candidates = data['videos'];
            else if (data['data'] is List) candidates = data['data'];
            else if (data['items'] is List) candidates = data['items'];
            else candidates = [data];
          }

          for (var item in candidates) {
            if (item is Map) {
              // سحب الوصف والعنوان
              _movieTitle ??= item['ar_title'] ?? item['en_title'];
              _movieDescription ??= item['ar_content'] ?? item['en_content'];

              // استخراج الرابط الموقّع الفعلي
              String? url = item['videoUrl'] ??
                  item['fileUrl'] ??
                  item['containerUrl'] ??
                  item['streamUrl'] ??
                  item['url'];

              if (url != null && url.startsWith('http')) {
                streamUrl = url;
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error querying $endpoint: $e');
      }

      if (streamUrl != null && streamUrl.isNotEmpty) break;
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر استخراج رابط البث الرسمي لهذا الفيلم من السيرفر.';
        });
      }
      return;
    }

    // تحويل الترويسة من تنزيل إلى عرض مباشر
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

    // بدء تشغيل الفيديو بالترويسات
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {
          'User-Agent': 'Cinemana/3.0.0 (Android)',
          'Referer': 'https://cinemana.shabakaty.com/',
        },
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
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'فشل تحميل مشغل الفيديو.\nتأكد من الاتصال بشبكة إيرثلنك/شبكتي.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ أثناء تهيئة المشغل: $e';
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
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
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
