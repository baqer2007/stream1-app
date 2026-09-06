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
// الصفحة الرئيسية
// -------------------------------------------------------------
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
  List<dynamic> _categories = [];

  int _currentPage = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _activeCategoryTitle = 'الكل';

  @override
  void initState() {
    super.initState();
    _loadCategories();
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

  // جلب التصنيفات الحقيقية من API سينمانا DevTools
  Future<void> _loadCategories() async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/mainCategories?lang=en'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      );
      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (decoded is List && mounted) {
          setState(() => _categories = decoded);
        }
      }
    } catch (_) {}
  }

  // جلب المحتوى المباشر عبر AdvancedSearch
  Future<void> _loadCeeContent({bool reset = false, String? categoryId}) async {
    if (reset) {
      _currentPage = 0;
      _hasMore = true;
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      String urlStr = 'https://cee.buzz/api/android/AdvancedSearch?level=0&page=$_currentPage&year=1900,2026';
      if (categoryId != null && categoryId != 'all') {
        urlStr += '&category=$categoryId';
      }

      final res = await http.get(Uri.parse(urlStr), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Accept': 'application/json, text/plain, */*',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
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
              _currentPage++;
            }

            _movies = _items.where((it) => (it['kind']?.toString() ?? '1') == '1' && (it['season'] == null || it['season'] == '0')).toList();
            _series = _items.where((it) => (it['kind']?.toString() ?? '1') != '1' || (it['season'] != null && it['season'] != '0')).toList();

            _isLoadingInitial = false;
            _isLoadingMore = false;
          });

          StreamService.preCacheMovieTitles(list.take(10).map((e) => {
            'id': e['nb']?.toString() ?? '',
            'title': e['en_title']?.toString() ?? e['ar_title']?.toString() ?? ''
          }).toList());
        }
      } else {
        if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  void _search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/AdvancedSearch?videoTitle=${Uri.encodeComponent(clean)}&level=0&page=0&year=1900,2026'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      ).timeout(const Duration(seconds: 8));

      Navigator.pop(context);

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        if (mounted && results.isNotEmpty) {
          setState(() {
            _items = results;
            _hasMore = false;
            _activeCategoryTitle = 'نتائج البحث: $clean';
          });
        }
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
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE50914), Color(0xFF0F1422)])),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: const [
                    Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    SizedBox(height: 4),
                    Text('أقسام وتصنيفات سينمانا الحقيقية', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
                title: const Text('الرئيسية'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _activeCategoryTitle = 'الكل');
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
              ..._categories.map((c) {
                final cId = c['nb']?.toString() ?? '';
                final cTitle = c['title']?.toString() ?? '';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.movie_creation_outlined, size: 20, color: Colors.white60),
                  title: Text(cTitle),
                  selected: _activeCategoryTitle == cTitle,
                  selectedColor: const Color(0xFF00F0FF),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _activeCategoryTitle = cTitle);
                    _loadCeeContent(reset: true, categoryId: cId);
                  },
                );
              }),
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
                          onSubmitted: _search,
                          decoration: InputDecoration(
                            hintText: 'ابحث عن أي فيلم، مسلسل أو أنمي...',
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
                      if (_items.isNotEmpty) _buildHeroBanner(_items.first, screenWidth),
                      if (_movies.isNotEmpty) _buildSectionShelf('🎬 أحدث الأفلام المتوفرة', _movies),
                      if (_series.isNotEmpty) _buildSectionShelf('📺 المسلسلات والأنمي المتجددة', _series),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                        child: Text(
                          _activeCategoryTitle == 'الكل' ? '🌐 جميع العروض' : '📂 $_activeCategoryTitle',
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
    final poster = item['imgObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['imgThumbObjUrl'] ?? item['img'] ?? '';
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(height: width * 0.52, width: double.infinity, decoration: BoxDecoration(image: poster.toString().isNotEmpty ? DecorationImage(image: NetworkImage(poster.toString()), fit: BoxFit.cover) : null)),
        Container(height: width * 0.52, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF07090E), Colors.transparent]))),
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
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
              final mTitle = item['ar_title'] ?? item['en_title'] ?? '';
              final poster = item['imgObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['imgThumbObjUrl'] ?? item['img'] ?? '';
              final score = item['stars']?.toString() ?? '8.0';
              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: cardWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: poster.toString().isNotEmpty ? Image.network(poster.toString(), height: cardHeight, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: cardHeight, color: const Color(0xFF172033))) : Container(height: cardHeight, color: const Color(0xFF172033))),
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
          final title = item['ar_title'] ?? item['en_title'] ?? '';
          final poster = item['imgObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['imgThumbObjUrl'] ?? item['img'] ?? '';
          final stars = item['stars']?.toString() ?? '8.0';
          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: poster.toString().isNotEmpty ? Image.network(poster.toString(), width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF172033))) : Container(color: const Color(0xFF172033))),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
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
// شاشة التفاصيل (الحلقات وسحب الرابط الموقع الأصلي للترجمة)
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
      _loadEpisodesRecursively(0);
    }
  }

  void _checkFav() async {
    final nb = widget.media['nb']?.toString() ?? '';
    final isFav = await FavoritesService.isFavorited(nb);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFav() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
    if (mounted) setState(() => _isFav = newState);
  }

  // سحب تتابعي كامل لجميع الحلقات بدون توقف
  Future<void> _loadEpisodesRecursively(int page) async {
    if (page == 0) setState(() => _isLoadingEpisodes = true);
    final nb = widget.media['nb'].toString();

    try {
      final epRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/50/series_episodes_list/$nb/itemsPerPage/50/pageNumber/$page/level/0'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://cee.buzz/home'},
      );

      if (epRes.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(epRes.bodyBytes, allowMalformed: true));
        List eList = (decoded is List) ? decoded : (decoded['articles'] ?? []);

        if (mounted) {
          setState(() {
            if (page == 0) {
              _episodes = eList;
            } else {
              _episodes.addAll(eList);
            }
          });

          // تكرار السحب للصفحات التالية إذا كانت الحلقات أكثر من 45
          if (eList.length >= 45) {
            _loadEpisodesRecursively(page + 1);
          } else {
            setState(() => _isLoadingEpisodes = false);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  // تشغيل الفيديو مع جلب رابط الترجمة الموقّع الأصلي عبر allVideoInfo
  void _playStream({String? targetNb, String? epTitle}) async {
    setState(() => _isLaunching = true);

    final nb = targetNb ?? widget.media['nb'].toString();
    final title = epTitle ?? widget.media['ar_title'] ?? widget.media['en_title'] ?? 'بث مباشر';
    
    String exactSubUrl = '';

    // استعلام مباشر عن تفاصيل الحلقة/الفيلم للحصول على رابط الترجمة الموقّع (Signed AWS URL)
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل هذا الرابط حالياً'), backgroundColor: Color(0xFFE50914)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = widget.media['imgObjUrl'] ?? widget.media['imgMediumThumbObjUrl'] ?? widget.media['imgThumbObjUrl'] ?? widget.media['img'] ?? '';
    final stars = widget.media['stars']?.toString() ?? '8.0';
    final story = widget.media['ar_content'] ?? widget.media['en_content'] ?? 'لا يوجد وصف متاح.';

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
                    child: poster.toString().isNotEmpty ? Image.network(poster.toString(), width: 110, height: 160, fit: BoxFit.cover) : Container(width: 110, height: 160, color: const Color(0xFF172033)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 8),
                        Text('⭐ $stars', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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
                Text('الحلقات المتوفرة (${_episodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _isLoadingEpisodes && _episodes.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.3),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final ep = _episodes[i];
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
// المشغل مع قراءة ملفات WebVTT و SRT الموقعة
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
    // جلب ملف الترجمة بالرابط الموقّع الأصلي دون أي تعديل يكسر تصريح الوصول
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
      body: Center(child: _isReady && _chewieController != null ? Chewie(controller: _chewieController!) : const CircularProgressIndicator(color: Color(0xFF00F0FF))),
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
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : _favorites.isEmpty ? const Center(child: Text('لا يوجد مفضلة')) : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.58),
          itemCount: _favorites.length,
          itemBuilder: (ctx, i) {
            final item = _favorites[i];
            final poster = item['imgObjUrl'] ?? item['imgMediumThumbObjUrl'] ?? item['imgThumbObjUrl'] ?? item['img'] ?? '';
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _load()),
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: poster.toString().isNotEmpty ? Image.network(poster.toString(), fit: BoxFit.cover) : Container())),
                    Padding(padding: const EdgeInsets.all(5), child: Text(item['ar_title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
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
