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
  static const String _apiKey = '8265bd1679663a7ea12ac168da84d2e8';
  static const String _imgBase = 'https://image.tmdb.org/t/p/w500';

  final ScrollController _scrollController = ScrollController();

  List<dynamic> _trending = [];
  List<dynamic> _popularSeries = [];
  List<dynamic> _animeList = [];
  List<dynamic> _infiniteExploreList = [];

  int _explorePage = 1;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    StreamService.startRelayWorker();
    _loadInitialData();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _loadMoreExplore();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final resTrending = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/trending/movie/day?api_key=$_apiKey&language=ar-SA'));
      final resSeries = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/trending/tv/day?api_key=$_apiKey&language=ar-SA'));
      final resAnime = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/discover/tv?api_key=$_apiKey&with_genres=16&with_original_language=ja&sort_by=popularity.desc&language=ar-SA'));
      final resExplore = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/discover/movie?api_key=$_apiKey&sort_by=popularity.desc&page=$_explorePage&language=ar-SA'));

      if (mounted) {
        setState(() {
          _trending = jsonDecode(resTrending.body)['results'] ?? [];
          _popularSeries = jsonDecode(resSeries.body)['results'] ?? [];
          _animeList = jsonDecode(resAnime.body)['results'] ?? [];
          _infiniteExploreList = jsonDecode(resExplore.body)['results'] ?? [];
          _isLoadingInitial = false;
        });

        _triggerBatchPreCaching();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  void _triggerBatchPreCaching() {
    final List<Map<String, String>> targetItems = [];
    for (var item in _trending) {
      if (item['id'] != null) {
        targetItems.add({
          'id': item['id'].toString(),
          'title': item['original_title'] ?? item['title'] ?? '',
        });
      }
      if (targetItems.length >= 20) break;
    }
    if (targetItems.isNotEmpty) {
      StreamService.preCacheMovieTitles(targetItems);
    }
  }

  Future<void> _loadMoreExplore() async {
    setState(() => _isLoadingMore = true);
    _explorePage++;

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/discover/movie?api_key=$_apiKey&sort_by=popularity.desc&page=$_explorePage&language=ar-SA'));
      if (res.statusCode == 200) {
        final List newItems = jsonDecode(res.body)['results'] ?? [];
        if (newItems.isEmpty) {
          _hasMore = false;
        } else {
          setState(() {
            _infiniteExploreList.addAll(newItems);
          });
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingMore = false);
  }

  void _openDetails(Map<String, dynamic> item, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(media: item, type: type),
      ),
    );
  }

  void _openFavoritesPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                child: const Text(
                  'ONEBR TV',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
              tooltip: 'المفضلة',
              onPressed: _openFavoritesPage,
            ),
          ],
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: () async {
                  _explorePage = 1;
                  _hasMore = true;
                  await _loadInitialData();
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trending.isNotEmpty) _buildHeroBanner(_trending.first, screenWidth),
                      const SizedBox(height: 12),
                      _buildShelf('🔥 الأكثر رواجاً اليوم', _trending, 'movie'),
                      _buildShelf('📺 المسلسلات والدراما التلفزيونية', _popularSeries, 'tv'),
                      _buildShelf('⛩️ عالم الأنمي الياباني', _animeList, 'tv'),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                        child: Text(
                          '🌐 استكشاف عروض لا نهائية',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      _buildInfiniteGrid(),
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
    final backdrop = item['backdrop_path'] ?? item['poster_path'];
    final posterUrl = backdrop != null ? 'https://image.tmdb.org/t/p/original$backdrop' : '';

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: width * 0.52,
          width: double.infinity,
          decoration: BoxDecoration(
            image: posterUrl.isNotEmpty
                ? DecorationImage(image: NetworkImage(posterUrl), fit: BoxFit.cover)
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
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _openDetails(item, 'movie'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 6),
                    Text('عرض التفاصيل والمشاهدة',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShelf(String title, List<dynamic> list, String type) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.31).clamp(105.0, 140.0);
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
              final mTitle = item['title'] ?? item['name'] ?? '';
              final path = item['poster_path'];
              final score = (item['vote_average'] as num?)?.toStringAsFixed(1) ?? '7.5';

              return InkWell(
                onTap: () => _openDetails(item, type),
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
                        child: path != null
                            ? Image.network(
                                '$_imgBase$path',
                                height: cardHeight,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(height: cardHeight, color: const Color(0xFF172033)),
                              )
                            : Container(height: cardHeight, color: const Color(0xFF172033)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text('⭐ $score',
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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

  Widget _buildInfiniteGrid() {
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
        itemCount: _infiniteExploreList.length,
        itemBuilder: (ctx, i) {
          final item = _infiniteExploreList[i];
          final mTitle = item['title'] ?? item['name'] ?? '';
          final path = item['poster_path'];
          final score = (item['vote_average'] as num?)?.toStringAsFixed(1) ?? '7.5';

          return InkWell(
            onTap: () => _openDetails(item, 'movie'),
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
                      child: path != null
                          ? Image.network(
                              '$_imgBase$path',
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF172033)),
                            )
                          : Container(color: const Color(0xFF172033)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text('⭐ $score',
                            style: const TextStyle(
                                fontSize: 9.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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
// شاشة قائمة المفضلة
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
    _loadFavorites();
  }

  void _loadFavorites() async {
    final list = await FavoritesService.getFavorites();
    if (mounted) {
      setState(() {
        _favorites = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('⭐ قائمة المفضلة الخاصة بك',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0F1422),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : _favorites.isEmpty
                ? const Center(
                    child: Text(
                      'لم تقم بإضافة أي أعمال إلى المفضلة بعد.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  )
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
                      final poster = item['poster_path'];
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MediaDetailScreen(
                                media: item,
                                type: item['type'] ?? 'movie',
                              ),
                            ),
                          ).then((_) => _loadFavorites());
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                  child: poster != null
                                      ? Image.network(
                                          'https://image.tmdb.org/t/p/w500$poster',
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(color: const Color(0xFF172033)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(5.0),
                                child: Text(
                                  item['title'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
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

// -------------------------------------------------------------
// شاشة تفاصيل العمل
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  final String type;

  const MediaDetailScreen({super.key, required this.media, required this.type});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  static const String _apiKey = '8265bd1679663a7ea12ac168da84d2e8';

  List<dynamic> _similarMedia = [];
  List<dynamic> _seasons = [];
  int _selectedSeason = 1;
  int _episodesCount = 12;
  String? _imdbId;
  bool _isLoadingDetails = true;
  bool _isLaunchingStream = false;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
    _fetchExtendedInfo();
  }

  void _checkFavoriteStatus() async {
    final isFav = await FavoritesService.isFavorited(widget.media['id'].toString());
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFavorite() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, widget.type);
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

  Future<void> _fetchExtendedInfo() async {
    final id = widget.media['id'];
    try {
      final resDetails = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/${widget.type}/$id?api_key=$_apiKey&append_to_response=external_ids&language=ar-SA'));
      final resSimilar = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/${widget.type}/$id/similar?api_key=$_apiKey&language=ar-SA'));

      if (resDetails.statusCode == 200) {
        final data = jsonDecode(resDetails.body);
        _imdbId = data['external_ids']?['imdb_id'] ?? data['imdb_id'];

        if (widget.type == 'tv' && data['seasons'] != null) {
          _seasons = (data['seasons'] as List).where((s) => (s['season_number'] ?? 0) > 0).toList();
          if (_seasons.isNotEmpty) {
            _selectedSeason = _seasons.first['season_number'];
            _episodesCount = _seasons.first['episode_count'] ?? 12;
          }
        }
      }

      if (resSimilar.statusCode == 200) {
        _similarMedia = jsonDecode(resSimilar.body)['results'] ?? [];
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingDetails = false);
  }

  void _playEpisode(int season, int episode) async {
    setState(() => _isLaunchingStream = true);

    final englishTitle = widget.media['original_title'] ??
        widget.media['original_name'] ??
        widget.media['title'] ??
        widget.media['name'] ??
        '';

    final tmdbId = widget.media['id'].toString();

    final data = await StreamService.getVideoSourceByTitle(
      title: englishTitle,
      tmdbId: tmdbId,
      isTv: widget.type == 'tv',
      season: season,
      episode: episode,
    );

    setState(() => _isLaunchingStream = false);

    if (data != null && mounted) {
      final mediaTitle = widget.media['title'] ?? widget.media['name'] ?? englishTitle;
      final fullTitle = widget.type == 'tv' ? '$mediaTitle - م$season ح$episode' : mediaTitle;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: fullTitle,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
            imdbId: _imdbId,
            type: widget.type,
            season: season,
            episode: episode,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تجهيز رابط ($englishTitle)، جاري معالجته عبر الريلاي...'),
          backgroundColor: const Color(0xFFE50914),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final overview = widget.media['overview'] ?? 'لا يتوفر وصف متاح لهذا العمل حالياً.';
    final poster = widget.media['poster_path'];
    final backdrop = widget.media['backdrop_path'] ?? poster;
    final score = (widget.media['vote_average'] as num?)?.toStringAsFixed(1) ?? '7.8';
    final date = (widget.media['release_date'] ?? widget.media['first_air_date'] ?? '2026')
        .toString()
        .split('-')
        .first;

    final screenWidth = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: _isLoadingDetails
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          height: screenWidth * 0.52,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            image: backdrop != null
                                ? DecorationImage(
                                    image: NetworkImage('https://image.tmdb.org/t/p/original$backdrop'),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                        Container(
                          height: screenWidth * 0.52,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF07090E), Colors.transparent],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: poster != null
                                    ? Image.network('https://image.tmdb.org/t/p/w500$poster',
                                        width: 95, height: 140, fit: BoxFit.cover)
                                    : Container(width: 95, height: 140, color: const Color(0xFF172033)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: const TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                                          child: Text('⭐ $score',
                                              style: const TextStyle(
                                                  color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(date, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F1422),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: const Text('السيرفر والترجمة: جاهز تلقائياً',
                                          style: TextStyle(fontSize: 11, color: Color(0xFF00F0FF))),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE50914),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _isLaunchingStream ? null : () => _playEpisode(_selectedSeason, 1),
                                    child: _isLaunchingStream
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                                              const SizedBox(width: 8),
                                              Text(
                                                widget.type == 'tv' ? 'مشاهدة الحلقة الأولى' : 'مشاهدة الفيلم الآن',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F1422),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _isFav ? const Color(0xFFF59E0B) : Colors.white24,
                                    width: 1.5,
                                  ),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _isFav ? Icons.bookmark_added_rounded : Icons.bookmark_border_rounded,
                                    color: _isFav ? const Color(0xFFF59E0B) : Colors.white70,
                                  ),
                                  onPressed: _toggleFavorite,
                                  tooltip: 'حفظ في المفضلة',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(overview,
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4)),
                        ],
                      ),
                    ),
                    if (widget.type == 'tv') ...[
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('المواسم والحلقات:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 8),
                      if (_seasons.isNotEmpty)
                        SizedBox(
                          height: 38,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            itemCount: _seasons.length,
                            itemBuilder: (ctx, i) {
                              final s = _seasons[i];
                              final sNum = s['season_number'];
                              final isSelected = sNum == _selectedSeason;

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedSeason = sNum;
                                    _episodesCount = s['episode_count'] ?? 12;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFE50914) : const Color(0xFF0F1422),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text('الموسم $sNum',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              );
                            },
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.4,
                          ),
                          itemCount: _episodesCount,
                          itemBuilder: (ctx, i) {
                            final epNum = i + 1;
                            return InkWell(
                              onTap: () => _playEpisode(_selectedSeason, epNum),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF172033),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                child: Center(
                                  child: Text('ح $epNum',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_similarMedia.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('🎯 أعمال مشابهة ومقترحة:',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 190,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _similarMedia.length,
                          itemBuilder: (ctx, i) {
                            final item = _similarMedia[i];
                            final simTitle = item['title'] ?? item['name'] ?? '';
                            final simPoster = item['poster_path'];

                            return InkWell(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MediaDetailScreen(media: item, type: widget.type),
                                  ),
                                );
                              },
                              child: Container(
                                width: 105,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F1422),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      child: simPoster != null
                                          ? Image.network('https://image.tmdb.org/t/p/w500$simPoster',
                                              height: 135, width: double.infinity, fit: BoxFit.cover)
                                          : Container(height: 135, color: const Color(0xFF172033)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Text(simTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// مشغل سينمائي احترافي (تخطي شارة البداية +85s + جودات + ترجمة فورية)
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final String? imdbId;
  final String type;
  final int season;
  final int episode;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.imdbId,
    required this.type,
    this.season = 1,
    this.episode = 1,
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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _initFastPlayer(_currentUrl!);
    _fetchSubtitlesInBackground();
  }

  void _initFastPlayer(String streamUrl, {List<Subtitle>? subs}) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_checkIntroTiming);
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
    _videoPlayerController!.addListener(_checkIntroTiming);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
      subtitle: subs != null && subs.isNotEmpty ? Subtitles(subs) : null,
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16.5,
            fontWeight: FontWeight.bold,
            height: 1.3,
            shadows: [
              Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black),
            ],
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
        ];
      },
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _checkIntroTiming() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

    final seconds = _videoPlayerController!.value.position.inSeconds;
    final shouldShow = seconds >= 2 && seconds <= 120;

    if (shouldShow != _showSkipIntroBtn && mounted) {
      setState(() => _showSkipIntroBtn = shouldShow);
    }
  }

  void _skipIntro() {
    if (_videoPlayerController == null) return;
    final currentPos = _videoPlayerController!.value.position;
    final targetPos = currentPos + const Duration(seconds: 85);
    _videoPlayerController!.seekTo(targetPos);
    setState(() => _showSkipIntroBtn = false);
  }

  void _fetchSubtitlesInBackground() async {
    if (widget.imdbId != null && widget.imdbId!.isNotEmpty) {
      try {
        final endpoint = widget.type == 'tv'
            ? 'https://opensubtitles-v3.strem.io/subtitles/series/${widget.imdbId}:${widget.season}:${widget.episode}.json'
            : 'https://opensubtitles-v3.strem.io/subtitles/movie/${widget.imdbId}.json';

        final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final subs = data['subtitles'] as List?;
          if (subs != null && subs.isNotEmpty) {
            final arSub = subs.firstWhere(
              (s) => s['lang'] == 'ara' || s['lang'] == 'ar' || s['lang'] == 'arabic',
              orElse: () => subs.first,
            );
            if (arSub['url'] != null) {
              final subContent = await http.get(Uri.parse(arSub['url'])).timeout(const Duration(seconds: 4));
              if (subContent.statusCode == 200) {
                final parsed = _parseSrt(subContent.body);
                if (mounted && parsed.isNotEmpty) {
                  _initFastPlayer(_currentUrl!, subs: parsed);
                }
              }
            }
          }
        }
      } catch (_) {}
    }
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

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Text('اختر جودة البث', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(color: Colors.white10),
              ...widget.qualities.map((q) {
                final res = q['resolution'] ?? 'تلقائي';
                final url = q['url'];
                final isSelected = url == _currentUrl;

                return ListTile(
                  leading: Icon(Icons.video_settings, color: isSelected ? const Color(0xFF00F0FF) : Colors.white60),
                  title: Text(res,
                      style: TextStyle(
                          color: isSelected ? const Color(0xFF00F0FF) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_checkIntroTiming);
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
        actions: [
          if (widget.qualities.length > 1)
            IconButton(
              icon: const Icon(Icons.hd_outlined, color: Color(0xFF00F0FF)),
              onPressed: _showQualitySheet,
            )
        ],
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
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward_rounded, color: Color(0xFFF59E0B), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'تخطي المقدمة (+85s)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00F0FF)),
                  SizedBox(height: 14),
                  Text('جاري فتح البث الفوري...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
      ),
    );
  }
}
