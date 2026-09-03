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
    _fetchServer();
  }

  // استخراج أي رابط فيديو صالح من أي حقل
  String? _parseVideoUrl(dynamic jsonItem) {
    if (jsonItem is! Map) return null;

    final possibleKeys = [
      'videoUrl',
      'containerUrl',
      'fileUrl',
      'url',
      'directUrl',
      'streamUrl',
      'link'
    ];

    for (var k in possibleKeys) {
      if (jsonItem[k] != null) {
        String val = jsonItem[k].toString().trim();
        if (val.startsWith('http')) return val;
      }
    }
    return null;
  }

  Future<void> _fetchServer() async {
    // المسار الناجح برمز 200
    final targetUrl =
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}/level/0';

    String? videoStreamUrl;
    String rawDataDump = '';

    try {
      final res = await http.get(Uri.parse(targetUrl), headers: _networkHeaders);

      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);

        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded[0];
          rawDataDump = const JsonEncoder.withIndent('  ').convert(first);

          _movieTitle ??= first['ar_title'] ?? first['en_title'];
          _movieDescription ??= first['ar_content'] ?? first['en_content'];

          // 1. فحص العنصر الرئيسي
          videoStreamUrl = _parseVideoUrl(first);

          // 2. إذا لم يظهر، فحص مصفوفات السيرفرات الفرعية إن وُجدت
          if (videoStreamUrl == null) {
            for (var val in first.values) {
              if (val is List) {
                for (var sub in val) {
                  videoStreamUrl = _parseVideoUrl(sub);
                  if (videoStreamUrl != null) break;
                }
              }
              if (videoStreamUrl != null) break;
            }
          }
        } else if (decoded is Map) {
          rawDataDump = const JsonEncoder.withIndent('  ').convert(decoded);
          videoStreamUrl = _parseVideoUrl(decoded);
        }
      } else {
        rawDataDump = 'فشل الرد برمز: ${res.statusCode}';
      }
    } catch (e) {
      rawDataDump = 'خطأ أثناء الاتصال: $e';
    }

    if (videoStreamUrl == null || videoStreamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = rawDataDump;
        });
      }
      return;
    }

    // تعديل الترويسة للـ inline
    if (videoStreamUrl.contains('response-content-disposition=attachment')) {
      videoStreamUrl = videoStreamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!videoStreamUrl.contains('response-content-disposition=')) {
      final sep = videoStreamUrl.contains('?') ? '&' : '?';
      videoStreamUrl = '$videoStreamUrl${sep}response-content-disposition=inline';
    }

    // تشغيل الفيديو
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoStreamUrl),
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
      _errorMessage = 'خطأ أثناء تهيئة المشغل:\n$e\n\nالرابط المستخرج:\n$videoStreamUrl';
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'محتوى الـ JSON المستلم من السيرفر (200 OK):',
                        style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                        ),
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
