import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AnimeStreamHome(),
  ));
}

class AnimeStreamHome extends StatefulWidget {
  const AnimeStreamHome({super.key});

  @override
  State<AnimeStreamHome> createState() => _AnimeStreamHomeState();
}

class _AnimeStreamHomeState extends State<AnimeStreamHome> {
  final TextEditingController _searchController = TextEditingController(text: "One Piece");
  List<dynamic> _animeList = [];
  bool _loading = false;
  String _status = "ابحث عن أي أنمي لمشاهدة حلقاته الحقيقية";

  @override
  void initState() {
    super.initState();
    _searchAnime("One Piece");
  }

  Future<void> _searchAnime(String query) async {
    final term = query.trim();
    if (term.isEmpty) return;

    setState(() {
      _loading = true;
      _status = "🔍 جاري البحث في سيرفرات الأنمي...";
      _animeList.clear();
    });

    try {
      // البحث عبر واجهة سحب الأنمي المباشرة
      final url = Uri.parse("https://api.consumet.org/anime/gogoanime/${Uri.encodeComponent(term)}");
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          setState(() {
            _animeList = data['results'];
            _loading = false;
            _status = "تم العثور على ${_animeList.length} عمل";
          });
          return;
        }
      }

      // سيرفر بحث بديل في حال تعطل الأول
      final fallbackUrl = Uri.parse("https://api.jikan.moe/v4/anime?q=${Uri.encodeComponent(term)}&limit=10");
      final fbRes = await http.get(fallbackUrl).timeout(const Duration(seconds: 8));
      if (fbRes.statusCode == 200) {
        final fbData = json.decode(fbRes.body);
        final list = fbData['data'] as List;
        setState(() {
          _animeList = list.map((item) => {
            'id': (item['title'] as String).toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-'),
            'title': item['title'],
            'image': item['images']?['jpg']?['large_image_url'] ?? '',
            'releaseDate': item['year']?.toString() ?? 'N/A'
          }).toList();
          _loading = false;
          _status = "تم جلب ${_animeList.length} عمل";
        });
        return;
      }

      setState(() {
        _loading = false;
        _status = "لم يتم العثور على نتائج.";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = "تعذر الاتصال بالسيرفر: $e";
      });
    }
  }

  void _openEpisodes(Map<String, dynamic> anime) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EpisodesScreen(animeId: anime['id'] ?? '', title: anime['title'] ?? '', image: anime['image'] ?? ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0D14),
      appBar: AppBar(
        title: const Text("محرك سحب وبث الأنمي المباشر", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF141724),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1C2030),
                      hintText: "اسم الأنمي بالإنجليزية...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onSubmitted: _searchAnime,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                  onPressed: () => _searchAnime(_searchController.text),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: Color(0xFF45F3FF)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(alignment: Alignment.centerRight, child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _animeList.length,
              itemBuilder: (context, index) {
                final item = _animeList[index];
                return GestureDetector(
                  onTap: () => _openEpisodes(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            child: Image.network(
                              item['image'] ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            item['title'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
      ),
    );
  }
}

class EpisodesScreen extends StatefulWidget {
  final String animeId;
  final String title;
  final String image;
  const EpisodesScreen({super.key, required this.animeId, required this.title, required this.image});

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  List<dynamic> _episodes = [];
  bool _loading = true;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _fetchEpisodes();
  }

  Future<void> _fetchEpisodes() async {
    try {
      final url = Uri.parse("https://api.consumet.org/anime/gogoanime/info/${widget.animeId}");
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['episodes'] != null && (data['episodes'] as List).isNotEmpty) {
          setState(() {
            _episodes = data['episodes'];
            _loading = false;
          });
          return;
        }
      }

      // إذا لم تعد الواجهة حلقات مفصلة، نولد الحلقات الأولى تلقائياً للتجربة المباشرة
      setState(() {
        _episodes = List.generate(20, (i) => {
          'id': "${widget.animeId}-episode-${i + 1}",
          'number': i + 1,
        });
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _episodes = List.generate(20, (i) => {
          'id': "${widget.animeId}-episode-${i + 1}",
          'number': i + 1,
        });
        _loading = false;
      });
    }
  }

  Future<void> _playEpisode(String episodeId, int epNum) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))),
    );

    String? videoUrl;

    try {
      final res = await http.get(Uri.parse("https://api.consumet.org/anime/gogoanime/watch/$episodeId")).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['sources'] != null && (data['sources'] as List).isNotEmpty) {
          // جلب مسار m3u8 الافتراضي الحقيقي
          final sources = data['sources'] as List;
          final defaultSource = sources.firstWhere(
            (s) => s['quality'] == 'default' || s['quality'] == 'backup',
            orElse: () => sources.first,
          );
          videoUrl = defaultSource['url'];
        }
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context); // إغلاق مؤشر التحميل

    if (videoUrl != null && videoUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RealPlayerScreen(url: videoUrl!, title: "${widget.title} - الحلقة $epNum"),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تعذر استخراج رابط هذه الحلقة من السيرفر، اختر حلقة أخرى.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0D14),
      appBar: AppBar(title: Text(widget.title, maxLines: 1), backgroundColor: const Color(0xFF141724)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final ep = _episodes[index];
                final epNum = ep['number'] ?? (index + 1);
                return Card(
                  color: const Color(0xFF171B26),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_outline, color: Color(0xFF45F3FF)),
                    title: Text("الحلقة $epNum", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Text("سحب وتشغيل", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12)),
                    onTap: () => _playEpisode(ep['id'], epNum),
                  ),
                );
              },
            ),
    );
  }
}

class RealPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const RealPlayerScreen({super.key, required this.url, required this.title});

  @override
  State<RealPlayerScreen> createState() => _RealPlayerScreenState();
}

class _RealPlayerScreenState extends State<RealPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startVideo();
  }

  Future<void> _startVideo() async {
    try {
      final uri = Uri.parse(widget.url);
      _videoPlayerController = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0 ? _videoPlayerController!.value.aspectRatio : 16 / 9,
        allowFullScreen: true,
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
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.transparent),
      body: Center(
        child: _error != null
            ? Text("خطأ في تشغيل الرابط المباشر:\n$_error", textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))
            : (_chewieController != null && _videoPlayerController!.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
