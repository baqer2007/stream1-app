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
    _resolveAndPlay();
  }

  // البحث عن أي رابط بث صالح ومباشر
  String? _extractStreamUrl(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      // 1. فحص روابط الفيديو المباشرة
      for (var k in ['videoUrl', 'containerUrl', 'fileUrl', 'streamUrl', 'url', 'directUrl']) {
        if (data[k] != null && data[k].toString().trim().startsWith('http')) {
          return data[k].toString().trim();
        }
      }

      // 2. إذا وُجد اسم الملف التابع لنفس العمل المطلوب
      if (data['fileFile'] != null && data['fileFile'].toString().isNotEmpty) {
        final fName = data['fileFile'].toString();
        // نبدل mkv إلى mp4 إذا أمكن لأن mp4 مدعوم مباشرة في المشغل
        final cleanName = fName.replaceAll('.mkv', '.mp4');
        return 'https://cndw1.shabakaty.com/vascin24-mp4/$cleanName?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';
      }

      for (var v in data.values) {
        if (v is Map || v is List) {
          final res = _extractStreamUrl(v);
          if (res != null) return res;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        final res = _extractStreamUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _resolveAndPlay() async {
    String? streamUrl;
    StringBuffer logs = StringBuffer();

    // قائمة مسارات الاستعلام مع Query Parameters بدلاً من الـ Path القديم الذي كان يعيد دائماً (3130532)
    final urlsToTry = [
      'https://cinemana.shabakaty.com/api/android/allVideo/page/0?postNb=${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/videoFiles?id=${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles?videoNb=${widget.videoId}&level=0',
      'https://cinemana.shabakaty.com/api/android/video/servers?videoNb=${widget.videoId}&level=0',
    ];

    for (final url in urlsToTry) {
      try {
        final res = await http.get(Uri.parse(url), headers: _networkHeaders);
        logs.writeln('[$url] -> ${res.statusCode}');

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
          final decoded = json.decode(res.body);

          // التحقق أن الاستجابة لا تخص الفيلم الافتراضي الثابت
          bool isDefaultFilm = false;
          if (decoded is List && decoded.isNotEmpty && decoded[0] is Map) {
            if (decoded[0]['nb'] == '3130532' && widget.videoId != '3130532') {
              isDefaultFilm = true;
            }
          }

          if (!isDefaultFilm) {
            logs.writeln('تم استلام رد يخص العمل المطلوب!');
            if (decoded is List && decoded.isNotEmpty && decoded[0] is Map) {
              _movieTitle ??= decoded[0]['ar_title'] ?? decoded[0]['en_title'];
              _movieDescription ??= decoded[0]['ar_content'] ?? decoded[0]['en_content'];
            } else if (decoded is Map) {
              _movieTitle ??= decoded['ar_title'] ?? decoded['en_title'];
              _movieDescription ??= decoded['ar_content'] ?? decoded['en_content'];
            }

            streamUrl = _extractStreamUrl(decoded);
            if (streamUrl != null) break;
          }
        }
      } catch (e) {
        logs.writeln('خطأ في طلب $url: $e');
      }
    }

    if (streamUrl == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'سجلات الاتصال بالخادم:\n$logs';
        });
      }
      return;
    }

    // تعديل الترويسة للـ inline
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

    // تشغيل الفيديو عبر المشغل
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
      _errorMessage = 'خطأ أثناء تهيئة المشغل:\n$e\n\nالرابط:\n$streamUrl\n\nالسجلات:\n$logs';
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
                        'بيانات الاتصال ومحاولات السيرفر:',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Container(
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
