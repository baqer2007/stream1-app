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

  List<dynamic> _qualities = [];
  List<dynamic> _subtitles = [];
  String _currentQuality = 'تلقائي';

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'] ??
        widget.movieData['title'];
    _movieDescription = widget.movieData['ar_content'] ??
        widget.movieData['en_content'] ??
        widget.movieData['content'];
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

  // نافذة اختيار الجودة
  void _showQualityDialog() {
    if (_qualities.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'اختر جودة الفيديو',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ..._qualities.map((item) {
              final res = item['resolution'] ?? 'غير محدد';
              final url = item['url'] ?? '';
              final isSelected = _currentQuality == res;

              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.redAccent : Colors.white54,
                ),
                title: Text(
                  res,
                  style: TextStyle(
                    color: isSelected ? Colors.redAccent : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (!isSelected && url.isNotEmpty) {
                    final currentPos = _videoPlayerController?.value.position ?? Duration.zero;
                    _currentQuality = res;
                    await _switchQuality(url, currentPos);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _switchQuality(String newUrl, Duration resumePosition) async {
    setState(() {
      _isLoading = true;
      _statusText = 'جاري التبديل إلى جودة $_currentQuality...';
    });

    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    await _initPlayer(newUrl, startAt: resumePosition);
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
        _statusText = 'جاري استخراج بيانات الفيديو والترجمة...';
      });

      final uri = Uri.parse('$appGlobalServerUrl/api/get-stream?id=$postId');
      final res = await http.get(uri).timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final String? videoUrl = data['video_url'];

        _qualities = data['qualities'] ?? [];
        _subtitles = data['subtitles'] ?? [];

        if (_qualities.isNotEmpty) {
          final matched = _qualities.firstWhere(
            (q) => q['url'] == videoUrl,
            orElse: () => _qualities.first,
          );
          _currentQuality = matched['resolution'] ?? 'Auto';
        }

        if (videoUrl != null && videoUrl.isNotEmpty) {
          await _initPlayer(videoUrl);
        } else {
          throw 'لم يتم العثور على رابط فيديو صالح في الرد.';
        }
      } else {
        throw 'استجابة السيرفر (${res.statusCode}): ${res.body}';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر تشغيل الفيديو: $e';
        });
      }
    }
  }

  Future<void> _initPlayer(String streamUrl, {Duration? startAt}) async {
    try {
      setState(() {
        _statusText = 'جاري تهيئة المشغل...';
      });

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://cee.buzz/',
          'Origin': 'https://cee.buzz',
        },
      );

      await _videoPlayerController!.initialize();

      if (startAt != null && startAt > Duration.zero) {
        await _videoPlayerController!.seekTo(startAt);
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        fullScreenByDefault: false,
        additionalOptions: (context) {
          return <OptionItem>[
            if (_qualities.isNotEmpty)
              OptionItem(
                onTap: () {
                  Navigator.pop(context);
                  _showQualityDialog();
                },
                iconData: Icons.high_quality,
                title: 'الجودة ($_currentQuality)',
              ),
          ];
        },
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'حدث خطأ في المشغل: $error',
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
          _errorMessage = 'فشل تهيئة مشغل الفيديو: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: Text(_movieTitle ?? 'مشغل الفيديو'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          if (_qualities.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              tooltip: 'تغيير الجودة',
              onPressed: _showQualityDialog,
            ),
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _movieTitle ?? 'بدون عنوان',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (_currentQuality.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.redAccent, width: 0.8),
                                    ),
                                    child: Text(
                                      _currentQuality,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                    ),
                                  ),
                              ],
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
