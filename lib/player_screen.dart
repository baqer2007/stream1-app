import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class CinemanaPlayerScreen extends StatefulWidget {
  final String videoId;

  const CinemanaPlayerScreen({super.key, required this.videoId});

  @override
  State<CinemanaPlayerScreen> createState() => _CinemanaPlayerScreenState();
}

class _CinemanaPlayerScreenState extends State<CinemanaPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  
  bool _isLoading = true;
  String? _movieTitle;
  String? _movieDescription;

  // رابط البث الموقّع المباشر مع ترويسة inline
  final String _streamUrl =
      'https://cndw1.shabakaty.com/vascin24-mp4/32256768-08AF-417D-A717-813547AF780C_video.mp4?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';

  @override
  void initState() {
    super.initState();
    _setupMedia();
  }

  Future<void> _setupMedia() async {
    // 1. جلب البيانات الوصفية من سينمانا
    final apiUrl = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}');

    try {
      final response = await http.get(apiUrl, headers: {
        'User-Agent': 'Cinemana/3.0.0 (Android)',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final item = data[0];
          setState(() {
            _movieTitle = item['ar_title'] ?? item['en_title'];
            _movieDescription = item['ar_content'] ?? item['en_content'];
          });
        }
      }
    } catch (e) {
      debugPrint('Metadata fetching error: $e');
    }

    // 2. تهيئة مشغل الفيديو مع ترويسات سينمانا
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(_streamUrl),
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
        errorBuilder: (context, errorMessage) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'تعذر تشغيل الفيديو.\nتأكد من الاتصال بشبكة تدعم الخدمة (شبكتي / إيرثلنك).',
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Video player initialization error: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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
          ? const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
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
                      child: _chewieController != null
                          ? Chewie(controller: _chewieController!)
                          : const Center(
                              child: Text(
                                'خطأ أثناء تهيئة المشغل',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
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
                        const SizedBox(height: 10),
                        Text(
                          _movieDescription ?? 'لا يوجد وصف متاح.',
                          style: const TextStyle(
                            fontSize: 14,
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
