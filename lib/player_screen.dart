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

  final Map<String, String> _headers = {
    'User-Agent': 'Cinemana/3.0.0 (Android)',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Accept': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle;
    _resolveStream();
  }

  // دالة متعمقة لاستخراج رابط الفيديو من أي كائن JSON
  String? _findVideoUrl(dynamic jsonObj) {
    if (jsonObj == null) return null;

    if (jsonObj is Map) {
      // تفقد الحقول المباشرة الشائعة
      final keys = [
        'videoUrl',
        'containerUrl',
        'fileUrl',
        'streamUrl',
        'directUrl',
        'url',
        'file'
      ];
      for (var k in keys) {
        if (jsonObj[k] != null &&
            jsonObj[k].toString().trim().startsWith('http')) {
          return jsonObj[k].toString().trim();
        }
      }

      // إذا وُجدت مصفوفة سيرفرات أو ملفات بالداخل
      for (var val in jsonObj.values) {
        if (val is List || val is Map) {
          final res = _findVideoUrl(val);
          if (res != null) return res;
        }
      }
    } else if (jsonObj is List) {
      for (var element in jsonObj) {
        final res = _findVideoUrl(element);
        if (res != null) return res;
      }
    }

    return null;
  }

  Future<void> _resolveStream() async {
    String? resolvedUrl;
    String effectiveVideoId = widget.videoId;

    // 1. محاولة معرفة ما إذا كان المعرف بحاجة لجلب الحلقات أولاً (postNb)
    final postEndpoint = Uri.parse(
        'https://cinemana.shabakaty.com/api/android/allVideo/page/0/postNb/${widget.videoId}');
    try {
      final postRes = await http.get(postEndpoint, headers: _headers);
      if (postRes.statusCode == 200) {
        final decoded = json.decode(postRes.body);
        List videosList = [];
        if (decoded is List) {
          videosList = decoded;
        } else if (decoded is Map && decoded['items'] is List) {
          videosList = decoded['items'];
        }

        if (videosList.isNotEmpty) {
          final first = videosList[0];
          if (first is Map && (first['nb'] != null || first['id'] != null)) {
            effectiveVideoId = (first['nb'] ?? first['id']).toString();
          }
          // محاولة التقاط الرابط مباشرة إذا كان موجوداً داخل رد الحلقات
          resolvedUrl = _findVideoUrl(first);
        }
      }
    } catch (e) {
      debugPrint('Post check failed: $e');
    }

    // 2. إذا لم يظهر الرابط بعد، نفحص خوادم الفيديو المتعددة
    if (resolvedUrl == null) {
      final videoApis = [
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/$effectiveVideoId',
        'https://cinemana.shabakaty.com/api/android/videoFiles/id/$effectiveVideoId',
        'https://cinemana.shabakaty.com/api/android/transcoddedFiles/videoNb/$effectiveVideoId',
        'https://cinemana.shabakaty.com/api/android/video/servers/videoNb/${widget.videoId}',
      ];

      for (var api in videoApis) {
        try {
          final res = await http.get(Uri.parse(api), headers: _headers);
          if (res.statusCode == 200) {
            final data = json.decode(res.body);

            // التقاط الوصف والعنوان في حال توفرهما
            if (data is List && data.isNotEmpty && data[0] is Map) {
              _movieTitle ??= data[0]['ar_title'] ?? data[0]['en_title'];
              _movieDescription ??= data[0]['ar_content'] ?? data[0]['en_content'];
            }

            resolvedUrl = _findVideoUrl(data);
            if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
              break;
            }
          }
        } catch (e) {
          debugPrint('Error query $api: $e');
        }
      }
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'تعذر الحصول على رابط البث. تأكد من أن العمل متوفر على سيرفرات شبكتي.';
        });
      }
      return;
    }

    // 3. تعديل الرابط ليكون inline للبث المباشر
    if (resolvedUrl.contains('response-content-disposition=attachment')) {
      resolvedUrl = resolvedUrl.replaceAll(
        'response-content-disposition=attachment',
        'response-content-disposition=inline',
      );
    } else if (!resolvedUrl.contains('response-content-disposition=')) {
      final sep = resolvedUrl.contains('?') ? '&' : '?';
      resolvedUrl = '$resolvedUrl${sep}response-content-disposition=inline';
    }

    // 4. تهيئة المشغل
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
        httpHeaders: _headers,
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
                'تعذر استلام البث، تأكد من الاتصال بشبكة إيرثلنك.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = 'خطأ أثناء تشغيل الفيديو: $e';
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
