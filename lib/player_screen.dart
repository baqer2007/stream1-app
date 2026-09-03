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

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _initializeContent();
  }

  Future<void> _initializeContent() async {
    // 1. جلب خوادم وسائط الفيلم من الـ API
    final apiUrl = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}');

    String? targetStreamUrl;

    try {
      final res = await http.get(apiUrl, headers: {
        'User-Agent': 'Cinemana/3.0.0 (Android)',
        'Accept': 'application/json',
      });

      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        if (data.isNotEmpty) {
          final item = data[0];
          _movieTitle = item['ar_title'] ?? item['en_title'] ?? _movieTitle;
          _movieDescription = item['ar_content'] ?? item['en_content'];

          // محاولة استخراج الرابط المباشر أو اسم الملف
          if (item['videoUrl'] != null && item['videoUrl'].toString().isNotEmpty) {
            targetStreamUrl = item['videoUrl'];
          } else if (item['fileFile'] != null) {
            // استخدام رابط S3 المباشر للفيلم مع توقيع البث
            final fileName = item['fileFile'];
            targetStreamUrl =
                'https://cndw1.shabakaty.com/vascin24-mp4/$fileName?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';
          }
        }
      }
    } catch (e) {
      debugPrint('API Error: $e');
    }

    if (targetStreamUrl == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذر العثور على مصدر بث لهذا العمل.';
      });
      return;
    }

    // 2. تهيئة مشغل الفيديو
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(targetStreamUrl),
      httpHeaders: {
        'User-Agent': 'Cinemana/3.0.0 (Android)',
        'Referer': 'https://cinemana.shabakaty.com/',
      },
    );

    try {
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
            child: Text(
              'تعذر تشغيل الفيديو، تأكد من الاتصال بشبكة تدعم الخدمة.',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ أثناء تهيئة المشغل.';
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
        title: Text(_movieTitle ?? 'المشغل'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center),
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
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: Chewie(controller: _chewieController!),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _movieTitle ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _movieDescription ?? 'لا يوجد وصف متوفر.',
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
