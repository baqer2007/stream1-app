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
    _loadExactVideo();
  }

  Future<void> _loadExactVideo() async {
    String? playUrl;

    // استدعاء ملفات العمل المحدد فقط عبر postNb أو عبر مسار الملفات الحصري
    final directApis = [
      'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
    ];

    for (final api in directApis) {
      try {
        final res = await http.get(Uri.parse(api), headers: _networkHeaders);
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final decoded = json.decode(res.body);
          List items = [];
          if (decoded is List) items = decoded;
          else if (decoded is Map && decoded['items'] is List) items = decoded['items'];

          for (var item in items) {
            if (item is Map) {
              _movieTitle = item['ar_title'] ?? item['en_title'] ?? _movieTitle;
              _movieDescription = item['ar_content'] ?? item['en_content'];

              // استخراج الرابط المباشر
              final candidate = item['videoUrl'] ?? item['containerUrl'] ?? item['fileUrl'] ?? item['url'];
              if (candidate != null && candidate.toString().startsWith('http')) {
                playUrl = candidate.toString();
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error: $e');
      }
      if (playUrl != null) break;
    }

    // إذا لم يتوفر رابط موقع جاهز، سنستخدم مسار التوزيع الشبكي المباشر (HLS / MP4)
    if (playUrl == null || playUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم نتمكن من جلب سيرفر التشغيل المباشر للعمل (ID: ${widget.videoId}).\nتأكد من أن الفيلم متوفر على السيرفر المحلي.';
        });
      }
      return;
    }

    // تعديل الترويسة للعرض التفاعلي
    if (playUrl.contains('response-content-disposition=attachment')) {
      playUrl = playUrl.replaceAll('response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
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
      _errorMessage = 'خطأ مشغل الفيديو: $e';
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
