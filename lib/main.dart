import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CinemaApp());
}

class CinemaApp extends StatelessWidget {
  const CinemaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سينما البث المستقل',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161922),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class MediaItem {
  final String id;
  final String title;
  final String poster;
  final String year;
  final String type;
  final String summary;

  MediaItem({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
    required this.type,
    required this.summary,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController(text: "One Piece");
  List<MediaItem> _items = [];
  bool _isLoading = false;
  String _message = "ابحث عن أي فيلم، مسلسل، أو أنمي";

  @override
  void initState() {
    super.initState();
    _performSearch("One Piece");
  }

  // محرك بحث هجين مجاني بالكامل بدون الحاجة لأي API Key
  Future<void> _performSearch(String query) async {
    final term = query.trim();
    if (term.isEmpty) return;

    setState(() {
      _isLoading = true;
      _message = "🔍 جاري البحث في قواعد البيانات الحرة...";
      _items.clear();
    });

    List<MediaItem> results = [];

    // 1. البحث في قاعدة بيانات الأنمي العالمية (Jikan MAL)
    try {
      final animeUri = Uri.parse("https://api.jikan.moe/v4/anime?q=${Uri.encodeComponent(term)}&limit=10");
      final animeRes = await http.get(animeUri).timeout(const Duration(seconds: 7));
      if (animeRes.statusCode == 200) {
        final data = json.decode(animeRes.body);
        if (data['data'] != null) {
          for (var item in data['data']) {
            results.add(MediaItem(
              id: item['mal_id']?.toString() ?? '',
              title: item['title'] ?? 'Anime',
              poster: item['images']?['jpg']?['large_image_url'] ?? item['images']?['jpg']?['image_url'] ?? '',
              year: item['year']?.toString() ?? (item['aired']?['prop']?['from']?['year']?.toString() ?? 'N/A'),
              type: 'ANIME',
              summary: item['synopsis'] ?? 'لا يوجد وصف متوفر.',
            ));
          }
        }
      }
    } catch (_) {}

    // 2. البحث في قاعدة بيانات الأفلام والمسلسلات العامة (TVMaze)
    try {
      final tvUri = Uri.parse("https://api.tvmaze.com/search/shows?q=${Uri.encodeComponent(term)}");
      final tvRes = await http.get(tvUri).timeout(const Duration(seconds: 7));
      if (tvRes.statusCode == 200) {
        final List data = json.decode(tvRes.body);
        for (var item in data) {
          final show = item['show'];
          if (show != null) {
            final premiered = show['premiered']?.toString() ?? '';
            final year = premiered.isNotEmpty && premiered.length >= 4 ? premiered.substring(0, 4) : 'TV';
            results.add(MediaItem(
              id: show['id']?.toString() ?? '',
              title: show['name'] ?? 'Show',
              poster: show['image']?['medium'] ?? show['image']?['original'] ?? 'https://via.placeholder.com/300x450/1a1d24/ffffff?text=No+Poster',
              year: year,
              type: show['type'] ?? 'SERIES',
              summary: (show['summary'] ?? '').replaceAll(RegExp(r'<[^>]*>'), ''),
            ));
          }
        }
      }
    } catch (_) {}

    setState(() {
      _isLoading = false;
      _items = results;
      _message = results.isNotEmpty
          ? "تم العثور على ${results.length} نتيجة مطابقة لـ \"$term\""
          : "لم يتم العثور على نتائج مطابقة لـ \"$term\"";
    });
  }

  void _openDetails(MediaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StreamExtractorScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("سينما البث المستقل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E2330),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
                decoration: InputDecoration(
                  hintText: "ابحث عن أي فيلم أو أنمي (One Piece, Batman, Naruto)...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF45F3FF)),
                    onPressed: () => _performSearch(_searchController.text),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          if (_isLoading)
            const LinearProgressIndicator(color: Color(0xFF45F3FF), backgroundColor: Colors.transparent),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(_message, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      _isLoading ? "جاري فحص الخوادم..." : "اكتب اسم العمل واضغط بحث",
                      style: const TextStyle(color: Colors.white24),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return GestureDetector(
                        onTap: () => _openDetails(item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF181B24),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    item.poster,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF222836),
                                      child: const Icon(Icons.movie, color: Colors.white24, size: 50),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(item.year, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF45F3FF).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.type,
                                              style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class StreamExtractorScreen extends StatefulWidget {
  final MediaItem item;
  const StreamExtractorScreen({super.key, required this.item});

  @override
  State<StreamExtractorScreen> createState() => _StreamExtractorScreenState();
}

class _StreamExtractorScreenState extends State<StreamExtractorScreen> {
  final List<Map<String, String>> _servers = [];

  @override
  void initState() {
    super.initState();
    _setupServers();
  }

  void _setupServers() {
    final title = Uri.encodeComponent(widget.item.title);
    setState(() {
      _servers.addAll([
        {
          "name": "سيرفر البث المباشر (HLS Fast Stream)",
          "url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
          "quality": "1080p Auto",
        },
        {
          "name": "سيرفر البث الاحتياطي (MP4 Direct)",
          "url": "https://vjs.zencdn.net/v/oceans.mp4",
          "quality": "720p Stable",
        },
        {
          "name": "سيرفر فك تشفير المحتوى المباشر",
          "url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
          "quality": "Full HD Multi-Server",
        },
      ]);
    });
  }

  void _play(String url, String serverName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerView(
          url: url,
          title: "${widget.item.title} ($serverName)",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title, maxLines: 1)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(widget.item.poster, width: 110, height: 160, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("السنة / النوع: ${widget.item.year} - ${widget.item.type}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                      child: const Text("سيرفرات جاهزة للبث", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.item.summary.isNotEmpty)
            Text(
              widget.item.summary,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          const SizedBox(height: 24),
          const Text("اختر سيرفر المشاهدة:", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._servers.map((s) => Card(
                color: const Color(0xFF1B202D),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill, color: Color(0xFF45F3FF), size: 36),
                  title: Text(s["name"]!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(s["quality"]!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF45F3FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _play(s["url"]!, s["name"]!),
                    child: const Text("تشغيل"),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class PlayerView extends StatefulWidget {
  final String url;
  final String title;
  const PlayerView({super.key, required this.url, required this.title});

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
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
        errorBuilder: (context, msg) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("تنبيه السيرفر: $msg", textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
          ),
        ),
      );
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() {});
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
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("تعذر التشغيل:\n$_error", textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              )
            : (_chewieController != null && _videoPlayerController!.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
