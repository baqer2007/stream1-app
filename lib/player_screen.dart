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
    _loadStream();
  }

  // فحص واستخراج الرابط من مختلف التراكيب
  String? _extractStreamUrl(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      // 1. فحص الحقول المباشرة
      for (final key in [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'streamUrl',
        'url',
        'directUrl',
      ]) {
        if (data[key] != null && data[key].toString().startsWith('http')) {
          return data[key].toString();
        }
      }

      // 2. فحص حالة وجود مسار واسم ملف ومجلد تخزين
      if (data['fileFile'] != null || data['fileName'] != null) {
        final fileName = data['fileFile'] ?? data['fileName'];
        final server = data['server'] ?? 'cndw1.shabakaty.com';
        final folder = data['folder'] ?? 'vascin24-mp4';
        return 'https://$server/$folder/$fileName?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';
      }

      // البحث في الفروع الداخلية
      for (final val in data.values) {
        if (val is Map || val is List) {
          final res = _extractStreamUrl(val);
          if (res != null) return res;
        }
      }
    } else if (data is List) {
      for (final element in data) {
        final res = _extractStreamUrl(element);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _loadStream() async {
    String? streamUrl;
    String lastStatus = '';

    // المسارات التي تستخدمها سينمانا لجلب سيرفرات الفيديو والملفات
    final endpoints = [
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}',
    ];

    for (final url in endpoints) {
      try {
        final res = await http.get(Uri.parse(url), headers: _networkHeaders);
        lastStatus = 'HTTP ${res.statusCode}';

        if (res.statusCode == 200) {
          final decoded = json.decode(res.body);

          // التقاط العنوان والوصف إن توفرا
          if (decoded is List && decoded.isNotEmpty && decoded[0] is Map) {
            _movieTitle ??= decoded[0]['ar_title'] ?? decoded[0]['en_title'];
            _movieDescription ??= decoded[0]['ar_content'] ?? decoded[0]['en_content'];
          } else if (decoded is Map) {
            _movieTitle ??= decoded['ar_title'] ?? decoded['en_title'];
            _movieDescription ??= decoded['ar_content'] ?? decoded['en_content'];
          }

          streamUrl = _extractStreamUrl(decoded);
          if (streamUrl != null && streamUrl.isNotEmpty) break;
        }
      } catch (e) {
        lastStatus = 'خطأ اتصال: $e';
      }
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'لم يتم العثور على رابط بث لهذا العمل ($lastStatus).\nتأكد من أن العمل متوفر عبر شبكتي.';
        });
      }
      return;
    }

    // تهيئة معامل inline
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

    // تهيئة مشغل الفيديو
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
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
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'تعذر استلام البث، تأكد من الاتصال بشبكة إيرثلنك.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ أثناء تشغيل الوسائط: $e';
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
