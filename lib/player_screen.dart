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
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _prepareStream();
  }

  Future<void> _prepareStream() async {
    String? finalVideoUrl;

    // 1. فحص روابط السيرفرات والجودات المتاحة لهذا الفيلم
    final endpoints = [
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
    ];

    for (final endpoint in endpoints) {
      try {
        final res = await http.get(Uri.parse(endpoint), headers: {
          'User-Agent': 'Cinemana/3.0.0 (Android)',
          'Accept': 'application/json',
        });

        if (res.statusCode == 200) {
          final dynamic data = json.decode(res.body);
          List list = [];
          if (data is List) {
            list = data;
          } else if (data is Map && data['files'] is List) {
            list = data['files'];
          }

          for (var entry in list) {
            // استخراج عنوان ووصف الفيلم إن وُجدا
            if (_movieTitle == null || _movieTitle!.isEmpty) {
              _movieTitle = entry['ar_title'] ?? entry['en_title'];
            }
            _movieDescription ??= entry['ar_content'] ?? entry['en_content'];

            // البحث عن رابط الفيديو الفعّال
            String candidate = entry['videoUrl'] ??
                entry['containerUrl'] ??
                entry['fileUrl'] ??
                '';

            if (candidate.isNotEmpty) {
              finalVideoUrl = candidate;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Endpoint error: $e');
      }

      if (finalVideoUrl != null && finalVideoUrl.isNotEmpty) break;
    }

    if (finalVideoUrl == null || finalVideoUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يتم العثور على رابط بث متاح لهذا العمل.';
        });
      }
      return;
    }

    // 2. تعديل الرابط ليعمل كـ inline بدلاً من attachment
    if (finalVideoUrl.contains('response-content-disposition=attachment')) {
      finalVideoUrl = finalVideoUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!finalVideoUrl.contains('response-content-disposition=')) {
      final separator = finalVideoUrl.contains('?') ? '&' : '?';
      finalVideoUrl = '$finalVideoUrl${separator}response-content-disposition=inline';
    }

    // 3. تشغيل الفيديو
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalVideoUrl),
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
          return const Center(
            child: Text(
              'تعذر تشغيل هذا المقطع، تأكد من اتصالك بشبكة إيرثلنك.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ أثناء تهيئة المشغل: تأكد من تفعيل بث الفيديو على الشبكة.';
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
