import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

// رابط سيرفر Render الثابت
String appGlobalServerUrl = 'https://cee-relay.onrender.com';

class CinemanaPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final String? initialTitle;

  const CinemanaPlayerScreen({
    super.key,
    required this.movieData,
    this.initialTitle,
  });

  @override
  State<CinemanaPlayerScreen> createState() => _CinemanaPlayerScreenState();
}

class _CinemanaPlayerScreenState extends State<CinemanaPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String _statusText = 'جاري الاتصال بالسيرفر...';
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'] ??
        widget.movieData['title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'] ?? widget.movieData['content'];
    _requestAndStartStreaming();
  }

  void _showChangeUrlDialog() {
    final controller = TextEditingController(text: appGlobalServerUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'تحديث رابط السيرفر',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'رابط سيرفر Render الحالي:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://cee-relay.onrender.com',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              String newUrl = controller.text.trim();
              if (newUrl.endsWith('/')) {
                newUrl = newUrl.substring(0, newUrl.length - 1);
              }

              setState(() {
                appGlobalServerUrl = newUrl;
                _isLoading = true;
                _errorMessage = null;
              });
              Navigator.pop(context);
              _requestAndStartStreaming();
            },
            child: const Text('حفظ وتشغيل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAndStartStreaming() async {
    final postId = (widget.movieData['nb'] ??
            widget.movieData['id'] ??
            widget.movieData['video_id'] ??
            '')
        .toString();

    if (postId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'معرف الفيديو غير متوفر.';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusText = 'جاري استخراج رابط البث من CEE...';
      });

      // طلب الرابط الموقع مباشرة من سيرفر Render بصيغة JSON
      final uri = Uri.parse('$appGlobalServerUrl/api/get-stream?id=$postId');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final String? videoUrl = data['video_url'];

        if (videoUrl != null && videoUrl.isNotEmpty) {
          await _initPlayer(videoUrl);
        } else {
          throw 'لم يتم العثور على رابط صالح في الاستجابة';
        }
      } else {
        throw 'خطأ من الخادم (${res.statusCode}): ${res.body}';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر تجهيز الفيديو: $e';
        });
      }
    }
  }

  Future<void> _initPlayer(String streamUrl) async {
    try {
      setState(() {
        _statusText = 'جاري تهيئة مشغل الفيديو...';
      });

      // تزويد المشغل بالترويسات المطلوبة لفك حماية CDN
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://cee.buzz/',
          'Origin': 'https://cee.buzz',
        },
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
                'حدث خطأ أثناء التشغيل: $error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'فشل تشغيل مشغل الفيديو: $e';
        });
      }
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
        title: Text(_movieTitle ?? 'مشاهدة الفيديو'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'إعدادات السيرفر',
            onPressed: _showChangeUrlDialog,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SelectableText(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('إعادة المحاولة'),
                          onPressed: _requestAndStartStreaming,
                        ),
                      ],
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
