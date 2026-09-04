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

  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Origin': 'https://cinemana.shabakaty.com',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    _playTargetMovie();
  }

  // استخراج رابط الجودة الأنسب (720p -> 1080p -> 480p -> أي رابط متاح)
  String? _extractBestVideoUrl(dynamic jsonList) {
    if (jsonList is! List || jsonList.isEmpty) return null;

    final preferredResolutions = ['720p', '1080p', '480p', '360p', '240p'];

    for (var targetRes in preferredResolutions) {
      for (var item in jsonList) {
        if (item is Map) {
          final res = (item['resolution'] ?? item['name'] ?? '').toString();
          final url = item['videoUrl']?.toString();
          if (res.contains(targetRes) && url != null && url.isNotEmpty) {
            return url;
          }
        }
      }
    }

    for (var item in jsonList) {
      if (item is Map && item['videoUrl'] != null) {
        final s = item['videoUrl'].toString();
        if (s.startsWith('http')) return s;
      }
    }
    return null;
  }

  Future<void> _playTargetMovie() async {
    final postNb = (widget.movieData['nb'] ?? widget.movieData['id'] ?? '').toString();
    String? rawStreamUrl;
    String? videoNb;

    // 1. جلب videoNb التابع للفيلم المحدد باستخدام مسار allVideo المعتمد
    if (postNb.isNotEmpty) {
      try {
        final uri = Uri.parse('https://cinemana.shabakaty.com/api/android/allVideo/page/0?postNb=$postNb');
        final res = await http.get(uri, headers: _headers);

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
          final decoded = json.decode(res.body);
          if (decoded is List && decoded.isNotEmpty) {
            final firstVideo = decoded.first;
            if (firstVideo is Map && firstVideo['nb'] != null) {
              videoNb = firstVideo['nb'].toString();
            }
          } else if (decoded is Map && decoded['videos'] is List && (decoded['videos'] as List).isNotEmpty) {
            final firstVideo = decoded['videos'][0];
            if (firstVideo is Map && firstVideo['nb'] != null) {
              videoNb = firstVideo['nb'].toString();
            }
          }
        }
      } catch (_) {}
    }

    // 2. إذا لم يرجع allVideo نتيجة، نعتمد على معرف المنشور مباشرة
    final targetId = videoNb ?? postNb;

    // 3. جلب مصفوفة الجودات الحقيقية لهذا الفيلم تحديداً
    if (targetId.isNotEmpty) {
      try {
        final transcodeUrl =
            'https://cinemana.shabakaty.com/api/android/transcoddedFiles/id/$targetId';
        final res = await http.get(Uri.parse(transcodeUrl), headers: _headers);

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
          final decoded = json.decode(res.body);
          rawStreamUrl = _extractBestVideoUrl(decoded);
        }
      } catch (_) {}
    }

    if (rawStreamUrl == null || rawStreamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يتم العثور على رابط بث لهذا المحتوى (ID: $targetId).';
        });
      }
      return;
    }

    // الرابط الموقّع الأصلي دون أي تعديل في نص الرابط
    final String finalStreamUrl = rawStreamUrl.trim();

    // 4. تهيئة المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalStreamUrl),
        httpHeaders: _headers,
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
      _errorMessage = 'خطأ مشغل الفيديو: $e\n\nالرابط:\n$finalStreamUrl';
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
                    child: SelectableText(
                      _errorMessage!,
                      style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontFamily: 'monospace'),
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
