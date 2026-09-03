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
    _startPlayback();
  }

  // دالة مسح واستخراج روابط البث من أي مفتاح
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
        if (data[key] != null && data[key].toString().trim().startsWith('http')) {
          return data[key].toString().trim();
        }
      }

      // في حال توفر اسم الملف المباشر
      if (data['fileFile'] != null && data['fileFile'].toString().isNotEmpty) {
        final fName = data['fileFile'].toString().replaceAll('.mkv', '.mp4');
        return 'https://cndw1.shabakaty.com/vascin24-mp4/$fName?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';
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

  Future<void> _startPlayback() async {
    // المسار المؤكد برمز 200
    final targetUrl = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/video/servers?videoNb=${widget.videoId}&level=0');

    String? streamUrl;
    String rawBody = '';

    try {
      final res = await http.get(targetUrl, headers: _networkHeaders);
      rawBody = res.body;

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = json.decode(res.body);

        if (decoded is List && decoded.isNotEmpty && decoded[0] is Map) {
          _movieTitle ??= decoded[0]['ar_title'] ?? decoded[0]['en_title'];
          _movieDescription ??= decoded[0]['ar_content'] ?? decoded[0]['en_content'];
        } else if (decoded is Map) {
          _movieTitle ??= decoded['ar_title'] ?? decoded['en_title'];
          _movieDescription ??= decoded['ar_content'] ?? decoded['en_content'];
        }

        streamUrl = _extractStreamUrl(decoded);
      }
    } catch (e) {
      rawBody = 'خطأ أثناء الاتصال: $e';
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = rawBody.isEmpty ? 'استجابة الخادم فارغة' : rawBody;
        });
      }
      return;
    }

    // تعديل الترويسة إلى inline
    if (streamUrl.contains('response-content-disposition=attachment')) {
      streamUrl = streamUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!streamUrl.contains('response-content-disposition=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}response-content-disposition=inline';
    }

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
      _errorMessage = 'خطأ أثناء تهيئة المشغل:\n$e\n\nالرابط المستخرج:\n$streamUrl';
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
                        'محتوى الرد المستلم من السيرفر (200 OK):',
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
