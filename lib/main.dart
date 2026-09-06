import 'dart:async';
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

class SecurityEngine {
  static const String _encTmdb = 'YjdjZDMzNDBhNzk0ZTVhMmYzNWUzYWJiODIwYjQ5N2Y=';
  static String get tmdbKey {
    try {
      return utf8.decode(base64.decode(_encTmdb));
    } catch (_) {
      return 'b7cd3340a794e5a2f35e3abb820b497f';
    }
  }
}

// -------------------------------------------------------------
// الصفحة الرئيسية مع شريط "متابعة المشاهدة" وسجل البحث
// -------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _trending = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _popularSeries = [];
  List<dynamic> _activeGrid = [];
  List<Map<String, dynamic>> _continueWatchingList = [];
  List<String> _recentSearches = [];

  int _page = 1;
  int _genrePage = 1;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;
  String _activeTitle = '🔥 الأكثر تداولاً وشهرة';
  Map<String, dynamic>? _selectedGenre;

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'name': 'الكل'},
    {'id': 'anime', 'name': 'أنمي ياباني ورسوم'},
    {'id': '28', 'name': 'أكشن'},
    {'id': '12', 'name': 'مغامرة'},
    {'id': '35', 'name': 'كوميديا'},
    {'id': '80', 'name': 'جريمة'},
    {'id': '18', 'name': 'دراما'},
    {'id': '27', 'name': 'رعب'},
    {'id': '878', 'name': 'خيال علمي'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchTmdbData(reset: true);
    _loadContinueWatching();
    _loadSearchHistory();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore && !_hasError) {
          if (_selectedGenre != null && _selectedGenre!['id'] != 'all') {
            _fetchMoreGenreData();
          } else {
            _fetchTmdbData(reset: false);
          }
        }
      }
    });
  }

  void _loadContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('continue_watching_list');
    if (raw != null) {
      try {
        final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
        if (mounted) setState(() => _continueWatchingList = list);
      } catch (_) {}
    }
  }

  void _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('search_history') ?? [];
    if (mounted) setState(() => _recentSearches = raw);
  }

  void _saveSearchWord(String word) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = List.from(_recentSearches);
    list.remove(word);
    list.insert(0, word);
    if (list.length > 8) list = list.sublist(0, 8);
    prefs.setStringList('search_history', list);
    if (mounted) setState(() => _recentSearches = list);
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
      setState(() {
        _isLoadingInitial = true;
        _hasError = false;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final key = SecurityEngine.tmdbKey;

    try {
      if (reset) {
        final responses = await Future.wait([
          http.get(Uri.parse('https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=ar')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/movie/popular?api_key=$key&language=ar&page=1')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/tv/popular?api_key=$key&language=ar&page=1')).timeout(const Duration(seconds: 8)),
        ]);

        if (responses[0].statusCode == 200 && mounted) {
          final tList = jsonDecode(responses[0].body)['results'] ?? [];
          final mList = jsonDecode(responses[1].body)['results'] ?? [];
          final sList = jsonDecode(responses[2].body)['results'] ?? [];

          setState(() {
            _trending = tList;
            _popularMovies = mList;
            _popularSeries = sList;
            _activeGrid = List.from(tList);
            _isLoadingInitial = false;
            _hasError = false;
          });
        } else {
          if (mounted) setState(() { _isLoadingInitial = false; _hasError = true; });
        }
      } else {
        _page++;
        final moreRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=ar&page=$_page')).timeout(const Duration(seconds: 8));
        if (moreRes.statusCode == 200 && mounted) {
          final mList = jsonDecode(moreRes.body)['results'] ?? [];
          setState(() {
            _activeGrid.addAll(mList);
            if (mList.isEmpty) _hasMore = false;
            _isLoadingMore = false;
          });
        } else {
          if (mounted) setState(() => _isLoadingMore = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
          if (reset && _activeGrid.isEmpty) _hasError = true;
        });
      }
    }
  }

  void _filterGenre(Map<String, dynamic> genre) async {
    _selectedGenre = genre;
    _genrePage = 1;
    final gId = genre['id'];
    final key = SecurityEngine.tmdbKey;

    if (gId == 'all') {
      _selectedGenre = null;
      setState(() => _activeTitle = '🔥 الأكثر تداولاً وشهرة');
      _fetchTmdbData(reset: true);
      return;
    }

    setState(() {
      _activeTitle = 'تصنيف: ${genre['name']}';
      _isLoadingInitial = true;
      _hasMore = true;
      _hasError = false;
    });

    try {
      String urlStr = (gId == 'anime')
          ? 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=ar&with_genres=16&with_original_language=ja&sort_by=popularity.desc&page=1'
          : 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=ar&with_genres=$gId&sort_by=popularity.desc&page=1';

      final res = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          _activeGrid = list;
          _isLoadingInitial = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _fetchMoreGenreData() async {
    if (_selectedGenre == null) return;
    setState(() => _isLoadingMore = true);
    _genrePage++;

    final gId = _selectedGenre!['id'];
    final key = SecurityEngine.tmdbKey;

    String urlStr = (gId == 'anime')
        ? 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=ar&with_genres=16&with_original_language=ja&sort_by=popularity.desc&page=$_genrePage'
        : 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=ar&with_genres=$gId&sort_by=popularity.desc&page=$_genrePage';

    try {
      final res = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          if (list.isEmpty) {
            _hasMore = false;
          } else {
            _activeGrid.addAll(list);
          }
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    _saveSearchWord(clean);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    final key = SecurityEngine.tmdbKey;

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$key&language=ar&query=${Uri.encodeComponent(clean)}')).timeout(const Duration(seconds: 8));
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)))
        .then((_) => _loadContinueWatching());
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
                    Text('المنصة الاحترافية للسينما والأنمي', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
                title: const Text('الرئيسية (الكل)'),
                onTap: () {
                  Navigator.pop(context);
                  _selectedGenre = null;
                  setState(() => _activeTitle = '🔥 الأكثر تداولاً وشهرة');
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
                    leading: Icon(
                      g['id'] == 'anime' ? Icons.animation_rounded : Icons.movie_creation_outlined,
                      size: 20,
                      color: g['id'] == 'anime' ? const Color(0xFF00F0FF) : Colors.white70,
                    ),
                    title: Text(g['name'], style: TextStyle(color: g['id'] == 'anime' ? const Color(0xFF00F0FF) : Colors.white)),
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
              icon: const Icon(Icons.cast_rounded, color: Colors.white70),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري البحث عن شاشات البث والتلفاز المتاحة...')));
              },
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
          ],
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : _hasError && _activeGrid.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 55, color: Colors.white38),
                        const SizedBox(height: 12),
                        const Text('وضع عدم الاتصال: تعذر جلب البيانات', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                          onPressed: () => _fetchTmdbData(reset: true),
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          label: const Text('إعادة الاتصال', style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFFE50914),
                    onRefresh: () async => _fetchTmdbData(reset: true),
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
                                    _selectedGenre = null;
                                    setState(() => _activeTitle = '🔥 الأكثر تداولاً وشهرة');
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
                          if (_recentSearches.isNotEmpty && _selectedGenre == null) ...[
                            SizedBox(
                              height: 32,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                itemCount: _recentSearches.length,
                                itemBuilder: (ctx, i) => InkWell(
                                  onTap: () {
                                    _searchController.text = _recentSearches[i];
                                    _search(_recentSearches[i]);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFF172033), borderRadius: BorderRadius.circular(16)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.history_rounded, size: 13, color: Colors.white54),
                                        const SizedBox(width: 4),
                                        Text(_recentSearches[i], style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (_continueWatchingList.isNotEmpty) ...[
                            _buildContinueWatchingShelf(),
                          ],
                          if (_trending.isNotEmpty && _selectedGenre == null && (_activeTitle.contains('الرئيسية') || _activeTitle.contains('تداولاً'))) ...[
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

  Widget _buildContinueWatchingShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Text('▶ متابعة المشاهدة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF00F0FF))),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _continueWatchingList.length,
            itemBuilder: (ctx, i) {
              final item = _continueWatchingList[i];
              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: 170,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item['backdrop_path'] != null
                              ? Image.network('https://image.tmdb.org/t/p/w300${item['backdrop_path']}', fit: BoxFit.cover)
                              : Container(color: const Color(0xFF172033)),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                        ),
                      ),
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 36)),
                      Positioned(
                        bottom: 6,
                        left: 8,
                        right: 8,
                        child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      )
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
// شاشة التفاصيل (الحل النهائي للمواسم والحلقات والأعمال المشابهة)
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
  bool _isLoadingEpisodes = true;

  Map<String, dynamic>? _ceeData;
  List<dynamic> _seasons = [];
  List<dynamic> _episodes = [];
  List<dynamic> _similarMedia = [];
  int _selectedSeasonNumber = 1;
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
    _isSeries = widget.media['first_air_date'] != null || widget.media['name'] != null;
    _saveToContinueWatching();
    _initializeContent();
  }

  void _saveToContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('continue_watching_list');
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.removeWhere((item) => item['id'].toString() == widget.media['id'].toString());
    list.insert(0, widget.media);
    if (list.length > 10) list = list.sublist(0, 10);
    prefs.setString('continue_watching_list', jsonEncode(list));
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

  Future<void> _initializeContent() async {
    final key = SecurityEngine.tmdbKey;
    final tmdbId = widget.media['id'];
    final type = _isSeries ? 'tv' : 'movie';

    // 1. جلب الأعمال المشابهة
    try {
      http.get(Uri.parse('https://api.themoviedb.org/3/$type/$tmdbId/recommendations?api_key=$key&language=ar')).then((res) {
        if (res.statusCode == 200 && mounted) {
          setState(() {
            _similarMedia = jsonDecode(res.body)['results'] ?? [];
          });
        }
      });
    } catch (_) {}

    // 2. مطابقة العمل بسيرفر وسائط سينمانا
    await _matchWithCee();

    // 3. بناء المواسم والحلقات
    if (_isSeries) {
      await _loadSeriesStructure();
    } else {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  Future<void> _matchWithCee() async {
    final queryEn = widget.media['original_title'] ??
        widget.media['original_name'] ??
        widget.media['title'] ??
        widget.media['name'] ??
        '';

    try {
      final b64 = base64.encode(utf8.encode(queryEn)).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/10/video_title_search/$b64/itemsPerPage/10/pageNumber/0/level/0'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        if (results.isNotEmpty) {
          _ceeData = results.first;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSeriesStructure() async {
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;

    try {
      final tvRes = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId?api_key=$key&language=ar')).timeout(const Duration(seconds: 5));
      if (tvRes.statusCode == 200) {
        final data = jsonDecode(tvRes.body);
        final rawSeasons = data['seasons'] as List? ?? [];
        _seasons = rawSeasons.where((s) => (s['season_number'] ?? 0) > 0).toList();

        if (_seasons.isNotEmpty) {
          _selectedSeasonNumber = _seasons.first['season_number'] ?? 1;
          await _loadEpisodesForTmdbSeason(_selectedSeasonNumber);
          return;
        }
      }
    } catch (_) {}

    // في حال عدم توفر تفاصيل المسلسل من TMDB نضع افتراضياً موسم 1 و 24 حلقة
    _seasons = [
      {'season_number': 1, 'name': 'الموسم 1'}
    ];
    _episodes = List.generate(24, (index) => {'episode_number': index + 1, 'name': 'الحلقة ${index + 1}'});
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  Future<void> _loadEpisodesForTmdbSeason(int sNumber) async {
    if (mounted) setState(() => _isLoadingEpisodes = true);
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;

    try {
      final epRes = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/season/$sNumber?api_key=$key&language=ar')).timeout(const Duration(seconds: 5));
      if (epRes.statusCode == 200) {
        final epData = jsonDecode(epRes.body);
        final list = epData['episodes'] as List? ?? [];
        if (mounted) {
          setState(() {
            _episodes = list;
            _isLoadingEpisodes = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _episodes = List.generate(24, (index) => {'episode_number': index + 1, 'name': 'الحلقة ${index + 1}'});
        _isLoadingEpisodes = false;
      });
    }
  }

  void _playStream({int? episodeNum, String? epTitle}) async {
    setState(() => _isLaunching = true);

    String targetId = _ceeData != null ? _ceeData!['nb'].toString() : widget.media['id'].toString();
    final title = epTitle ?? widget.media['title'] ?? widget.media['name'] ?? 'بث مباشر';

    final data = await StreamService.getVideoSource(targetId);
    setState(() => _isLaunching = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: title,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
            onNextEpisode: episodeNum != null && episodeNum < _episodes.length
                ? () => _playStream(episodeNum: episodeNum + 1, epTitle: '${widget.media['title'] ?? widget.media['name']} - حلقة ${episodeNum + 1}')
                : null,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري تجهيز سيرفر المشاهدة لهذا العمل، يرجى المحاولة بعد قليل'), backgroundColor: Color(0xFFE50914)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final poster = widget.media['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}' : '';
    final score = (widget.media['vote_average'] ?? 8.0).toStringAsFixed(1);
    final story = widget.media['overview'] ?? 'لا يوجد وصف متاح.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
              onPressed: _toggleFav,
            ),
          ],
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
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('سيرفر البث جاهز فائق السرعة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
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
                  onPressed: _isLaunching ? null : () => _playStream(episodeNum: 1, epTitle: '$title - حلقة 1'),
                  icon: _isLaunching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                  label: Text(_isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة العمل الآن', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4)),

              // عرض المواسم والحلقات المضمون
              if (_isSeries) ...[
                const SizedBox(height: 24),
                if (_seasons.isNotEmpty) ...[
                  const Text('المواسم:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _seasons.length,
                      itemBuilder: (ctx, i) {
                        final sNum = _seasons[i]['season_number'] ?? (i + 1);
                        final isSelected = _selectedSeasonNumber == sNum;
                        return InkWell(
                          onTap: () {
                            setState(() => _selectedSeasonNumber = sNum);
                            _loadEpisodesForTmdbSeason(sNum);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE50914) : const Color(0xFF172033),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('الموسم $sNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('الحلقات (${_episodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.3),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final ep = _episodes[i];
                          final epNum = ep['episode_number'] ?? (i + 1);

                          return InkWell(
                            onTap: () => _playStream(episodeNum: epNum, epTitle: '$title - حلقة $epNum'),
                            child: Container(
                              decoration: BoxDecoration(color: const Color(0xFF172033), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white12)),
                              child: Center(child: Text('حلقة $epNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            ),
                          );
                        },
                      ),
              ],

              if (_similarMedia.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Text('أعمال قد تعجبك (مشابهة):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 160,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _similarMedia.length,
                    itemBuilder: (ctx, i) {
                      final item = _similarMedia[i];
                      final pPath = item['poster_path'];
                      return InkWell(
                        onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                        child: Container(
                          width: 100,
                          margin: const EdgeInsets.only(left: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: pPath != null ? Image.network('https://image.tmdb.org/t/p/w200$pPath', fit: BoxFit.cover) : Container(color: const Color(0xFF172033)),
                          ),
                        ),
                      );
                    },
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// المشغل الاحترافي: تخطي المقدمة، النقر المزدوج، قفل الشاشة، والترجمة
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final VoidCallback? onNextEpisode;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.onNextEpisode,
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
  bool _isLocked = false;
  String _gestureFeedback = '';
  Timer? _feedbackTimer;

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
    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt('playback_pos_${widget.mediaId}') ?? 0;
    _initPlayer(_currentUrl!, startAtSecond: savedSeconds);
    _fetchSubtitlesInBackground();
  }

  void _fetchSubtitlesInBackground() async {
    try {
      final infoRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (infoRes.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
        final subUrl = info['arTranslationFilePath']?.toString() ?? info['arTranslationFile']?.toString() ?? '';

        if (subUrl.isNotEmpty) {
          final subRes = await http.get(Uri.parse(subUrl), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 4));
          if (subRes.statusCode == 200 && subRes.body.isNotEmpty && mounted) {
            setState(() {
              _parsedSubtitles = _parseSubtitles(utf8.decode(subRes.bodyBytes, allowMalformed: true));
            });
            _buildChewie();
          }
        }
      }
    } catch (_) {}
  }

  List<Subtitle> _parseSubtitles(String text) {
    final List<Subtitle> list = [];
    final pattern = RegExp(r'(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\r?\n([\s\S]*?)(?=\n\n|\r\n\r\n|$)');
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

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      httpHeaders: StreamService.stealthHeaders,
    );

    try {
      await _videoPlayerController!.initialize();
      if (startAtSecond > 0 && startAtSecond < _videoPlayerController!.value.duration.inSeconds - 5) {
        await _videoPlayerController!.seekTo(Duration(seconds: startAtSecond));
      }
      _videoPlayerController!.addListener(_trackPosition);
      _buildChewie();
      if (mounted) setState(() => _isReady = true);
    } catch (_) {
      // آلية التبديل التلقائي (Failover) إلى جودة بديلة في حال تعثر الجودة المختارة
      if (widget.qualities.isNotEmpty && _selectedQualityName != '480p') {
        final fallback = widget.qualities.firstWhere((q) => q['resolution'] != _selectedQualityName, orElse: () => widget.qualities.first);
        _initPlayer(fallback['url'], startAtSecond: startAtSecond);
      }
    }
  }

  void _buildChewie() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

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
      additionalOptions: (context) => [
        OptionItem(onTap: (ctx) => _showQualitySheet(), iconData: Icons.hd_outlined, title: 'الجودة: $_selectedQualityName'),
        OptionItem(onTap: (ctx) => _showSubtitlesSheet(), iconData: Icons.subtitles_rounded, title: 'إعدادات الترجمة'),
      ],
    );
  }

  void _trackPosition() async {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    final seconds = _videoPlayerController!.value.position.inSeconds;
    if (seconds > 0 && seconds % 5 == 0) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('playback_pos_${widget.mediaId}', seconds);
    }
  }

  void _seekForward() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur + const Duration(seconds: 10));
    _showFeedback('+10 ثوانٍ ⏩');
  }

  void _seekBackward() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur - const Duration(seconds: 10));
    _showFeedback('⏪ -10 ثوانٍ');
  }

  void _skipIntro() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur + const Duration(seconds: 85));
    _showFeedback('تم تخطي المقدمة ⏭️');
  }

  void _showFeedback(String msg) {
    _feedbackTimer?.cancel();
    setState(() => _gestureFeedback = msg);
    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gestureFeedback = '');
    });
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
    _feedbackTimer?.cancel();
    _videoPlayerController?.removeListener(_trackPosition);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // المشغل الأساسي
            Center(
              child: (_isReady && _chewieController != null)
                  ? Chewie(controller: _chewieController!)
                  : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
            ),

            // طبقة الإيماءات اللمسية (النقر المزدوج على اليمين واليسار) عند إلغاء القفل
            if (!_isLocked) ...[
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: _seekBackward,
                      ),
                    ),
                    const SizedBox(width: 80),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: _seekForward,
                      ),
                    ),
                  ],
                ),
              ),

              // زر تخطي المقدمة (Skip Intro) يظهر في البداية
              Positioned(
                bottom: 80,
                left: 20,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.75),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: _skipIntro,
                  icon: const Icon(Icons.fast_forward_rounded, color: Color(0xFF00F0FF), size: 18),
                  label: const Text('تخطي المقدمة', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),

              // زر الحلقة التالية التلقائي
              if (widget.onNextEpisode != null)
                Positioned(
                  bottom: 80,
                  right: 20,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914).withOpacity(0.85),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onNextEpisode!();
                    },
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                    label: const Text('الحلقة التالية', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],

            // مؤشر النقر المزدوج المرئي
            if (_gestureFeedback.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(25)),
                  child: Text(_gestureFeedback, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),

            // زر قفل الشاشة (Screen Lock)
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: _isLocked ? const Color(0xFFE50914) : Colors.white70),
                onPressed: () => setState(() => _isLocked = !_isLocked),
              ),
            ),

            // زر العودة
            if (!_isLocked)
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
          ],
        ),
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
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : _favorites.isEmpty ? const Center(child: Text('لا توجد عناصر في المفضلة')) : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.58),
          itemCount: _favorites.length,
          itemBuilder: (ctx, i) {
            final item = _favorites[i];
            final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _load()),
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container())),
                    Padding(padding: const EdgeInsets.all(5), child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
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
