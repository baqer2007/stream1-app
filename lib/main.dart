import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: StreamSearchScreen(),
  ));
}

class StreamSearchScreen extends StatefulWidget {
  const StreamSearchScreen({super.key});

  @override
  State<StreamSearchScreen> createState() => _StreamSearchScreenState();
}

class _StreamSearchScreenState extends State<StreamSearchScreen> {
  final TextEditingController _queryController = TextEditingController(text: "Inception");
  bool _isSearching = false;
  String _statusMessage = "أدخل اسم العمل للبحث عن سيرفرات البث";
  List<Map<String, String>> _streamServers = [];

  // رأس متصفح قياسي لتخطي عمليات الحظر
  final Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  Future<void> _searchAndExtract() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _statusMessage = "🔍 جاري فحص خوادم المشاهدة وسحب الروابط...";
      _streamServers.clear();
    });

    List<Map<String, String>> foundServers = [];

    try {
      // 1. محرك البحث الأول: جلب وتدقيق البث عبر مصادر عامة ومباشرة
      // تجربة استخراج روابط تجريبية وسيرفرات مفتوحة متوافقة
      final encodedQuery = Uri.encodeComponent(query);
      
      // إضافة سيرفر تجريبي مباشر عالي الدقة دائماً للاختبار السريع
      foundServers.add({
        "server": "سيرفر البث السريع (HLS / m3u8)",
        "url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "quality": "1080p / Multi"
      });

      foundServers.add({
        "server": "سيرفر البث الاحتياطي (MP4 Direct)",
        "url": "https://vjs.zencdn.net/v/oceans.mp4",
        "quality": "720p"
      });

      // 2. محرك استخراج الروابط المباشرة من صفحات الويب (Scraper Engine)
      // فحص مصادر المشاهدة العامة واستخراج مصادر الفيديو من وسوم iframe أو video
      try {
        final searchUrl = Uri.parse("https://html.duckduckgo.com/html/?q=${encodedQuery}+watch+online+stream");
        final searchRes = await http.get(searchUrl, headers: _defaultHeaders).timeout(const Duration(seconds: 8));

        if (searchRes.statusCode == 200) {
          final doc = html_parser.parse(searchRes.body);
          final links = doc.querySelectorAll('a.result__url');
          
          for (var link in links.take(3)) {
            final rawHref = link.attributes['href'];
            if (rawHref != null && rawHref.contains("uddg=")) {
              final targetUrl = Uri.decodeComponent(rawHref.split("uddg=")[1].split("&")[0]);
              
              // سحب محتوى الصفحة والبحث عن مسارات الفيديو
              final pageRes = await http.get(Uri.parse(targetUrl), headers: _defaultHeaders).timeout(const Duration(seconds: 6));
              if (pageRes.statusCode == 200) {
                final pageDoc = html_parser.parse(pageRes.body);

                // استخراج من وسوم video
                final videoTag = pageDoc.querySelector('video source, video');
                final videoSrc = videoTag?.attributes['src'];
                if (videoSrc != null && (videoSrc.contains('.mp4') || videoSrc.contains('.m3u8'))) {
                  foundServers.add({
                    "server": "مستخرج الويب المباشر (${Uri.parse(targetUrl).host})",
                    "url": videoSrc,
                    "quality": "Direct"
                  });
                }

                // استخراج التضمينات iFrame
                final iframeTag = pageDoc.querySelector('iframe[src*="embed"], iframe[src*="player"]');
                final iframeSrc = iframeTag?.attributes['src'];
                if (iframeSrc != null) {
                  foundServers.add({
                    "server": "سيرفر مضمن (${Uri.parse(targetUrl).host})",
                    "url": iframeSrc.startsWith('//') ? "https:$iframeSrc" : iframeSrc,
                    "quality": "Embedded"
                  });
                }
              }
            }
          }
        }
      } catch (_) {
        // الاستمرار في حال انتهاء مهلة محرك الويب
      }

      setState(() {
        _isSearching = false;
        _streamServers = foundServers;
        _statusMessage = "تم العثور على ${foundServers.length} سيرفر(ات) للبث";
      });

    } catch (e) {
      setState(() {
        _isSearching = false;
        _statusMessage = "تعذر السحب: ${e.toString()}";
      });
    }
  }

  void _openPlayer(String url, String serverName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          url: url,
          title: "${_queryController.text} - $serverName",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1016),
      appBar: AppBar(
        title: const Text("محرك سحب وبث الفيديو", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF181B26),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E2230),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "اكتب اسم الفيلم أو الأنمي...",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Color(0xFF45F3FF), strokeWidth: 2),
                          )
                        : const Icon(Icons.search, color: Color(0xFF45F3FF)),
                    onPressed: _isSearching ? null : _searchAndExtract,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(color: Color(0xFF8E99A8), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _streamServers.isEmpty
                  ? Center(
                      child: Text(
                        _isSearching ? "جاري فك تشفير مسارات التشغيل..." : "لا توجد سيرفرات معروضة حالياً",
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _streamServers.length,
                      itemBuilder: (context, index) {
                        final item = _streamServers[index];
                        return Card(
                          color: const Color(0xFF1A1D27),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFF232938),
                              child: Icon(Icons.play_circle_fill, color: Color(0xFF45F3FF)),
                            ),
                            title: Text(
                              item["server"] ?? "سيرفر تشغيل",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              "الجودة / النوع: ${item["quality"]}",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF45F3FF),
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () => _openPlayer(item["url"]!, item["server"]!),
                              child: const Text("تشغيل"),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const VideoPlayerScreen({super.key, required this.url, required this.title});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final uri = Uri.parse(widget.url);
      _videoPlayerController = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
          'Referer': '${uri.scheme}://${uri.host}/',
        },
      );

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              "خطأ أثناء العرض: $errorMessage",
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    } catch (e) {
      _errorMessage = e.toString();
    }

    if (mounted) {
      setState(() {});
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "تعذر تشغيل هذا الرابط:\n$_errorMessage\n\nجرّب سيرفر آخر من القائمة.",
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            : (_chewieController != null && _videoPlayerController!.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
