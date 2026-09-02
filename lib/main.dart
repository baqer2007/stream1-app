import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  Future<void> _performSearch(String query) async {
    final term = query.trim();
    if (term.isEmpty) return;

    setState(() {
      _isLoading = true;
      _message = "🔍 جاري البحث في قواعد البيانات الحرة...";
      _items.clear();
    });

    List<MediaItem> results = [];

    // 1. فحص قاعدة بيانات الأنمي العالمية
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

    // 2. فحص قاعدة بيانات الأفلام والمسلسلات العامة
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
              id: show['externals']?['imdb'] ?? show['id']?.toString() ?? '',
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
          ? "تم العثور على ${results.length} نتيجة لـ \"$term\""
          : "لم يتم العثور على نتائج لـ \"$term\"";
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
                  hintText: "ابحث بالاسم (One Piece, Batman, Naruto)...",
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
                      _isLoading ? "جاري الفحص..." : "اكتب اسم العمل واضغط بحث",
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
    _setupRealServers();
  }

  void _setupRealServers() {
    final title = Uri.encodeComponent(widget.item.title);
    final id = widget.item.id;

    setState(() {
      // 1. سيرفر البث المباشر الفعلي المخصص للأفلام والمسلسلات والأنمي
      _servers.add({
        "name": "سيرفر البث الحقيقي (MultiEmbed HD)",
        "url": "https://multiembed.mov/?video_id=$title",
        "quality": "1080p / Multi Servers",
        "isWeb": "true",
      });

      // 2. سيرفر البث البديل (SuperEmbed)
      _servers.add({
        "name": "سيرفر المشاهدة السريع (VidLink)",
        "url": "https://vidlink.pro/movie/$title",
        "quality": "FHD Multi-Player",
        "isWeb": "true",
      });

      // 3. سيرفر البث المباشر (2Embed)
      _servers.add({
        "name": "سيرفر البث السحابي (2Embed Stream)",
        "url": "https://www.2embed.cc/embed/$title",
        "quality": "Direct Embed Player",
        "isWeb": "true",
      });
    });
  }

  void _play(String url, String serverName, bool isWeb) {
    if (isWeb) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebStreamPlayerScreen(url: url, title: "${widget.item.title} - $serverName"),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativePlayerScreen(url: url, title: "${widget.item.title} - $serverName"),
        ),
      );
    }
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
                      child: const Text("سيرفرات البث الفعلي جاهزة", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12)),
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
          const Text("اختر سيرفر المشاهدة الحقيقي:", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                    onPressed: () => _play(s["url"]!, s["name"]!, s["isWeb"] == "true"),
                    child: const Text("تشغيل العمل 🎬"),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// المشغل السحابي الحقيقي لسيرفرات الأفلام والأنمي
class WebStreamPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const WebStreamPlayerScreen({super.key, required this.url, required this.title});

  @override
  State<WebStreamPlayerScreen> createState() => _WebStreamPlayerScreenState();
}

class _WebStreamPlayerScreenState extends State<WebStreamPlayerScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            setState(() {
              _loading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF45F3FF)),
            ),
        ],
      ),
    );
  }
}

// المشغل المباشر لملفات MP4 / M3U8
class NativePlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const NativePlayerScreen({super.key, required this.url, required this.title});

  @override
  State<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends State<NativePlayerScreen> {
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
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
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
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 14)), backgroundColor: Colors.transparent),
      body: Center(
        child: _error != null
            ? Text("تعذر التشغيل: $_error", style: const TextStyle(color: Colors.redAccent))
            : (_chewieController != null && _videoPlayerController!.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
