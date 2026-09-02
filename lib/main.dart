import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CleanStreamApp(),
  ));
}

class MediaEntry {
  final String id;
  final String title;
  final String poster;
  final String year;
  final bool isAnime;

  MediaEntry({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
    this.isAnime = false,
  });
}

// قائمة أعمال مثبتة مع بوسترات مستقرة
final List<MediaEntry> catalog = [
  MediaEntry(
    id: "tt0388629",
    title: "One Piece",
    poster: "https://cdn.myanimelist.net/images/anime/6/73245l.jpg",
    year: "1999",
    isAnime: true,
  ),
  MediaEntry(
    id: "tt0988824",
    title: "Naruto Shippuden",
    poster: "https://cdn.myanimelist.net/images/anime/1565/111305l.jpg",
    year: "2007",
    isAnime: true,
  ),
  MediaEntry(
    id: "tt1877514",
    title: "The Batman",
    poster: "https://image.tmdb.org/t/p/w500/74xTEgt7R36Fpooo50r9T25onhq.jpg",
    year: "2022",
  ),
  MediaEntry(
    id: "tt2560140",
    title: "Attack on Titan",
    poster: "https://cdn.myanimelist.net/images/anime/10/47347l.jpg",
    year: "2013",
    isAnime: true,
  ),
  MediaEntry(
    id: "tt0204993",
    title: "Inuyasha",
    poster: "https://cdn.myanimelist.net/images/anime/13/11262l.jpg",
    year: "2000",
    isAnime: true,
  ),
  MediaEntry(
    id: "tt0434706",
    title: "Bleach",
    poster: "https://cdn.myanimelist.net/images/anime/3/40451l.jpg",
    year: "2004",
    isAnime: true,
  ),
  MediaEntry(
    id: "tt0816692",
    title: "Interstellar",
    poster: "https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
    year: "2014",
  ),
  MediaEntry(
    id: "tt1375666",
    title: "Inception",
    poster: "https://image.tmdb.org/t/p/w500/edv5CZvWj09vOvt2JWv49740U8h.jpg",
    year: "2010",
  ),
];

class CleanStreamApp extends StatefulWidget {
  const CleanStreamApp({super.key});

  @override
  State<CleanStreamApp> createState() => _CleanStreamAppState();
}

class _CleanStreamAppState extends State<CleanStreamApp> {
  final TextEditingController _ctrl = TextEditingController();
  List<MediaEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(catalog);
  }

  void _search(String text) {
    final q = text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(catalog);
      } else {
        _filtered = catalog.where((m) => m.title.toLowerCase().contains(q)).toList();
      }
    });
  }

  void _openStream(MediaEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmbeddedCleanPlayer(entry: entry)),
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
                hintText: "ابحث في الكتالوج (One Piece, Batman, Inuyasha)...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF191D2C),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: _search,
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
                  onTap: () => _openStream(item),
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
                                  const Text("تشغيل مباشر ▶", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 11, fontWeight: FontWeight.bold)),
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

// مشغل العرض السينمائي الكامل النظيف: ينظف الصفحة تماماً من أي إعلانات ويبقي الفيديو فقط
class EmbeddedCleanPlayer extends StatefulWidget {
  final MediaEntry entry;
  const EmbeddedCleanPlayer({super.key, required this.entry});

  @override
  State<EmbeddedCleanPlayer> createState() => _EmbeddedCleanPlayerState();
}

class _EmbeddedCleanPlayerState extends State<EmbeddedCleanPlayer> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    final String targetUrl = "https://multiembed.mov/?video_id=${widget.entry.id}";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
              // حقن كود CSS & JS لحذف الإعلانات وجعل حاوية الفيديو تمتد للشاشة بالكامل
              _controller.runJavaScript("""
                try {
                  const style = document.createElement('style');
                  style.innerHTML = `
                    body, html { margin:0!important; padding:0!important; width:100%!important; height:100%!important; background:#000!important; overflow:hidden!important; }
                    iframe, video { position:fixed!important; top:0!important; left:0!important; width:100vw!important; height:100vh!important; z-index:999999!important; border:none!important; }
                    .ad, [class*='banner'], [id*='pop'], [class*='ads'] { display:none!important; }
                  `;
                  document.head.appendChild(style);
                } catch(e) {}
              """);
            }
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            // حظر النوافذ المنبثقة الإعلانية وتفادي فتح أي تطبيق آخر
            if (url.contains('ad') || url.contains('click') || url.contains('pop') || url.contains('youtube') || url.contains('banner')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(targetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.entry.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF45F3FF)),
                  SizedBox(height: 16),
                  Text("جاري تهيئة مشغل البث عالي الدقة...", style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
