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
  String? _debugUrl;

  final Map<String, String> _networkHeaders = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _resolveAndStartStream();
  }

  Future<void> _resolveAndStartStream() async {
    String? finalStreamUrl;
    String realVideoNb = widget.videoId;

    // 1. فحص ما إذا كان المعرف هو Post ID واستخراج الـ videoNb الحقيقي
    try {
      final postUrl = Uri.parse(
          'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}');
      final postRes = await http.get(postUrl, headers: _networkHeaders);

      if (postRes.statusCode == 200) {
        final decoded = json.decode(postRes.body);
        List videos = [];
        if (decoded is List) {
          videos = decoded;
        } else if (decoded is Map && decoded['items'] is List) {
          videos = decoded['items'];
        }

        if (videos.isNotEmpty) {
          final firstItem = videos[0];
          if (firstItem is Map) {
            _movieTitle ??= firstItem['ar_title'] ?? firstItem['en_title'];
            _movieDescription ??= firstItem['ar_content'] ?? firstItem['en_content'];
            if (firstItem['nb'] != null) {
              realVideoNb = firstItem['nb'].toString();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting post videos: $e');
    }

    // 2. طلب سيرفرات الفيديو بالمعرف الداخلي videoNb
    final serverUrls = [
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/$realVideoNb',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/$realVideoNb',
    ];

    for (final sUrl in serverUrls) {
      try {
        final res = await http.get(Uri.parse(sUrl), headers: _networkHeaders);
        if (res.statusCode == 200) {
          final dynamic data = json.decode(res.body);
          List items = [];
          if (data is List) {
            items = data;
          } else if (data is Map) {
            if (data['files'] is List) items = data['files'];
            else if (data['videos'] is List) items = data['videos'];
            else items = [data];
          }

          for (var item in items) {
            if (item is Map) {
              _movieTitle ??= item['ar_title'] ?? item['en_title'];
              _movieDescription ??= item['ar_content'] ?? item['en_content'];

              // استخراج الرابط المباشر من السيرفر
              final url = item['videoUrl'] ??
                  item['containerUrl'] ??
                  item['fileUrl'] ??
                  item['streamUrl'];

              if (url != null && url.toString().startsWith('http')) {
                finalStreamUrl = url.toString();
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to query $sUrl: $e');
      }

      if (finalStreamUrl != null) break;
    }

    if (finalStreamUrl == null || finalStreamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'لم يعثر السيرفر على رابط صالح لـ ID: $realVideoNb.\nتأكد من توفر الفيلم على شبكتي.';
        });
      }
      return;
    }

    // 3. ضبط المعامل لـ inline
    if (finalStreamUrl.contains('response-content-disposition=attachment')) {
      finalStreamUrl = finalStreamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!finalStreamUrl.contains('response-content-disposition=')) {
      final sep = finalStreamUrl.contains('?') ? '&' : '?';
      finalStreamUrl = '$finalStreamUrl${sep}response-content-disposition=inline';
    }

    _debugUrl = finalStreamUrl;

    // 4. تشغيل الفيديو
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalStreamUrl),
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
      _errorMessage = 'خطأ مشغل الفيديو: $e\nالرابط: $_debugUrl';
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
