import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  final TextEditingController _urlController = TextEditingController(
    text: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
  );
  String _status = "جاهز للتشغيل. يمكنك تجربة الرابط الافتراضي أو لصق أي رابط فيديو.";
  bool _loading = false;

  void _playCurrentUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url, title: "مشغل البث"),
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
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1F2833),
                hintText: "أدخل رابط البث المباشر (mp4 أو m3u8)...",
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
              onPressed: _loading ? null : _playCurrentUrl,
              child: const Text("تشغيل البث التجريبي 🎬", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
      );
    } catch (e) {
      _hasError = true;
    }
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
        child: _hasError
            ? const Text("تعذر تحميل البث من هذا الرابط", style: TextStyle(color: Colors.red))
            : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
