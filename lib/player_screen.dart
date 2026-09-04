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

  Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Origin': 'https://cinemana.shabakaty.com',
    'Accept': 'application/json, text/plain, */*',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _resolveAndPlay();
  }

  String? _findVideoFileUrl(dynamic obj) {
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
        final res = _findVideoFileUrl(val);
        if (res != null) return res;
      }
    } else if (obj is List) {
      for (var item in obj) {
        final res = _findVideoFileUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  String? _extractVideoNb(dynamic obj) {
    if (obj == null) return null;
    if (obj is Map) {
      if (obj['nb'] != null && obj['nb'].toString() != widget.videoId) {
        return obj['nb'].toString();
      }
      if (obj['videoNb'] != null) {
        return obj['videoNb'].toString();
      }
      for (var val in obj.values) {
        final res = _extractVideoNb(val);
        if (res != null) return res;
      }
    } else if (obj is List) {
      for (var item in obj) {
        final res = _extractVideoNb(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> _resolveAndPlay() async {
    String? resolvedUrl;
    StringBuffer debugLog = StringBuffer();

    // المرحلة 1: فحص الـ ID في allVideoInfo
    try {
      final directInfoUrl = Uri.parse(
          'https://cinemana.shabakaty.com/api/android/allVideoInfo/id/${widget.videoId}');
      final res = await http.get(directInfoUrl, headers: _browserHeaders);
      debugLog.writeln('allVideoInfo(${widget.videoId}): ${res.statusCode}');

      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != '[]') {
        final data = json.decode(res.body);
        resolvedUrl = _findVideoFileUrl(data);
      }
    } catch (e) {
      debugLog.writeln('Direct info error: $e');
    }

    // المرحلة 2: استخراج الـ videoNb من الـ postNb
    if (resolvedUrl == null) {
      final postResolutionUrls = [
        'https://cinemana.shabakaty.com/api/android/video/servers?postNb=${widget.videoId}',
        'https://cinemana.shabakaty.com/api/android/allVideo/page/0?postNb=${widget.videoId}',
        'https://cinemana.shabakaty.com/api/android/postFiles/id/${widget.videoId}',
      ];

      for (final pUrl in postResolutionUrls) {
        try {
          final pRes = await http.get(Uri.parse(pUrl), headers: _browserHeaders);
          debugLog.writeln('$pUrl => ${pRes.statusCode}');

          if (pRes.statusCode == 200 && pRes.body.isNotEmpty && pRes.body != '[]') {
            final pData = json.decode(pRes.body);
            resolvedUrl = _findVideoFileUrl(pData);
            if (resolvedUrl != null) break;

            final extractedNb = _extractVideoNb(pData);
            if (extractedNb != null) {
              debugLog.writeln('تم العثور على videoNb: $extractedNb');
              final infoRes = await http.get(
                  Uri.parse('https://cinemana.shabakaty.com/api/android/allVideoInfo/id/$extractedNb'),
                  headers: _browserHeaders);
              if (infoRes.statusCode == 200 && infoRes.body.isNotEmpty) {
                final infoData = json.decode(infoRes.body);
                resolvedUrl = _findVideoFileUrl(infoData);
                if (resolvedUrl != null) break;
              }
            }
          }
        } catch (e) {
          debugLog.writeln('Post resolve error: $e');
        }
      }
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'تعذر تحويل معرّف المنشور إلى ملف تشغيل.\n\nسجل المحاولات:\n$debugLog';
        });
      }
      return;
    }

    // ترقية المتغير لضمان عدم كونه null
    String finalStreamUrl = resolvedUrl;

    if (finalStreamUrl.contains('response-content-disposition=attachment')) {
      finalStreamUrl = finalStreamUrl.replaceAll(
          'response-content-disposition=attachment', 'response-content-disposition=inline');
    }

    // تتبع الـ 302 Redirect بأمان تام للأنواع
    try {
      final headRes = await http.head(Uri.parse(finalStreamUrl), headers: _browserHeaders);
      if (headRes.statusCode == 302 && headRes.headers['location'] != null) {
        finalStreamUrl = headRes.headers['location']!;
      }
    } catch (_) {}

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(finalStreamUrl),
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
      _errorMessage = 'خطأ مشغل الفيديو: $e\n\nالرابط المستخرج:\n$finalStreamUrl';
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
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _errorMessage!,
                        style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                        textAlign: TextAlign.left,
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
