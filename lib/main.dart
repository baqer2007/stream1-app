import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
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

  List<dynamic> _allLoaded = [];
  List<dynamic> _movies = [];
  List<dynamic> _series = [];
  List<dynamic> _displayedGrid = [];

  int _offset = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _selectedCategoryName = 'الرئيسية';

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'title': 'الكل'},
    {'id': 'action', 'title': 'أكشن'},
    {'id': 'adventure', 'title': 'مغامرة'},
    {'id': 'animation', 'title': 'أنمي ورسوم متحركة'},
    {'id': 'comedy', 'title': 'كوميديا'},
    {'id': 'crime', 'title': 'جريمة'},
    {'id': 'drama', 'title': 'دراما'},
    {'id': 'horror', 'title': 'رعب'},
    {'id': 'sci-fi', 'title': 'خيال علمي'},
    {'id': 'romance', 'title': 'رومانسي'},
  ];

  @override
  void initState() {
    super.initState();
    StreamService.startRelayWorker();
    _fetchFeed(reset: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _fetchFeed(reset: false);
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

  Future<void> _fetchFeed({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    List<dynamic> fetched = [];
    final endpoints = [
      'https://cee.buzz/api/android/newlyVideosItems/level/0/offset/$_offset/',
      'https://cee.buzz/api/android/allVideo/page/${(_offset ~/ 12) + 1}/level/0',
    ];

    for (var ep in endpoints) {
      try {
        final res = await http.get(Uri.parse(ep), headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
          'Referer': 'https://cee.buzz/home',
          'Accept': 'application/json, text/plain, */*',
        }).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && res.body.isNotEmpty) {
          dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is List) {
            fetched = decoded;
            break;
          } else if (decoded is Map) {
            final l = decoded['articles'] ?? decoded['data'] ?? decoded['videos'];
            if (l is List && l.isNotEmpty) {
              fetched = l;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        if (reset) {
          _allLoaded = fetched;
        } else {
          _allLoaded.addAll(fetched);
        }

        if (fetched.length < 8) {
          _hasMore = false;
        } else {
          _offset += 12;
        }

        // فصل الأفلام والمسلسلات اعتماداً على kind و season
        _movies = _allLoaded.where((it) {
          final k = it['kind']?.toString() ?? '1';
          return k == '1' && (it['season'] == null || it['season'] == '0');
        }).toList();

        _series = _allLoaded.where((it) {
          final k = it['kind']?.toString() ?? '1';
          return k != '1' || (it['season'] != null && it['season'] != '0');
        }).toList();

        _applyCategoryFilter(_selectedCategoryName);

        _isLoadingInitial = false;
        _isLoadingMore = false;
      });

      // حفظ استباقي في Firebase للأشخاص خارج العراق
      if (_allLoaded.isNotEmpty) {
        _syncToFirebaseRelay(_allLoaded.take(20).toList());
      }
    }
  }

  void _syncToFirebaseRelay(List items) {
    final List<Map<String, String>> batch = [];
    for (var it in items) {
      final nb = it['nb']?.toString();
      final title = it['en_title'] ?? it['ar_title'] ?? '';
      if (nb != null) {
        batch.add({'id': nb, 'title': title});
      }
    }
    StreamService.preCacheMovieTitles(batch);
  }

  void _applyCategoryFilter(String genreTitle) {
    setState(() {
      _selectedCategoryName = genreTitle;
      if (genreTitle == 'الرئيسية' || genreTitle == 'الكل') {
        _displayedGrid = List.from(_allLoaded);
      } else {
        _displayedGrid = _allLoaded.where((it) {
          final cats = it['categories'];
          if (cats is List) {
            return cats.any((c) =>
                (c['ar_title']?.toString().contains(genreTitle) ?? false) ||
                (c['en_title']?.toString().toLowerCase().contains(genreTitle.toLowerCase()) ?? false));
          }
          return false;
        }).toList();
      }
    });
  }

  void _performSearch(String query) async {
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
      final urls = [
        'https://cee.buzz/api/android/video/V/2/itemsPerPage/20/video_title_search/$b64/itemsPerPage/12/pageNumber/0/level/0',
        'https://cee.buzz/api/android/AdvancedSearch?videoTitle=${Uri.encodeComponent(clean)}',
      ];

      for (var u in urls) {
        try {
          final res = await http.get(Uri.parse(u), headers: {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://cee.buzz/',
          }).timeout(const Duration(seconds: 6));

          if (res.statusCode == 200) {
            dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
            if (decoded is List && decoded.isNotEmpty) {
              results = decoded;
              break;
            } else if (decoded is Map) {
              final l = decoded['articles'] ?? decoded['data'];
              if (l is List && l.isNotEmpty) {
                results = l;
                break;
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
      if (results.isNotEmpty) {
        setState(() {
          _displayedGrid = results;
          _hasMore = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على نتائج مطابقة لـ "$clean"'),
            backgroundColor: const Color(0xFFE50914),
          ),
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
        // القائمة الجانبية (Drawer)
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
                    Text('مكتبة الأفلام والمسلسلات الشاملة', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
                title: const Text('الصفحة الرئيسية'),
                onTap: () {
                  Navigator.pop(context);
                  _applyCategoryFilter('الرئيسية');
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                title: const Text('قائمة المفضلة'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              const Divider(color: Colors.white12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('التصنيفات والأنواع', style: TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.bold)),
              ),
              ..._genres.map((g) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.movie_creation_outlined, size: 20, color: Colors.white60),
                    title: Text(g['title']),
                    selected: _selectedCategoryName == g['title'],
                    selectedColor: const Color(0xFF00F0FF),
                    onTap: () {
                      Navigator.pop(context);
                      _applyCategoryFilter(g['title']);
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
                onRefresh: () => _fetchFeed(reset: true),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // شريط البحث
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _performSearch,
                          decoration: InputDecoration(
                            hintText: 'ابحث عن أي فيلم، مسلسل أو أنمي...',
                            hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF00F0FF)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _fetchFeed(reset: true);
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F1422),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),

                      if (_displayedGrid.isNotEmpty && _selectedCategoryName == 'الرئيسية')
                        _buildHeroBanner(_displayedGrid.first, screenWidth),

                      if (_selectedCategoryName == 'الرئيسية') ...[
                        if (_movies.isNotEmpty) _buildMediaShelf('🎬 أحدث الأفلام المتوفرة', _movies),
                        if (_series.isNotEmpty) _buildMediaShelf('📺 المسلسلات والدراما المتجددة', _series),
                      ],

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                        child: Text(
                          _selectedCategoryName == 'الرئيسية' ? '🌐 جميع العروض المتوفرة' : '📂 تصنيف: $_selectedCategoryName',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),

                      _buildMediaGrid(_displayedGrid),

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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
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

  Widget _buildMediaShelf(String title, List<dynamic> list) {
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

  Widget _buildMediaGrid(List<dynamic> list) {
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
          final stars = item['stars']?.toString() ?? '8';

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
// شاشة التفاصيل (المواسم، الحلقات، القصة والتصنيفات)
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
  bool _isTv = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
    final k = widget.media['kind']?.toString() ?? '1';
    _isTv = k != '1' || (widget.media['season'] != null && widget.media['season'] != '0');
    if (_isTv) _fetchSeriesEpisodes();
  }

  void _checkFav() async {
    final nb = widget.media['nb']?.toString() ?? '';
    final isFav = await FavoritesService.isFavorited(nb);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFav() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, _isTv ? 'tv' : 'movie');
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

  Future<void> _fetchSeriesEpisodes() async {
    setState(() => _isLoadingEpisodes = true);
    final nb = widget.media['nb'].toString();

    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideo/page/1/level/2/sub_id/$nb'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      );
      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        if (mounted && list.isNotEmpty) setState(() => _episodes = list);
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  void _playStream({String? targetNb, String? subTitle}) async {
    setState(() => _isLaunching = true);

    final nb = targetNb ?? widget.media['nb'].toString();
    final title = subTitle ?? widget.media['ar_title'] ?? widget.media['en_title'] ?? 'بث مباشر';
    final subFile = widget.media['arTranslationFile']?.toString() ?? '';

    final data = await StreamService.getVideoSource(nb);

    setState(() => _isLaunching = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: title,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
            subtitleFileName: subFile,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح السيرفر، جاري المعالجة عبر الريلاي...'), backgroundColor: Color(0xFFE50914)),
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

    // استخراج التصنيفات
    String genresText = '';
    if (widget.media['categories'] is List) {
      genresText = (widget.media['categories'] as List)
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
                        if (genresText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(genresText, style: const TextStyle(fontSize: 11.5, color: Color(0xFF00F0FF), fontWeight: FontWeight.w600)),
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
                        onPressed: _isLaunching ? null : () => _playStream(),
                        icon: _isLaunching
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                        label: Text(_isTv ? 'مشاهدة الحلقة الأولى' : 'مشاهدة العمل الآن',
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

              // شبكة الحلقات للمسلسلات
              if (_isTv) ...[
                const SizedBox(height: 24),
                const Text('حلقات المسلسل المتوفرة:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : _episodes.isEmpty
                        ? const Text('المسلسل متوفر بحلقة مجمعة أو يتم تجهيز الحلقات...', style: TextStyle(color: Colors.white54, fontSize: 12))
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
                                onTap: () => _playStream(targetNb: epNb, subTitle: '$title - $epTitle'),
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
// المشغل مع تخطي شارة البداية وإعدادات الترجمة المخصصة
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final String subtitleFileName;

  const PlayerScreen({
    super.key,
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

  // إعدادات الترجمة
  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 16.0;
  List<Subtitle> _parsedSubtitles = [];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _loadSubtitlesAndInitPlayer();
  }

  void _loadSubtitlesAndInitPlayer() async {
    if (widget.subtitleFileName.isNotEmpty) {
      try {
        final subUrl = 'https://cnth2.cee.buzz/vascin-subtitles-files/${widget.subtitleFileName}';
        final res = await http.get(Uri.parse(subUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          _parsedSubtitles = _parseSrt(utf8.decode(res.bodyBytes));
        }
      } catch (_) {}
    }

    _initFastPlayer(_currentUrl!);
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

  void _initFastPlayer(String streamUrl) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_checkIntro);
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
    _videoPlayerController!.addListener(_checkIntro);

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

  void _checkIntro() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    final seconds = _videoPlayerController!.value.position.inSeconds;
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
                  _initFastPlayer(_currentUrl!);
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
                  _initFastPlayer(_currentUrl!);
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
                  setState(() {
                    _currentUrl = url;
                    _selectedQualityName = res;
                  });
                  _initFastPlayer(url);
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
    _videoPlayerController?.removeListener(_checkIntro);
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
// قائمة المفضلة
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
