import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: StreamHome(),
  ));
}

class StreamHome extends StatefulWidget {
  const StreamHome({super.key});

  @override
  State<StreamHome> createState() => _StreamHomeState();
}

class _StreamHomeState extends State<StreamHome> {
  final TextEditingController _query = TextEditingController(text: "Inception");
  String _status = "جاهز للاستخراج والتشغيل";
  bool _loading = false;

  Future<void> _extractAndPlay() async {
    final title = _query.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _loading = true;
      _status = "🔍 جاري فحص السيرفر وسحب الرابط المباشر...";
    });

    try {
      final searchUri = Uri.parse("https://akwam.to/search?q=${Uri.encodeComponent(title)}");
      final response = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36'
      });

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final firstLink = document.querySelector('a[href*="/movie/"], a[href*="/series/"]')?.attributes['href'];

        if (firstLink != null) {
          final pageRes = await http.get(Uri.parse(firstLink), headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36'
          });

          final pageHtml = pageRes.body;
          final regex = RegExp(r'https?://[^\s"<>]+\.(mp4|m3u8)[^\s"<>]*');
          final match = regex.firstMatch(pageHtml);

          if (match != null) {
            final streamUrl = match.group(0)!;
            _openPlayer(streamUrl, title);
            return;
          }
        }
      }

      setState(() {
        _loading = false;
        _status = "⚠️ تعذر جلب رابط الفيديو، تحقق من اسم العمل بدقة.";
      });

    } catch (e) {
      setState(() {
        _loading = false;
        _status = "خطأ في الاتصال: ${e.toString()}";
      });
    }
  }

  void _openPlayer(String url, String title) {
    setState(() {
      _loading = false;
      _status = "✅ تم العثور على البث، فتح المشغل...";
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        title: const Text("تطبيق المشاهدة المستقل", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF14161D),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _query,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1F2833),
                hintText: "اسم الفيلم أو العمل...",
                hintStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF45F3FF),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _loading ? null : _extractAndPlay,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text("سحب وتشغيل البث 🎬", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(color: Color(0xFF45F3FF)), textAlign: TextAlign.center),
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
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.transparent),
      body: Center(
        child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(color: Color(0xFF45F3FF)),
      ),
    );
  }
}
