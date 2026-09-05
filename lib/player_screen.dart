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
  String _statusText = 'جاري إرسال طلب التجهيز للسيرفر...';
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  // الرابط العام المباشر من localhost.run
  static const String serverBaseUrl = 'https://9518c92e23b550.lhr.life
';

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    _requestAndStartStreaming();
  }

  Future<void> _requestAndStartStreaming() async {
    final postId = (widget.movieData['nb'] ?? widget.movieData['id'] ?? '').toString();

    if (postId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'معرف الفيلم غير متوفر.';
      });
      return;
    }

    try {
      // 1. إرسال طلب المعالجة للسيرفر
      final uri = Uri.parse('$serverBaseUrl/play-hls?postId=$postId&res=240p');
      final res = await http.get(uri);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final String streamUrl = data['streamUrl'];

        setState(() {
          _statusText = 'جاري تهيئة أولى أجزاء البث...';
        });

        // انتظار زمني قصير لضمان رفع القطع الأولى إلى السحابة
        await Future.delayed(const Duration(seconds: 8));

        await _initPlayer(streamUrl);
      } else {
        throw 'استجابة السيرفر: ${res.statusCode}';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر الاتصال بالسيرفر:\n$e';
        });
      }
    }
  }

  Future<void> _initPlayer(String streamUrl) async {
    try {
      setState(() {
        _statusText = 'جاري فتح الفيديو...';
      });

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
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
                'جاري تحميل أجزاء إضافية من البث... يرجى الانتظار ثوانٍ ($error)',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'فشل تشغيل تدفق HLS: $e';
        });
      }
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SelectableText(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
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
