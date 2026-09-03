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
    _fetchSignedStream();
  }

  // البحث عن الروابط الموقعة الجاهزة
  String? _findSignedUrl(dynamic json) {
    if (json == null) return null;

    if (json is Map) {
      // فحص الحقول التي تحتوي على رابط كامل موقّع
      for (var key in ['videoUrl', 'containerUrl', 'fileUrl', 'url']) {
        if (json[key] != null) {
          final str = json[key].toString().trim();
          if (str.startsWith('http') && (str.contains('AWSAccessKeyId') || str.contains('Signature') || str.endsWith('.mp4'))) {
            return str;
          }
        }
      }

      for (var v in json.values) {
        if (v is Map || v is List) {
          final res = _findSignedUrl(v);
          if (res != null) return res;
        }
      }
    } else if (json is List) {
      // تفضيل روابط mp4 إن وجدت الجودات
      for (var item in json) {
        final res = _findSignedUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _fetchSignedStream() async {
    String? streamUrl;
    StringBuffer logBuffer = StringBuffer();

    // المسارات الدقيقة مع معامل level/0 الذي يطلبه سيرفر شبكتي لإرجاع التوقيع
    final List<String> endpoints = [
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}/level/0',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}/level/0',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
    ];

    for (final ep in endpoints) {
      try {
        final res = await http.get(Uri.parse(ep), headers: _networkHeaders);
        logBuffer.writeln('[$ep] => ${res.statusCode}');

        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final dynamic data = json.decode(res.body);

          // حفظ العنوان والوصف
          if (data is List && data.isNotEmpty && data[0] is Map) {
            _movieTitle ??= data[0]['ar_title'] ?? data[0]['en_title'];
            _movieDescription ??= data[0]['ar_content'] ?? data[0]['en_content'];
          } else if (data is Map) {
            _movieTitle ??= data['ar_title'] ?? data['en_title'];
            _movieDescription ??= data['ar_content'] ?? data['en_content'];
          }

          final candidate = _findSignedUrl(data);
          if (candidate != null && candidate.isNotEmpty) {
            streamUrl = candidate;
            logBuffer.writeln('تم العثور على رابط موقع بنجاح');
            break;
          }
        }
      } catch (e) {
        logBuffer.writeln('خطأ في $ep: $e');
      }
    }

    if (streamUrl == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم نتمكن من استخراج رابط التوقيع الحي:\n\n$logBuffer';
        });
      }
      return;
    }

    // تبديل الترويسة إلى inline للبث الحي
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

    // تشغيل الفيديو
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
                'تعذر تشغيل البث: $error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'فشل أثناء تهيئة المشغل:\n$e\n\nالرابط المستلم:\n$streamUrl';
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
                        'تفاصيل الاستجابة والتوقيع:',
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
