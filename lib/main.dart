import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: UniversalCinemaApp(),
  ));
}

class MediaEntry {
  final String id;
  final String title;
  final String poster;
  final String year;
  final bool isSeries;

  MediaEntry({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
    this.isSeries = false,
  });
}

final List<MediaEntry> catalog = [
  MediaEntry(
    id: "tt0388629",
    title: "One Piece",
    poster: "https://cdn.myanimelist.net/images/anime/6/73245l.jpg",
    year: "1999",
    isSeries: true,
  ),
  MediaEntry(
    id: "tt0988824",
    title: "Naruto Shippuden",
    poster: "https://cdn.myanimelist.net/images/anime/1565/111305l.jpg",
    year: "2007",
    isSeries: true,
  ),
  MediaEntry(
    id: "tt2560140",
    title: "Attack on Titan",
    poster: "https://cdn.myanimelist.net/images/anime/10/47347l.jpg",
    year: "2013",
    isSeries: true,
  ),
  MediaEntry(
    id: "tt0204993",
    title: "Inuyasha",
    poster: "https://cdn.myanimelist.net/images/anime/13/11262l.jpg",
    year: "2000",
    isSeries: true,
  ),
  MediaEntry(
    id: "tt0434706",
    title: "Bleach",
    poster: "https://cdn.myanimelist.net/images/anime/3/40451l.jpg",
    year: "2004",
    isSeries: true,
  ),
  MediaEntry(
    id: "tt1877514",
    title: "The Batman",
    poster: "https://image.tmdb.org/t/p/w500/74xTEgt7R36Fpooo50r9T25onhq.jpg",
    year: "2022",
    isSeries: false,
  ),
  MediaEntry(
    id: "tt0816692",
    title: "Interstellar",
    poster: "https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
    year: "2014",
    isSeries: false,
  ),
  MediaEntry(
    id: "tt1375666",
    title: "Inception",
    poster: "https://image.tmdb.org/t/p/w500/edv5CZvWj09vOvt2JWv49740U8h.jpg",
    year: "2010",
    isSeries: false,
  ),
];

class UniversalCinemaApp extends StatefulWidget {
  const UniversalCinemaApp({super.key});

  @override
  State<UniversalCinemaApp> createState() => _UniversalCinemaAppState();
}

class _UniversalCinemaAppState extends State<UniversalCinemaApp> {
  final TextEditingController _ctrl = TextEditingController();
  List<MediaEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(catalog);
  }

  void _filter(String text) {
    final q = text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(catalog);
      } else {
        _filtered = catalog.where((m) => m.title.toLowerCase().contains(q)).toList();
      }
    });
  }

  void _openPlayer(MediaEntry item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MultiServerPlayer(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(
        title: const Text("سينما البث المباشر المستقل", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF141724),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "ابحث في الأعمال (One Piece, Batman, Interstellar)...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF191D2C),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: _filter,
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.67,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final item = _filtered[i];
                return GestureDetector(
                  onTap: () => _openPlayer(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF151824),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            child: Image.network(
                              item.poster,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 45, color: Colors.white24),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(item.year, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text(item.isSeries ? "مسلسل" : "فيلم", style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                  )
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class MultiServerPlayer extends StatefulWidget {
  final MediaEntry item;
  const MultiServerPlayer({super.key, required this.item});

  @override
  State<MultiServerPlayer> createState() => _MultiServerPlayerState();
}

class _MultiServerPlayerState extends State<MultiServerPlayer> {
  late final WebViewController _controller;
  int _currentServer = 0;
  bool _isLoading = true;

  List<String> _buildServerUrls() {
    final id = widget.item.id;
    final isS = widget.item.isSeries;

    return [
      // سيرفر 1: MultiEmbed مع التمييز الدقيق للأنمي/المسلسلات
      isS
          ? "https://multiembed.mov/?video_id=$id&s=1&e=1"
          : "https://multiembed.mov/?video_id=$id",
      // سيرفر 2: Smashystream السريع
      isS
          ? "https://embed.smashystream.com/playere.php?imdb=$id&season=1&episode=1"
          : "https://embed.smashystream.com/playere.php?imdb=$id",
      // سيرفر 3: 2Embed Cloud
      isS
          ? "https://www.2embed.cc/embedtv/$id&s=1&e=1"
          : "https://www.2embed.cc/embed/$id",
    ];
  }

  @override
  void initState() {
    super.initState();
    final urls = _buildServerUrls();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            // حظر النوافذ الإعلانية المنبثقة
            if (url.contains('ad') || url.contains('pop') || url.contains('click') || url.contains('banner')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(urls[_currentServer]));
  }

  void _switchServer(int index) {
    setState(() {
      _currentServer = index;
      _isLoading = true;
    });
    final urls = _buildServerUrls();
    _controller.loadRequest(Uri.parse(urls[index]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.item.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF141724),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.dns, color: Color(0xFF45F3FF)),
            tooltip: "تبديل السيرفر",
            onSelected: _switchServer,
            itemBuilder: (context) => [
              PopupMenuItem(value: 0, child: Text("سيرفر 1 (الأساسي)${_currentServer == 0 ? ' ✓' : ''}")),
              PopupMenuItem(value: 1, child: Text("سيرفر 2 (السريع)${_currentServer == 1 ? ' ✓' : ''}")),
              PopupMenuItem(value: 2, child: Text("سيرفر 3 (الاحتياطي)${_currentServer == 2 ? ' ✓' : ''}")),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF45F3FF)),
                    SizedBox(height: 14),
                    Text("جاري تشغيل الفيديو...", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
