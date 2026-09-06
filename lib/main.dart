import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

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
        scaffoldBackgroundColor: const Color(0xFF07090E),
        primaryColor: const Color(0xFFE50914),
        cardColor: const Color(0xFF0F1422),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF0F1422),
          secondary: Color(0xFF00F0FF),
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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _items = [];
  List<dynamic> _movies = [];
  List<dynamic> _series = [];

  int _offset = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _currentFilter = 'الرئيسية';

  final List<Map<String, String>> _categoriesList = [
    {'name': 'الكل', 'id': 'all'},
    {'name': 'أكشن', 'id': 'Action'},
    {'name': 'مغامرة', 'id': 'Adventure'},
    {'name': 'أنمي', 'id': 'Animation'},
    {'name': 'كوميديا', 'id': 'Comedy'},
    {'name': 'جريمة', 'id': 'Crime'},
    {'name': 'دراما', 'id': 'Drama'},
    {'name': 'رعب', 'id': 'Horror'},
    {'name': 'خيال علمي', 'id': 'Sci-Fi'},
    {'name': 'غموض', 'id': 'Mystery'},
    {'name': 'وثائقي', 'id': 'Documentary'},
  ];

  @override
  void initState() {
    super.initState();
    StreamService.startRelayWorker();
    _loadCeeContent(reset: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _loadCeeContent(reset: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCeeContent({bool reset = false, String? categoryQuery}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    String urlStr;
    if (categoryQuery != null && categoryQuery != 'all' && categoryQuery != 'الكل') {
      final b64 = base64.encode(utf8.encode(categoryQuery)).replaceAll('=', '');
      urlStr = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/24/video_title_search/$b64/itemsPerPage/24/pageNumber/${_offset ~/ 24}/level/0';
    } else {
      urlStr = 'https://cee.buzz/api/android/newlyVideosItems/level/0/offset/$_offset/';
    }

    try {
      final res = await http.get(Uri.parse(urlStr), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Accept': 'application/json, text/plain, */*',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        List list = (decoded is List) ? decoded : (decoded['articles'] ?? decoded['data'] ?? []);

        if (mounted) {
          setState(() {
            if (reset) {
              _items = list;
            } else {
              _items.addAll(list);
            }

            if (list.length < 8) {
              _hasMore = false;
            } else {
              _offset += 24;
            }

            _movies = _items.where((it) {
              final k = it['kind']?.toString() ?? '1';
              final s = it['season']?.toString() ?? '0';
              return k == '1' && (s == '0' || s.isEmpty);
            }).toList();

            _series = _items.where((it) {
              final k = it['kind']?.toString() ?? '1';
              final s = it['season']?.toString() ?? '0';
              return k != '1' || (s != '0' && s.isNotEmpty);
            }).toList();

            _isLoadingInitial = false;
            _isLoadingMore = false;
          });

          // المزامنة الصامتة في Firebase لكل ما تم جلبه
          if (list.isNotEmpty) {
            _syncItemsToRelay(list);
          }
        }
      } else {
        if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  void _syncItemsToRelay(List raw) {
    final List<Map<String, String>> batch = [];
    for (var it in raw.take(20)) {
      final nb = it['nb']?.toString();
      final title = it['en_title'] ?? it['ar_title'] ?? '';
      if (nb != null && nb.isNotEmpty) {
        batch.add({'id': nb, 'title': title});
      }
    }
    StreamService.preCacheMovieTitles(batch);
  }

  void _searchCee(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    List results = [];
    try {
      final b64 = base64.encode(utf8.encode(clean)).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/30/video_title_search/$b64/itemsPerPage/30/pageNumber/0/level/0'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        results = (decoded is List) ? decoded : (decoded['articles'] ?? []);
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
      if (results.isNotEmpty) {
        setState(() {
          _items = results;
          _hasMore = false;
          _currentFilter = 'نتائج البحث: $clean';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لم يتم العثور على أعمال مطابقة لـ "$clean"')),
        );
      }
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Drawer(
          backgroundColor: const Color(0xFF0F1422),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFE50914), Color(0xFF0F1422)]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: const [
                    Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    SizedBox(height: 4),
                    Text('جميع تصنيفات وأقسام سينمانا', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
                title: const Text('الرئيسية'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentFilter = 'الرئيسية');
                  _loadCeeContent(reset: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                title: const Text('المفضلة'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              const Divider(color: Colors.white12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('الأقسام والتصنيفات:', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              ..._categoriesList.map((cat) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.movie_filter_outlined, size: 20, color: Colors.white60),
                    title: Text(cat['name']!),
                    selected: _currentFilter == cat['name'],
                    selectedColor: const Color(0xFF00F0FF),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentFilter = cat['name']!);
                      _loadCeeContent(reset: true, categoryQuery: cat['id']);
                    },
                  )),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE50914)),
                ),
                child: const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 18),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFF3344), Color(0xFF00F0FF)],
                ).createShader(bounds),
                child: const Text('ONEBR TV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
          ],
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: () => _loadCeeContent(reset: true),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _searchCee,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم (عربي أو إنجليزي)...',
                            hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF00F0FF)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadCeeContent(reset: true);
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F1422),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),

                      if (_items.isNotEmpty && _currentFilter == 'الرئيسية')
                        _buildHeroBanner(_items.first, screenWidth),

                      if (_currentFilter == 'الرئيسية') ...[
                        if (_movies.isNotEmpty) _buildShelf('🎬 أحدث الأفلام المتوفرة', _movies),
                        if (_series.isNotEmpty) _buildShelf('📺 أحدث المسلسلات والأنمي', _series),
                      ],

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                        child: Text(
                          _currentFilter == 'الرئيسية' ? '🌐 جميع العروض المتوفرة' : '📂 $_currentFilter',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),

                      _buildGrid(_items),

                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
                        ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeroBanner(Map<String, dynamic> item, double width) {
    final title = item['ar_title'] ?? item['en_title'] ?? '';
    final poster = item['imgThumbObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['img'] ?? '';

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: width * 0.52,
          width: double.infinity,
          decoration: BoxDecoration(
            image: poster.toString().isNotEmpty
                ? DecorationImage(image: NetworkImage(poster.toString()), fit: BoxFit.cover)
                : null,
          ),
        ),
        Container(
          height: width * 0.52,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF07090E), Colors.transparent],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                onPressed: () => _openDetails(item),
                icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                label: const Text('مشاهدة وتفاصيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShelf(String title, List<dynamic> list) {
    final cardWidth = (MediaQuery.of(context).size.width * 0.31).clamp(105.0, 140.0);
    final cardHeight = cardWidth * 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        SizedBox(
          height: cardHeight + 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final item = list[i];
              final mTitle = item['ar_title'] ?? item['en_title'] ?? '';
              final poster = item['imgThumbObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['img'] ?? '';
              final score = item['stars']?.toString() ?? '8.0';

              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: cardWidth,
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
                        child: poster.toString().isNotEmpty
                            ? Image.network(poster.toString(), height: cardHeight, width: double.infinity, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(height: cardHeight, color: const Color(0xFF172033)))
                            : Container(height: cardHeight, color: const Color(0xFF172033)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('⭐ $score', style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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

  Widget _buildGrid(List<dynamic> list) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.58,
        ),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          final title = item['ar_title'] ?? item['en_title'] ?? '';
          final poster = item['imgThumbObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['img'] ?? '';
          final stars = item['stars']?.toString() ?? '8.0';

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1422),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: poster.toString().isNotEmpty
                          ? Image.network(poster.toString(), width: double.infinity, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF172033)))
                          : Container(color: const Color(0xFF172033)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('⭐ $stars', style: const TextStyle(fontSize: 9.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة التفاصيل (المواسم والحلقات والقصة)
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunching = false;
  bool _isFav = false;
  bool _isLoadingEpisodes = false;
  List<dynamic> _episodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
    final k = widget.media['kind']?.toString() ?? '1';
    final s = widget.media['season']?.toString() ?? '0';
    _isSeries = k != '1' || (s != '0' && s.isNotEmpty);

    if (_isSeries) {
      _loadSeriesEpisodesList();
    }
  }

  void _checkFav() async {
    final nb = widget.media['nb']?.toString() ?? '';
    final isFav = await FavoritesService.isFavorited(nb);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFav() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
    if (mounted) {
      setState(() => _isFav = newState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState ? 'تمت إضافة العمل إلى المفضلة ⭐' : 'تمت إزالة العمل من المفضلة'),
          backgroundColor: newState ? const Color(0xFF10B981) : const Color(0xFFE50914),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // الرابط الصحيح من سينمانا لجلب مئات الحلقات للمسلسلات
  Future<void> _loadSeriesEpisodesList() async {
    setState(() => _isLoadingEpisodes = true);
    final nb = widget.media['nb'].toString();

    final urls = [
      'https://cee.buzz/api/android/video/V/2/itemsPerPage/50/series_episodes_list/$nb/level/0',
      'https://cee.buzz/api/android/allVideo/page/1/level/2/sub_id/$nb',
    ];

    for (var u in urls) {
      try {
        final res = await http.get(Uri.parse(u), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
          List list = (decoded is List) ? decoded : (decoded['articles'] ?? decoded['data'] ?? []);
          if (list.isNotEmpty) {
            if (mounted) setState(() => _episodes = list);
            break;
          }
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  void _playEpisode({String? targetNb, String? epTitle}) async {
    setState(() => _isLaunching = true);

    final nb = targetNb ?? widget.media['nb'].toString();
    final title = epTitle ?? widget.media['ar_title'] ?? widget.media['en_title'] ?? 'بث مباشر';
    final subFile = widget.media['arTranslationFile']?.toString() ?? '';

    final data = await StreamService.getVideoSource(nb);

    setState(() => _isLaunching = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: nb,
            title: title,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
            subtitleFileName: subFile,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تشغيل هذا الرابط حالياً'), backgroundColor: Color(0xFFE50914)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final enTitle = widget.media['en_title'] ?? '';
    final poster = widget.media['imgThumbObjUrl'] ?? widget.media['imgMediumThumbObjUrl'] ?? widget.media['img'] ?? '';
    final stars = widget.media['stars']?.toString() ?? '8.0';
    final year = widget.media['year']?.toString() ?? '2026';
    final story = widget.media['ar_content'] ?? widget.media['en_content'] ?? 'لا يوجد وصف متاح لهذا العمل حالياً.';

    String genres = '';
    if (widget.media['categories'] is List) {
      genres = (widget.media['categories'] as List)
          .map((c) => c['ar_title'] ?? c['en_title'] ?? '')
          .where((s) => s.toString().isNotEmpty)
          .join(' • ');
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: poster.toString().isNotEmpty
                        ? Image.network(poster.toString(), width: 110, height: 160, fit: BoxFit.cover)
                        : Container(width: 110, height: 160, color: const Color(0xFF172033)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                        if (enTitle.isNotEmpty && enTitle != title) ...[
                          const SizedBox(height: 3),
                          Text(enTitle, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                              child: Text('⭐ $stars', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            Text(year, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          ],
                        ),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(genres, style: const TextStyle(fontSize: 11.5, color: Color(0xFF00F0FF), fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isLaunching ? null : () => _playEpisode(),
                        icon: _isLaunching
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                        label: Text(_isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة العمل الآن',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1422),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _isFav ? const Color(0xFFF59E0B) : Colors.white24),
                    ),
                    child: IconButton(
                      icon: Icon(_isFav ? Icons.bookmark_added_rounded : Icons.bookmark_border_rounded,
                          color: _isFav ? const Color(0xFFF59E0B) : Colors.white70),
                      onPressed: _toggleFav,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4)),

              // حلقات المسلسل
              if (_isSeries) ...[
                const SizedBox(height: 24),
                const Text('حلقات المسلسل المتوفرة:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : _episodes.isEmpty
                        ? const Text('تم توفير هذا المسلسل برابط تشغيل مباشر.', style: TextStyle(color: Colors.white54, fontSize: 12))
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.3,
                            ),
                            itemCount: _episodes.length,
                            itemBuilder: (ctx, i) {
                              final ep = _episodes[i];
                              final epTitle = ep['ar_title'] ?? ep['title'] ?? 'حلقة ${i + 1}';
                              final epNb = ep['nb']?.toString() ?? ep['id']?.toString() ?? '';

                              return InkWell(
                                onTap: () => _playEpisode(targetNb: epNb, epTitle: '$title - $epTitle'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF172033),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Center(
                                    child: Text(epTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                            },
                          ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// المشغل مع حفظ واستئناف الدقيقة وتخطي المقدمة وإعدادات الترجمة
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final String subtitleFileName;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.subtitleFileName = '',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String? _currentUrl;
  String _selectedQualityName = '720p';
  bool _isReady = false;
  bool _showSkipIntroBtn = false;

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 16.0;
  List<Subtitle> _parsedSubtitles = [];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _startPlayback();
  }

  void _startPlayback() async {
    // جلب ملف الترجمة
    if (widget.subtitleFileName.isNotEmpty) {
      try {
        final subUrl = 'https://cnth2.cee.buzz/vascin-subtitles-files/${widget.subtitleFileName}';
        final res = await http.get(Uri.parse(subUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          _parsedSubtitles = _parseSrt(utf8.decode(res.bodyBytes));
        }
      } catch (_) {}
    }

    // استرجاع الدقيقة التي خرج عندها المستخدم
    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt('playback_pos_${widget.mediaId}') ?? 0;

    _initFastPlayer(_currentUrl!, startAtSecond: savedSeconds);
  }

  List<Subtitle> _parseSrt(String srtText) {
    final List<Subtitle> list = [];
    final pattern = RegExp(
        r'(\d+)\r?\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\r?\n([\s\S]*?)(?=\n\n|\r\n\r\n|$)');
    final matches = pattern.allMatches(srtText);

    int idx = 0;
    for (var m in matches) {
      final start = _parseDuration(m.group(2)!);
      final end = _parseDuration(m.group(3)!);
      final text = m.group(4)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (text.isNotEmpty) {
        list.add(Subtitle(index: idx++, start: start, end: end, text: text));
      }
    }
    return list;
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.replaceAll(',', '.').split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final secondsParts = parts[2].split('.');
    final seconds = int.parse(secondsParts[0]);
    final millis = int.parse(secondsParts[1].padRight(3, '0').substring(0, 3));
    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  void _initFastPlayer(String streamUrl, {int startAtSecond = 0}) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_saveAndTrackPosition);
    await _videoPlayerController?.dispose();

    setState(() {
      _isReady = false;
      _showSkipIntroBtn = false;
    });

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    await _videoPlayerController!.initialize();

    // الاستئناف من نفس الدقيقة فور التهيئة
    if (startAtSecond > 0 && startAtSecond < _videoPlayerController!.value.duration.inSeconds - 10) {
      await _videoPlayerController!.seekTo(Duration(seconds: startAtSecond));
    }

    _videoPlayerController!.addListener(_saveAndTrackPosition);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
      subtitle: (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) ? Subtitles(_parsedSubtitles) : null,
      subtitleBuilder: (context, subtitle) => Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white,
            fontSize: _subtitleFontSize,
            fontWeight: FontWeight.bold,
            height: 1.3,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black)],
          ),
          textAlign: TextAlign.center,
        ),
      ),
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFE50914),
        handleColor: const Color(0xFF00F0FF),
        bufferedColor: Colors.white24,
        backgroundColor: Colors.white10,
      ),
      additionalOptions: (context) {
        return <OptionItem>[
          OptionItem(
            onTap: (ctx) => _showQualitySheet(),
            iconData: Icons.hd_outlined,
            title: 'الجودة: $_selectedQualityName',
          ),
          OptionItem(
            onTap: (ctx) => _showSubtitleSettingsSheet(),
            iconData: Icons.subtitles_rounded,
            title: 'إعدادات الترجمة',
          ),
        ];
      },
    );

    if (mounted) setState(() => _isReady = true);
  }

  // حفظ الدقيقة لحظياً وفحص وقت شارة البداية
  void _saveAndTrackPosition() async {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

    final seconds = _videoPlayerController!.value.position.inSeconds;

    // حفظ الموضع كل 5 ثوانٍ
    if (seconds > 0 && seconds % 5 == 0) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('playback_pos_${widget.mediaId}', seconds);
    }

    // إظهار زر تخطي المقدمة
    final shouldShow = seconds >= 2 && seconds <= 120;
    if (shouldShow != _showSkipIntroBtn && mounted) {
      setState(() => _showSkipIntroBtn = shouldShow);
    }
  }

  void _skipIntro() {
    if (_videoPlayerController == null) return;
    _videoPlayerController!.seekTo(_videoPlayerController!.value.position + const Duration(seconds: 85));
    setState(() => _showSkipIntroBtn = false);
  }

  void _showSubtitleSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إعدادات الترجمة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white12),
              SwitchListTile(
                title: const Text('تفعيل الترجمة'),
                value: _subtitlesEnabled,
                activeColor: const Color(0xFF00F0FF),
                onChanged: (val) {
                  setSheetState(() => _subtitlesEnabled = val);
                  setState(() => _subtitlesEnabled = val);
                  _initFastPlayer(_currentUrl!, startAtSecond: _videoPlayerController?.value.position.inSeconds ?? 0);
                },
              ),
              const SizedBox(height: 8),
              const Text('حجم خط الترجمة:', style: TextStyle(fontSize: 13, color: Colors.white70)),
              Slider(
                value: _subtitleFontSize,
                min: 12.0,
                max: 26.0,
                divisions: 7,
                activeColor: const Color(0xFFE50914),
                label: _subtitleFontSize.round().toString(),
                onChanged: (val) {
                  setSheetState(() => _subtitleFontSize = val);
                  setState(() => _subtitleFontSize = val);
                  _initFastPlayer(_currentUrl!, startAtSecond: _videoPlayerController?.value.position.inSeconds ?? 0);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.qualities.map((q) {
            final res = q['resolution'] ?? 'تلقائي';
            final url = q['url'];
            final isSelected = url == _currentUrl;
            return ListTile(
              title: Text(res, style: TextStyle(color: isSelected ? const Color(0xFF00F0FF) : Colors.white)),
              trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF00F0FF)) : null,
              onTap: () {
                Navigator.pop(context);
                if (!isSelected && url != null) {
                  final currentSeconds = _videoPlayerController?.value.position.inSeconds ?? 0;
                  setState(() {
                    _currentUrl = url;
                    _selectedQualityName = res;
                  });
                  // العودة لنفس الدقيقة عند تبديل الدقة
                  _initFastPlayer(url, startAtSecond: currentSeconds);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // حفظ الموضع النهائي عند الخروج من الفيديو
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('playback_pos_${widget.mediaId}', _videoPlayerController!.value.position.inSeconds);
      });
    }
    _videoPlayerController?.removeListener(_saveAndTrackPosition);
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
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Chewie(controller: _chewieController!),
                  if (_showSkipIntroBtn)
                    Positioned(
                      bottom: 75,
                      left: 20,
                      child: InkWell(
                        onTap: _skipIntro,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward_rounded, color: Color(0xFFF59E0B), size: 18),
                              SizedBox(width: 6),
                              Text('تخطي المقدمة (+85s)',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
      ),
    );
  }
}

// -------------------------------------------------------------
// المفضلة
// -------------------------------------------------------------
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final list = await FavoritesService.getFavorites();
    if (mounted) setState(() { _favorites = list; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('⭐ قائمة المفضلة'), backgroundColor: const Color(0xFF0F1422)),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : _favorites.isEmpty
                ? const Center(child: Text('لم تقم بإضافة أي أعمال للمفضلة بعد', style: TextStyle(color: Colors.white54)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, i) {
                      final item = _favorites[i];
                      final poster = item['imgThumbObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['img'] ?? '';
                      final title = item['ar_title'] ?? item['en_title'] ?? '';

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)),
                          ).then((_) => _load());
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                  child: poster.toString().isNotEmpty
                                      ? Image.network(poster.toString(), width: double.infinity, fit: BoxFit.cover)
                                      : Container(color: const Color(0xFF172033)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(5.0),
                                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
