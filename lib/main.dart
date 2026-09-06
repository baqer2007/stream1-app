import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'stream_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OnebrTvApp());
}

class OnebrTvApp extends StatelessWidget {
  const OnebrTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ONEBR TV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E), // --bg
        primaryColor: const Color(0xFFE50914), // --primary
        cardColor: const Color(0xFF0F1422), // --surface
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF0F1422),
          secondary: Color(0xFF00F0FF), // --cyan
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  // نماذج أعمال افتراضية للعرض في الرفوف
  final List<Map<String, String>> _trendingItems = [
    {'id': '3130508', 'title': 'The Runner', 'score': '⭐ 8.5', 'year': '2026', 'img': 'https://image.tmdb.org/t/p/w500/mXk9kEw9u5dF72Tsk4O9Jt0rGgG.jpg'},
    {'id': '3128445', 'title': 'Dune: Part Two', 'score': '⭐ 8.8', 'year': '2024', 'img': 'https://image.tmdb.org/t/p/w500/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg'},
    {'id': '3129910', 'title': 'Solo Leveling', 'score': '⭐ 9.1', 'year': '2024', 'img': 'https://image.tmdb.org/t/p/w500/geCRueV3ElhRTr0xtJuPxJ8ZXq5.jpg'},
  ];

  final List<Map<String, String>> _animeItems = [
    {'id': '3129910', 'title': 'Solo Leveling', 'score': '⭐ 9.1', 'year': '2024', 'img': 'https://image.tmdb.org/t/p/w500/geCRueV3ElhRTr0xtJuPxJ8ZXq5.jpg'},
    {'id': '3130508', 'title': 'Jujutsu Kaisen', 'score': '⭐ 8.9', 'year': '2023', 'img': 'https://image.tmdb.org/t/p/w500/hD8eN3iU2p24fS4X27gK.jpg'},
  ];

  @override
  void initState() {
    super.initState();
    // تفعيل عامل المعالجة في الخلفية لدعم مستخدمي الخارج
    StreamService.startRelayWorker();
  }

  void _playVideoById(String id, String title) async {
    setState(() => _isLoading = true);

    final data = await StreamService.getVideoSource(id);

    setState(() => _isLoading = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: title,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities']),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر جلب فيديو ($title)، جاري معالجته في السحابة...'),
          backgroundColor: const Color(0xFFE50914),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: _buildDrawer(),
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(),
                  const SizedBox(height: 16),
                  _buildSectionShelf('🔥 الأكثر رواجاً اليوم', _trendingItems),
                  _buildSectionShelf('⛩️ عالم الأنمي والرسوم المتحركة', _animeItems),
                  _buildSectionShelf('🎬 أحدث الأفلام العالمية', _trendingItems.reversed.toList()),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.75),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00F0FF)),
                      SizedBox(height: 16),
                      Text(
                        'جاري فحص السيرفر وتجهيز البث الفوري...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F1422),
      elevation: 0,
      titleSpacing: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE50914), width: 1),
            ),
            child: const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 18),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF3344), Color(0xFF00F0FF)],
            ).createShader(bounds),
            child: const Text(
              'ONEBR TV',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text('👑 VIP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0B0F19),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0F1422)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFF3344), Color(0xFF00F0FF)],
                  ).createShader(bounds),
                  child: const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(height: 6),
                const Text('مشاهدة أحدث الأفلام والمسلسلات والأنمي', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          ListTile(leading: const Icon(Icons.home, color: Colors.white), title: const Text('الرئيسية'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.movie, color: Colors.white), title: const Text('الأفلام'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.tv, color: Colors.white), title: const Text('المسلسلات'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.sports_esports, color: Color(0xFF00F0FF)), title: const Text('الأنمي'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.bookmark, color: Color(0xFFF59E0B)), title: const Text('المفضلة'), onTap: () => Navigator.pop(context)),
          const Divider(color: Colors.white12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'تشغيل معرف يدوي (ID)...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF172033),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.play_arrow, color: Color(0xFF00F0FF)),
                  onPressed: () {
                    final id = _searchController.text.trim();
                    if (id.isNotEmpty) {
                      Navigator.pop(context);
                      _playVideoById(id, 'العمل رقم $id');
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: 240,
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage('https://image.tmdb.org/t/p/original/mXk9kEw9u5dF72Tsk4O9Jt0rGgG.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          height: 240,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF07090E), Colors.transparent],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The Runner (2026)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('أقوى عروض الأسبوع متوفر الآن بأعلى دقة وسيرفرات سريعة.', style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _playVideoById('3130508', 'The Runner'),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('مشاهدة العمل الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionShelf(String title, List<Map<String, String>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        SizedBox(
          height: 215,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              return InkWell(
                onTap: () => _playVideoById(item['id']!, item['title']!),
                child: Container(
                  width: 125,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1422),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: Image.network(
                          item['img']!,
                          height: 155,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(height: 155, color: const Color(0xFF172033)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item['year']!, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                Text(item['score']!, style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.videoUrl,
    required this.qualities,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _startPlayer(widget.videoUrl);
  }

  void _startPlayer(String url) async {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    setState(() => _isReady = false);

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFE50914),
        handleColor: const Color(0xFF00F0FF),
        backgroundColor: Colors.white24,
        bufferedColor: Colors.white38,
      ),
    );

    if (mounted) setState(() => _isReady = true);
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
        title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F1422),
      ),
      body: Center(
        child: _isReady && _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
      ),
    );
  }
}
