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
  String _debugLog = '';

  final Map<String, String> _networkHeaders = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _startFetch();
  }

  // دالة متقدمة لاستخراج الروابط أو بناء الرابط في حال وجد اسم الملف والسيرفر
  String? _extractStream(dynamic obj) {
    if (obj == null) return null;

    if (obj is Map) {
      // 1. فحص الروابط الصريحة
      for (var key in ['videoUrl', 'containerUrl', 'fileUrl', 'directUrl', 'streamUrl', 'url']) {
        if (obj[key] != null && obj[key].toString().trim().startsWith('http')) {
          return obj[key].toString().trim();
        }
      }

      // 2. فحص إن كان يعيد كائن سيرفر به اسم ملف
      if (obj['fileFile'] != null || obj['file'] != null || obj['fileName'] != null) {
        String fName = (obj['fileFile'] ?? obj['file'] ?? obj['fileName']).toString();
        // إذا كان يحتوي على اسم الملف فقط
        if (!fName.startsWith('http') && fName.isNotEmpty) {
          return 'https://cndw1.shabakaty.com/vascin24-mp4/$fName?response-content-disposition=inline';
        }
      }

      for (var v in obj.values) {
        if (v is Map || v is List) {
          final res = _extractStream(v);
          if (res != null) return res;
        }
      }
    } else if (obj is List) {
      for (var item in obj) {
        final res = _extractStream(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _startFetch() async {
    String? streamUrl;
    StringBuffer logs = StringBuffer();

    // 1. أولاً نجرب مسار الحلقات للـ post لمعرفة معرّف الفيديو الحقيقي لكل فيلم
    String targetId = widget.videoId;
    final String postCheckUrl =
        'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}';

    try {
      final postRes = await http.get(Uri.parse(postCheckUrl), headers: _networkHeaders);
      logs.writeln('طلب allVideo: ${postRes.statusCode}');

      if (postRes.statusCode == 200) {
        final body = json.decode(postRes.body);
        List videos = [];
        if (body is List) videos = body;
        else if (body is Map && body['items'] is List) videos = body['items'];

        if (videos.isNotEmpty && videos[0] is Map) {
          final v = videos[0];
          logs.writeln('تم العثور على حلقة/فيديو داخلي: nb=${v['nb']}');
          if (v['nb'] != null) {
            targetId = v['nb'].toString();
          }
          // فحص مباشر للملفات داخل الرد
          streamUrl = _extractStream(v);
        }
      }
    } catch (e) {
      logs.writeln('فشل فحص allVideo: $e');
    }

    // 2. إذا لم نجد الرابط، نستدعي مسارات السيرفرات المتعددة
    if (streamUrl == null) {
      final endpoints = [
        'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/$targetId',
        'https://cinemana.shabakaty.com/api/android/videoFiles/id/$targetId',
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/$targetId',
      ];

      for (var ep in endpoints) {
        try {
          final res = await http.get(Uri.parse(ep), headers: _networkHeaders);
          logs.writeln('[$ep] -> ${res.statusCode}');

          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final data = json.decode(res.body);

            // طباعة المفاتيح الموجودة بالرد للمساعدة في التشخيص
            if (data is List && data.isNotEmpty && data[0] is Map) {
              logs.writeln('مفاتيح الرد: ${data[0].keys.toList()}');
              _movieTitle ??= data[0]['ar_title'] ?? data[0]['en_title'];
              _movieDescription ??= data[0]['ar_content'] ?? data[0]['en_content'];
            } else if (data is Map) {
              logs.writeln('مفاتيح الرد: ${data.keys.toList()}');
            }

            streamUrl = _extractStream(data);
            if (streamUrl != null) {
              logs.writeln('تم استخراج الرابط بنجاح!');
              break;
            }
          }
        } catch (e) {
          logs.writeln('خطأ في $ep: $e');
        }
      }
    }

    if (streamUrl == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = logs.toString();
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

    // بدء المشغل
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
      _errorMessage = 'خطأ أثناء تهيئة المشغل:\n$e\nالرابط:\n$streamUrl\n\nالسجلات:\n$logs';
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
                        'بيانات الاتصال وتفاصيل الاستجابة:',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
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
