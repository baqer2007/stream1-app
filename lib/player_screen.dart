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
    _fetchAndStream();
  }

  Future<void> _fetchAndStream() async {
    String? resolvedUrl;

    // مسارات استخراج خوادم وروابط الفيديو الرسمية في شبكتي
    final List<String> possibleApis = [
      'https://cinemana.shabakaty.com/api/android/videoFiles/id/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
      'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}',
    ];

    for (final apiUrl in possibleApis) {
      try {
        final res = await http.get(Uri.parse(apiUrl), headers: _networkHeaders);

        if (res.statusCode == 200) {
          final dynamic data = json.decode(res.body);

          List entries = [];
          if (data is List) {
            entries = data;
          } else if (data is Map) {
            if (data['files'] is List) entries = data['files'];
            else if (data['videos'] is List) entries = data['videos'];
            else if (data['items'] is List) entries = data['items'];
            else if (data['data'] is List) entries = data['data'];
            else entries = [data]; // إذا كان كائناً منفرداً
          }

          for (var item in entries) {
            if (item is Map) {
              _movieTitle ??= item['ar_title'] ?? item['en_title'];
              _movieDescription ??= item['ar_content'] ?? item['en_content'];

              // استخراج رابط البث
              String? url = item['videoUrl'] ??
                  item['containerUrl'] ??
                  item['fileUrl'] ??
                  item['video_url'] ??
                  item['file'];

              // إذا وُجد اسم الملف الخام بدون السيرفر
              if ((url == null || !url.startsWith('http')) && item['fileFile'] != null) {
                final file = item['fileFile'];
                url = 'https://cndw1.shabakaty.com/vascin24-mp4/$file?response-content-disposition=inline&AWSAccessKeyId=PSFBSAZRKNBJOAMKHHBIBOBEONKBBOPKEDDBFBOJCH&Expires=1788966299&Signature=VlWCzhalKqlz15nu3xZN316GOKI%3D';
              }

              if (url != null && url.startsWith('http')) {
                resolvedUrl = url;
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Failed reading $apiUrl: $e');
      }

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) break;
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يتم العثور على خادم تشغيل نشط لهذا العمل حالياً.';
        });
      }
      return;
    }

    // تعديل الترويسة للتشغيل المباشر داخل المشغل
    if (resolvedUrl.contains('response-content-disposition=attachment')) {
      resolvedUrl = resolvedUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!resolvedUrl.contains('response-content-disposition=')) {
      final sep = resolvedUrl.contains('?') ? '&' : '?';
      resolvedUrl = '$resolvedUrl${sep}response-content-disposition=inline';
    }

    // تهيئة وتشغيل المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
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
                'تعذر تحميل الفيديو، تأكد من اتصالك بشبكة تدعم شبكتي.',
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
