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

// -------------------------------------------------------------
// الصفحة الرئيسية (تعتمد على TMDB للعرض فائق السرعة)
// -------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  // مفتاح TMDB الرسمي العام
  final String _tmdbApiKey = 'b7cd3340a794e5a2f35e3abb820b497f';
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _trending = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _popularSeries = [];
  List<dynamic> _activeGrid = [];

  int _page = 1;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _activeTitle = '🔥 الأكثر تداولاً وشهرة';

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'name': 'الكل', 'type': 'all'},
    {'id': '28', 'name': 'أكشن', 'type': 'movie'},
    {'id': '12', 'name': 'مغامرة', 'type': 'movie'},
    {'id': '16', 'name': 'أنمي ورسوم متحركة', 'type': 'both'},
    {'id': '35', 'name': 'كوميديا', 'type': 'both'},
    {'id': '80', 'name': 'جريمة', 'type': 'both'},
    {'id': '18', 'name': 'دراما', 'type': 'both'},
    {'id': '27', 'name': 'رعب', 'type': 'movie'},
    {'id': '878', 'name': 'خيال علمي', 'type': 'both'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchTmdbData(reset: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _fetchTmdbData(reset: false);
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

  Future<void> _fetchTmdbData({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      if (reset) {
        // جلب التريند، الأفلام الشائعة، والمسلسلات
        final trendingRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/trending/all/week?api_key=$_tmdbApiKey&language=ar'));
        final moviesRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/movie/popular?api_key=$_tmdbApiKey&language=ar&page=1'));
        final seriesRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/tv/popular?api_key=$_tmdbApiKey&language=ar&page=1'));

        if (trendingRes.statusCode == 200 && mounted) {
          final tList = jsonDecode(trendingRes.body)['results'] ?? [];
          final mList = jsonDecode(moviesRes.body)['results'] ?? [];
          final sList = jsonDecode(seriesRes.body)['results'] ?? [];

          setState(() {
            _trending = tList;
            _popularMovies = mList;
            _popularSeries = sList;
            _activeGrid = List.from(tList);
            _isLoadingInitial = false;
          });
        }
      } else {
        // تحميل المزيد من الصفحات
        _page++;
        final moreRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/trending/all/week?api_key=$_tmdbApiKey&language=ar&page=$_page'));
        if (moreRes.statusCode == 200 && mounted) {
          final mList = jsonDecode(moreRes.body)['results'] ?? [];
          setState(() {
            _activeGrid.addAll(mList);
            if (mList.isEmpty) _hasMore = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  // فلترة التصنيفات عبر TMDB
  void _filterGenre(Map<String, dynamic> genre) async {
    final gId = genre['id'];
    setState(() {
      _activeTitle = 'تصنيف: ${genre['name']}';
      _isLoadingInitial = true;
    });

    if (gId == 'all') {
      _fetchTmdbData(reset: true);
      return;
    }

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/discover/movie?api_key=$_tmdbApiKey&language=ar&with_genres=$gId&sort_by=popularity.desc'));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          _activeGrid = list;
          _hasMore = false;
          _isLoadingInitial = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  // البحث الشامل في TMDB
  void _search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$_tmdbApiKey&language=ar&query=${Uri.encodeComponent(clean)}'));
      Navigator.pop(context);

      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          _activeGrid = list;
          _hasMore = false;
          _activeTitle = 'نتائج البحث عن: $clean';
        });
      }
    } catch (_) {
      Navigator.pop(context);
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)));
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
                    Text('المكتبة السينمائية الشاملة', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
                title: const Text('الرئيسية (الكل)'),
                onTap: () {
                  Navigator.pop(context);
                  _fetchTmdbData(reset: true);
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
                child: Text('التصنيفات والأنواع:', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              ..._genres.map((g) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.movie_creation_outlined, size: 20, color: Colors.white70),
                    title: Text(g['name']),
                    onTap: () {
                      Navigator.pop(context);
                      _filterGenre(g);
                    },
                  )),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          elevation: 0,
          title: const Text('ONEBR TV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
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
                onRefresh: () => _fetchTmdbData(reset: true),
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
                          onSubmitted: _search,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم (عربي أو إنجليزي)...',
                            hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF00F0FF)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _fetchTmdbData(reset: true);
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F1422),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      if (_trending.isNotEmpty && _activeTitle.contains('الرئيسية') || _activeTitle.contains('تداولاً')) ...[
                        _buildHeroBanner(_trending.first, screenWidth),
                        if (_popularMovies.isNotEmpty) _buildSectionShelf('🎬 أفلام مميزة وجديدة', _popularMovies),
                        if (_popularSeries.isNotEmpty) _buildSectionShelf('📺 مسلسلات وأنمي رائجة', _popularSeries),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                        child: Text(
                          _activeTitle,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      _buildGrid(_activeGrid),
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
    final title = item['title'] ?? item['name'] ?? '';
    final backdrop = item['backdrop_path'] != null
        ? 'https://image.tmdb.org/t/p/w780${item['backdrop_path']}'
        : '';

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: width * 0.52,
          width: double.infinity,
          decoration: BoxDecoration(
            image: backdrop.isNotEmpty
                ? DecorationImage(image: NetworkImage(backdrop), fit: BoxFit.cover)
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
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

  Widget _buildSectionShelf(String title, List<dynamic> list) {
    final cardWidth = (MediaQuery.of(context).size.width * 0.31).clamp(105.0, 140.0);
    final cardHeight = cardWidth * 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0), child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
        SizedBox(
          height: cardHeight + 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final item = list[i];
              final mTitle = item['title'] ?? item['name'] ?? '';
              final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
              final score = (item['vote_average'] ?? 8.0).toStringAsFixed(1);

              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: cardWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: poster.isNotEmpty
                            ? Image.network(poster, height: cardHeight, width: double.infinity, fit: BoxFit.cover)
                            : Container(height: cardHeight, color: const Color(0xFF172033)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.58),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          final title = item['title'] ?? item['name'] ?? '';
          final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
          final score = (item['vote_average'] ?? 8.0).toStringAsFixed(1);

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: poster.isNotEmpty
                          ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                          : Container(color: const Color(0xFF172033)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('⭐ $score', style: const TextStyle(fontSize: 9.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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
// شاشة التفاصيل: تبحث في سينمانا خلف الكواليس وتستخرج البث
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
  bool _isLoadingCee = true;

  // البيانات المستخرجة من سينمانا في الكواليس
  Map<String, dynamic>? _ceeData;
  List<dynamic> _ceeEpisodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
    _isSeries = widget.media['first_air_date'] != null || widget.media['name'] != null;
    _matchWithCeeBackend();
  }

  void _checkFav() async {
    final id = widget.media['id'].toString();
    final isFav = await FavoritesService.isFavorited(id);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFav() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
    if (mounted) setState(() => _isFav = newState);
  }

  // المطابقة الصامتة في الكواليس مع خادم سينمانا
  Future<void> _matchWithCeeBackend() async {
    final String queryEn = widget.media['original_title'] ??
        widget.media['original_name'] ??
        widget.media['title'] ??
        widget.media['name'] ??
        '';

    try {
      final b64 = base64.encode(utf8.encode(queryEn)).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/10/video_title_search/$b64/itemsPerPage/10/pageNumber/0/level/0'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);

        if (results.isNotEmpty) {
          _ceeData = results.first;
          final ceeNb = _ceeData!['nb'].toString();

          // إذا كان مسلسلاً، نسحب حلقاته من سينمانا في الخلفية
          if (_isSeries) {
            _loadCeeEpisodes(ceeNb, 0);
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingCee = false);
  }

  Future<void> _loadCeeEpisodes(String ceeNb, int page) async {
    try {
      final epRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/50/series_episodes_list/$ceeNb/itemsPerPage/50/pageNumber/$page/level/0'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      );

      if (epRes.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(epRes.bodyBytes, allowMalformed: true));
        List eList = (decoded is List) ? decoded : (decoded['articles'] ?? []);

        if (mounted) {
          setState(() {
            if (page == 0) {
              _ceeEpisodes = eList;
            } else {
              _ceeEpisodes.addAll(eList);
            }
          });

          if (eList.length >= 45) {
            _loadCeeEpisodes(ceeNb, page + 1);
          }
        }
      }
    } catch (_) {}
  }

  void _playStream({String? targetNb, String? epTitle}) async {
    if (_ceeData == null && targetNb == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري معالجة السيرفر البديل، يرجى المحاولة بعد ثوانٍ...')),
      );
      return;
    }

    setState(() => _isLaunching = true);

    final nb = targetNb ?? _ceeData!['nb'].toString();
    final title = epTitle ?? widget.media['title'] ?? widget.media['name'] ?? 'بث مباشر';

    // سحب الترجمة الموقعة من سينمانا
    String exactSubUrl = '';
    try {
      final infoRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$nb'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      ).timeout(const Duration(seconds: 4));

      if (infoRes.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
        exactSubUrl = info['arTranslationFilePath']?.toString() ??
            info['arTranslationFile']?.toString() ??
            '';
      }
    } catch (_) {}

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
            signedSubtitleUrl: exactSubUrl,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر العثور على رابط المشاهدة المباشر لهذا العمل في سينمانا'), backgroundColor: Color(0xFFE50914)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final poster = widget.media['poster_path'] != null
        ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}'
        : '';
    final score = (widget.media['vote_average'] ?? 8.0).toStringAsFixed(1);
    final story = widget.media['overview'] ?? 'لا يوجد وصف متاح.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFF0F1422), title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
                    child: poster.isNotEmpty
                        ? Image.network(poster, width: 110, height: 160, fit: BoxFit.cover)
                        : Container(width: 110, height: 160, color: const Color(0xFF172033)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 8),
                        Text('⭐ $score (TMDB)', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _ceeData != null ? const Color(0xFF10B981) : Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _isLoadingCee ? 'جاري الفحص...' : (_ceeData != null ? 'متوفر بسيرفر سينمانا' : 'قيد المعالجة'),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _isLaunching ? null : () => _playStream(),
                  icon: _isLaunching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                  label: Text(_isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة العمل الآن', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4)),

              if (_isSeries) ...[
                const SizedBox(height: 20),
                Text('الحلقات المتوفرة في سينمانا (${_ceeEpisodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _isLoadingCee
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : _ceeEpisodes.isEmpty
                        ? const Text('المسلسل متوفر برابط تشغيل مباشر.', style: TextStyle(color: Colors.white54, fontSize: 12))
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.3),
                            itemCount: _ceeEpisodes.length,
                            itemBuilder: (ctx, i) {
                              final ep = _ceeEpisodes[i];
                              final epNum = ep['episode']?.toString() ?? '${i + 1}';
                              final epNb = ep['nb']?.toString() ?? '';

                              return InkWell(
                                onTap: () => _playStream(targetNb: epNb, epTitle: '$title - حلقة $epNum'),
                                child: Container(
                                  decoration: BoxDecoration(color: const Color(0xFF172033), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white12)),
                                  child: Center(child: Text('حلقة $epNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
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
// المشغل مع دعم الترجمة واستئناف الدقيقة
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final String signedSubtitleUrl;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.signedSubtitleUrl = '',
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

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 16.0;
  List<Subtitle> _parsedSubtitles = [];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _prepareAndPlay();
  }

  void _prepareAndPlay() async {
    if (widget.signedSubtitleUrl.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(widget.signedSubtitleUrl), headers: {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://cee.buzz/home'
        }).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200 && res.body.isNotEmpty) {
          _parsedSubtitles = _parseSubtitles(utf8.decode(res.bodyBytes, allowMalformed: true));
        }
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt('playback_pos_${widget.mediaId}') ?? 0;
    _initPlayer(_currentUrl!, startAtSecond: savedSeconds);
  }

  List<Subtitle> _parseSubtitles(String text) {
    final List<Subtitle> list = [];
    final pattern = RegExp(
        r'(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\r?\n([\s\S]*?)(?=\n\n|\r\n\r\n|$)');
    final matches = pattern.allMatches(text);

    int idx = 0;
    for (var m in matches) {
      final start = _parseDuration(m.group(1)!);
      final end = _parseDuration(m.group(2)!);
      final subText = m.group(3)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (subText.isNotEmpty) {
        list.add(Subtitle(index: idx++, start: start, end: end, text: subText));
      }
    }
    return list;
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.replaceAll(',', '.').split(':');
    final secondsParts = parts[2].split('.');
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      seconds: int.parse(secondsParts[0]),
      milliseconds: int.parse(secondsParts[1].padRight(3, '0').substring(0, 3)),
    );
  }

  void _initPlayer(String streamUrl, {int startAtSecond = 0}) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_trackPosition);
    await _videoPlayerController?.dispose();

    setState(() => _isReady = false);

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
    await _videoPlayerController!.initialize();

    if (startAtSecond > 0 && startAtSecond < _videoPlayerController!.value.duration.inSeconds - 5) {
      await _videoPlayerController!.seekTo(Duration(seconds: startAtSecond));
    }

    _videoPlayerController!.addListener(_trackPosition);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      subtitle: (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) ? Subtitles(_parsedSubtitles) : null,
      subtitleBuilder: (context, subtitle) => Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
        child: Text(subtitle, style: TextStyle(color: Colors.white, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      ),
      materialProgressColors: ChewieProgressColors(playedColor: const Color(0xFFE50914), handleColor: const Color(0xFF00F0FF)),
      additionalOptions: (context) {
        return [
          OptionItem(onTap: (ctx) => _showQualitySheet(), iconData: Icons.hd_outlined, title: 'الجودة: $_selectedQualityName'),
          OptionItem(onTap: (ctx) => _showSubtitlesSheet(), iconData: Icons.subtitles_rounded, title: 'إعدادات الترجمة'),
        ];
      },
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _trackPosition() async {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    final seconds = _videoPlayerController!.value.position.inSeconds;
    if (seconds > 0 && seconds % 5 == 0) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('playback_pos_${widget.mediaId}', seconds);
    }
  }

  void _showSubtitlesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
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
                onChanged: (val) {
                  setSheetState(() => _subtitlesEnabled = val);
                  setState(() => _subtitlesEnabled = val);
                  _initPlayer(_currentUrl!, startAtSecond: _videoPlayerController?.value.position.inSeconds ?? 0);
                },
              ),
              const SizedBox(height: 8),
              const Text('حجم خط الترجمة:', style: TextStyle(fontSize: 13, color: Colors.white70)),
              Slider(
                value: _subtitleFontSize, min: 12.0, max: 26.0, divisions: 7,
                label: _subtitleFontSize.round().toString(),
                onChanged: (val) {
                  setSheetState(() => _subtitleFontSize = val);
                  setState(() => _subtitleFontSize = val);
                  _initPlayer(_currentUrl!, startAtSecond: _videoPlayerController?.value.position.inSeconds ?? 0);
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
            return ListTile(
              title: Text(res, style: TextStyle(color: url == _currentUrl ? const Color(0xFF00F0FF) : Colors.white)),
              onTap: () {
                Navigator.pop(context);
                if (url != _currentUrl && url != null) {
                  final pos = _videoPlayerController?.value.position.inSeconds ?? 0;
                  setState(() { _currentUrl = url; _selectedQualityName = res; });
                  _initPlayer(url, startAtSecond: pos);
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
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      SharedPreferences.getInstance().then((prefs) => prefs.setInt('playback_pos_${widget.mediaId}', _videoPlayerController!.value.position.inSeconds));
    }
    _videoPlayerController?.removeListener(_trackPosition);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 15)), backgroundColor: const Color(0xFF0F1422)),
      body: Center(child: _isReady && _chewieController != null ? Chewie(controller: _chewieController!) :
