import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'stream_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CinemanaApp());
}

class CinemanaApp extends StatelessWidget {
  const CinemanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cinemana Player',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE11D48),
          secondary: Color(0xFFE11D48),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController(text: '3130508');
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // تفعيل عامل المعالجة الصامت في الخلفية لجلب المهام المعلقة تلقائياً
    StreamService.startRelayWorker();
  }

  void _loadAndPlay() async {
    final videoId = _controller.text.trim();
    if (videoId.isEmpty) return;

    setState(() => _isLoading = true);

    // محاولة جلب الفيديو (من الكاش السحابي أو الشبكة)
    final data = await StreamService.getVideoSource(videoId);

    setState(() => _isLoading = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities']),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر جلب رابط الفيديو حالياً، يرجى المحاولة لاحقاً'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cinemana Relay Player'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_circle_fill_rounded,
                size: 80,
                color: Color(0xFFE11D48),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'معرف الفيلم أو الحلقة (Video ID)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Column(
                      children: [
                        CircularProgressIndicator(color: Color(0xFFE11D48)),
                        SizedBox(height: 12),
                        Text('جاري الاتصال وجلب الرابط المباشر...'),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE11D48),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _loadAndPlay,
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        label: const Text(
                          'تشغيل الفيديو',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;

  const PlayerScreen({
    super.key,
    required this.videoUrl,
    required this.qualities,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isPlayerReady = false;

  @override
  void initState() {
    super.initState();
    _initPlayer(widget.videoUrl);
  }

  void _initPlayer(String url) async {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    setState(() => _isPlayerReady = false);

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFE11D48),
        handleColor: const Color(0xFFE11D48),
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white24,
      ),
    );

    if (mounted) {
      setState(() => _isPlayerReady = true);
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('مشغل الفيديو'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _isPlayerReady && _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(color: Color(0xFFE11D48)),
      ),
    );
  }
}
