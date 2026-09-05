import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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
  String _statusText = 'جاري التحضير...';
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  // الرابط الافتراضي الحالي
  String _serverBaseUrl = 'https://ffbdca9fc0bc6f.lhr.life';

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    
    _loadSavedUrlAndStart();
  }

  // قراءة الرابط المخزن في الهاتف
  Future<void> _loadSavedUrlAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('saved_server_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _serverBaseUrl = savedUrl;
    }
    _requestAndStartStreaming();
  }

  // نافذة لتغيير الرابط ولصق الجديد بنقرة زر
  void _showChangeUrlDialog() {
    final controller = TextEditingController(text: _serverBaseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('تحديث رابط السيرفر', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الصق رابط localhost.run الجديد هنا دون الحاجة لإعادة تنزيل التطبيق:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://xxxx.lhr.life',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
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
            onPressed: () async {
              String newUrl = controller.text.trim();
              if (newUrl.endsWith('/')) newUrl = newUrl.substring(0, newUrl.length - 1);
              
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('saved_server_url', newUrl);

              setState(() {
                _serverBaseUrl = newUrl;
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
    final postId = (widget.movieData['nb'] ?? widget.movieData['id'] ?? '').toString();

    if (postId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'معرف الفيلم غير متوفر.';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusText = 'جاري إرسال طلب التجهيز للسيرفر...';
      });

      final uri = Uri.parse('$_serverBaseUrl/play-hls?postId=$postId&res=240p');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final String streamUrl = data['streamUrl'];

        setState(() {
          _statusText = 'جاري تهيئة أجزاء البث...';
        });

        await Future.delayed(const Duration(seconds: 8));
        await _initPlayer(streamUrl);
      } else {
        throw 'استجابة السيرفر: ${res.statusCode}';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر الاتصال بالسيرفر ($e)\n\nتأكد من الرابط أو اضغط أيقونة الإعدادات ⚙️ بالأعلى لتغييره.';
        });
      }
    }
  }

  Future<void> _initPlayer(String streamUrl) async {
    try {
      setState(() {
        _statusText = 'جاري فتح الفيديو...';
      });

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
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
                'جاري تحميل أجزاء إضافية من البث... ($error)',
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
          _errorMessage = 'فشل تشغيل تدفق HLS: $e';
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
        title: Text(_movieTitle ?? 'مشغل سينمانا'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'تغيير رابط السيرفر',
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
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('تغيير الرابط الآن'),
                          onPressed: _showChangeUrlDialog,
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
