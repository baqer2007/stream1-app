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

  // مطابقة الترويسات الدقيقة للمتصفح لمنع خطأ 400
  Map<String, String> get _browserHeaders => {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/video/en/${widget.videoId}?showinfo=true',
    'Origin': 'https://cinemana.shabakaty.com',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'ar-IQ,ar;q=0.9,en-IQ;q=0.8,en;q=0.7',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _startPlaybackFlow();
  }

  // البحث عن أي رابط بث مباشر أو استخراجه من أي حقل
  String? _extractStreamUrl(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      for (final key in [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'directUrl',
        'streamUrl',
        'url',
        'link'
      ]) {
        if (data[key] != null) {
          final s = data[key].toString().trim();
          if (s.startsWith('http') && (s.contains('.mp4') || s.contains('vascin'))) {
            return s;
          }
        }
      }

      for (var val in data.values) {
        if (val is Map || val is List) {
          final res = _extractStreamUrl(val);
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

  Future<void> _startPlaybackFlow() async {
    // المسار الرسمي الذي أرجع 200 OK في DevTools
    final targetUrl = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/allVideoInfo/id/${widget.videoId}');

    String? streamUrl;
    String rawResponse = '';

    try {
      final res = await http.get(targetUrl, headers: _browserHeaders);

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = json.decode(res.body);

        if (decoded is Map) {
          _movieTitle ??= decoded['ar_title'] ?? decoded['en_title'];
          _movieDescription ??= decoded['ar_content'] ?? decoded['en_content'];
          streamUrl = _extractStreamUrl(decoded);
          if (streamUrl == null) {
            rawResponse = const JsonEncoder.withIndent('  ').convert(decoded);
          }
        } else if (decoded is List && decoded.isNotEmpty) {
          final first = decoded[0];
          if (first is Map) {
            _movieTitle ??= first['ar_title'] ?? first['en_title'];
            _movieDescription ??= first['ar_content'] ?? first['en_content'];
          }
          streamUrl = _extractStreamUrl(decoded);
          if (streamUrl == null) {
            rawResponse = const JsonEncoder.withIndent('  ').convert(first);
          }
        }
      } else {
        rawResponse = 'فشل الرد برمز: ${res.statusCode}\n${res.body}';
      }
    } catch (e) {
      rawResponse = 'خطأ أثناء الاتصال: $e';
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = rawResponse.isEmpty
              ? 'لم يتم العثور على رابط البث في الاستجابة.'
              : rawResponse;
        });
      }
      return;
    }

    // تعديل الترويسة لتعمل بوضع inline للبث
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
          'response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    // تتبع الـ Redirect (302) التلقائي إلى CDN الخادم
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
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'محتوى الرد المستلم من السيرفر:',
                        style: TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
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
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontFamily: 'monospace'),
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
