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
    _movieDescription = widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    _resolveStream();
  }

  String? _extractStreamUrl(dynamic obj) {
    if (obj == null) return null;
    if (obj is Map) {
      for (final key in [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'directUrl',
        'streamUrl',
        'url'
      ]) {
        if (obj[key] != null) {
          final s = obj[key].toString().trim();
          if (s.startsWith('http') && (s.contains('.mp4') || s.contains('vascin') || s.contains('cndw1'))) {
            return s;
          }
        }
      }
      for (var val in obj.values) {
        final res = _extractStreamUrl(val);
        if (res != null) return res;
      }
    } else if (obj is List) {
      for (var item in obj) {
        final res = _extractStreamUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _resolveStream() async {
    // 1. فحص كائن الفيلم الممرر مباشرة من شاشة البحث
    String? foundUrl = _extractStreamUrl(widget.movieData);

    // 2. إذا لم يكن الرابط في الكائن مباشرة، نبحث عن المعرفات المحتملة
    if (foundUrl == null) {
      final possibleIds = [
        widget.movieData['videoNb'],
        widget.movieData['video_nb'],
        widget.movieData['targetNb'],
        widget.movieData['nb'],
        widget.movieData['id'],
      ].where((id) => id != null && id.toString().isNotEmpty).toList();

      for (var rawId in possibleIds) {
        final currentId = rawId.toString();
        final endpoints = [
          'https://cinemana.shabakaty.com/api/android/allVideoInfo/id/$currentId',
          'https://cinemana.shabakaty.com/api/android/videoFiles/id/$currentId',
          'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/$currentId/level/0',
        ];

        for (var ep in endpoints) {
          try {
            final res = await http.get(Uri.parse(ep), headers: _browserHeaders);
            if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
              final decoded = json.decode(res.body);
              foundUrl = _extractStreamUrl(decoded);
              if (foundUrl != null) break;
            }
          } catch (_) {}
        }
        if (foundUrl != null) break;
      }
    }

    if (foundUrl == null || foundUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'محتوى كائن الفيلم القادم من البحث (لم يتم العثور على رابط مباشر):\n\n' +
              const JsonEncoder.withIndent('  ').convert(widget.movieData);
        });
      }
      return;
    }

    String streamUrl = foundUrl;

    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
          'response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    // تتبع تحويل 302
    try {
      final headRes = await http.head(Uri.parse(streamUrl), headers: _browserHeaders);
      if (headRes.statusCode == 302 && headRes.headers['location'] != null) {
        streamUrl = headRes.headers['location']!;
      }
    } catch (_) {}

    // تهيئة وتشغيل المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
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
      _errorMessage = 'خطأ مشغل الفيديو: $e\n\nالرابط المستخرج:\n$streamUrl';
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
                            fontSize: 11,
                            fontFamily: 'monospace'),
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
