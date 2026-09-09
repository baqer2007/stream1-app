import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';

class Subtitle {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  Subtitle({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });
}

class LocalStorageService {
  static Future<List<Map<String, dynamic>>> getList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<void> setList(String key, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 50, String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => (x[idField] ?? x['id'])?.toString() == (item[idField] ?? item['id'])?.toString());
    list.insert(0, item);
    if (list.length > maxLength) list.removeRange(maxLength, list.length);
    await setList(key, list);
  }

  static Future<void> removeItem(String key, String id, {String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => (x[idField] ?? x['id'])?.toString() == id);
    await setList(key, list);
  }
}

class ActiveDownload {
  final String id;
  final String title;
  final String url;
  final String poster;
  double progress;
  int downloadedBytes;
  int totalBytes;
  http.Client? client;
  bool isCancelled = false;

  ActiveDownload({
    required this.id,
    required this.title,
    required this.url,
    required this.poster,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  });
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final Map<String, ActiveDownload> activeDownloads = {};

  Future<String> _getAppStoragePath() async {
    final paths = [
      '/storage/emulated/0/Download/ONEBR_TV',
      '/sdcard/Download/ONEBR_TV',
    ];
    for (var p in paths) {
      final d = Directory(p);
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
        return d.path;
      } catch (_) {}
    }
    return Directory.systemTemp.path;
  }

  Future<void> startDownload({
    required String targetId,
    required String title,
    required String url,
    required String poster,
  }) async {
    if (activeDownloads.containsKey(targetId)) return;

    final download = ActiveDownload(id: targetId, title: title, url: url, poster: poster);
    activeDownloads[targetId] = download;
    notifyListeners();

    try {
      final basePath = await _getAppStoragePath();
      final safeName = '${targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.mp4';
      final filePath = '$basePath/$safeName';
      final file = File(filePath);

      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = file.lengthSync();
      }

      await LocalStorageService.appendItem('downloaded_works_list', {
        'nb': targetId,
        'title': title,
        'path': filePath,
        'size': 'قيد التنزيل...',
        'poster': poster,
      });

      final client = http.Client();
      download.client = client;

      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(StreamService.stealthHeaders);
      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      final response = await client.send(request);
      final total = (response.contentLength ?? 0) + downloadedBytes;
      download.totalBytes = total;

      final sink = file.openWrite(mode: FileMode.append);

      await response.stream.listen((chunk) {
        if (download.isCancelled) {
          sink.close();
          return;
        }
        downloadedBytes += chunk.length;
        download.downloadedBytes = downloadedBytes;
        sink.add(chunk);
        if (total > 0) {
          download.progress = (downloadedBytes / total).clamp(0.0, 1.0);
          notifyListeners();
        }
      }).asFuture();

      await sink.close();

      if (!download.isCancelled && file.existsSync()) {
        final fileSizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        await LocalStorageService.appendItem('downloaded_works_list', {
          'nb': targetId,
          'title': title,
          'path': filePath,
          'size': '$fileSizeMb ميغابايت',
          'poster': poster,
        });
      }
    } catch (_) {}

    activeDownloads.remove(targetId);
    notifyListeners();
  }

  void cancelDownload(String targetId) {
    if (activeDownloads.containsKey(targetId)) {
      activeDownloads[targetId]!.isCancelled = true;
      activeDownloads[targetId]!.client?.close();
      activeDownloads.remove(targetId);
      notifyListeners();
    }
  }
}

class PlayerSettings extends ChangeNotifier {
  static final PlayerSettings instance = PlayerSettings._();
  PlayerSettings._();

  int seekDuration = 10;
  String filterLevel = 'الافتراضي'; // الافتراضي، عائلي، أطفال
  bool skipSensitiveScenes = true;
  double subFontSize = 18.0;
  Color subColor = Colors.white;
  Color subShadowColor = Colors.black87;
  bool subHasShadow = true;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    seekDuration = p.getInt('player_seek_dur') ?? 10;
    filterLevel = p.getString('player_filter_lvl') ?? 'الافتراضي';
    skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
    subFontSize = p.getDouble('player_sub_size') ?? 18.0;
  }

  void updateSeek(int sec) async {
    seekDuration = sec;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('player_seek_dur', sec);
  }

  void updateFilter(String lvl) async {
    filterLevel = lvl;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('player_filter_lvl', lvl);
  }

  void updateSkipScenes(bool val) async {
    skipSensitiveScenes = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('player_skip_sens', val);
  }

  void updateSubStyle({double? size, Color? color, bool? shadow}) {
    if (size != null) subFontSize = size;
    if (color != null) subColor = color;
    if (shadow != null) subHasShadow = shadow;
    notifyListeners();
  }

  void resetSubtitles() {
    subFontSize = 18.0;
    subColor = Colors.white;
    subHasShadow = true;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlayerSettings.instance.init();
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
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFFE50914),
        cardColor: const Color(0xFF131B2A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF131B2A),
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
  int _currentNavIndex = 0;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _officialCategories = [
    {'id': 0, 'ar': 'الكل'},
    {'id': 88, 'ar': 'أنمي ياباني'},
    {'id': 57, 'ar': 'رسوم متحركة'},
    {'id': 84, 'ar': 'أكشن وإثارة'},
    {'id': 62, 'ar': 'دراما'},
    {'id': 59, 'ar': 'كوميديا'},
    {'id': 70, 'ar': 'رعب'},
    {'id': 56, 'ar': 'مغامرة'},
    {'id': 60, 'ar': 'جريمة وغموض'},
    {'id': 78, 'ar': 'خيال علمي'},
    {'id': 77, 'ar': 'رومانسي'},
    {'id': 89, 'ar': 'حروب وتاريخ'},
  ];

  List<dynamic> _heroItems = [];
  List<dynamic> _streamFeed = [];
  final Set<String> _uniqueIds = {};
  int _page = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // التحميل التلقائي المستمر كلما نزل المستخدم لأسفل (Infinite Scroll)
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _fetchMoreWorks();
        }
      }
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingMore = true);
    final res = await Future.wait([
      StreamService.fetchFeed(isSeries: false, page: 0, perPage: 12),
      StreamService.fetchFeed(isSeries: true, page: 0, perPage: 12),
      StreamService.fetchByCategory(88, page: 0), // جلب باقة أنمي مباشرة
    ]);

    final List<dynamic> combined = [...res[0], ...res[1], ...res[2]];
    final List<dynamic> deduplicated = [];

    for (var item in combined) {
      final id = (item['nb'] ?? item['id'])?.toString();
      if (id != null && !_uniqueIds.contains(id)) {
        _uniqueIds.add(id);
        deduplicated.add(item);
      }
    }

    if (mounted) {
      setState(() {
        _heroItems = deduplicated.take(5).toList();
        _streamFeed = deduplicated;
        _isLoadingMore = false;
        _page = 1;
      });
    }
  }

  Future<void> _fetchMoreWorks() async {
    setState(() => _isLoadingMore = true);
    final newItems = await StreamService.fetchFeed(isSeries: _page % 2 == 0, page: _page, perPage: 24);

    final List<dynamic> added = [];
    for (var item in newItems) {
      final id = (item['nb'] ?? item['id'])?.toString();
      if (id != null && !_uniqueIds.contains(id)) {
        _uniqueIds.add(id);
        added.add(item);
      }
    }

    if (mounted) {
      setState(() {
        _streamFeed.addAll(added);
        _isLoadingMore = false;
        if (added.isEmpty) _hasMore = false;
        _page++;
      });
    }
  }

  void _openCategoryView(Map<String, dynamic> cat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryCatalogScreen(category: cat),
      ),
    );
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0E17),
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('ONEBR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
              ),
              const SizedBox(width: 8),
              const Text('سينما بلس', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white70),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: const Color(0xFFE50914),
          onRefresh: () async {
            _uniqueIds.clear();
            await _loadInitialData();
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // شريط التصنيفات الأفقي السريع
                SizedBox(
                  height: 42,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _officialCategories.length,
                    itemBuilder: (ctx, i) {
                      final c = _officialCategories[i];
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ActionChip(
                          backgroundColor: const Color(0xFF182234),
                          side: BorderSide(color: Colors.white.withOpacity(0.08)),
                          label: Text(c['ar'], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          onPressed: () => _openCategoryView(c),
                        ),
                      );
                    },
                  ),
                ),

                // بانر الواجهة
                if (_heroItems.isNotEmpty) _buildHeroSlider(),

                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('أحدث الإصدارات المضافة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Icon(Icons.auto_awesome, color: Color(0xFFE50914), size: 18),
                    ],
                  ),
                ),

                // شبكة أعمال تتسع وتزداد كلما نزل المستخدم بدون تكرار
                _buildDynamicCatalogGrid(),

                if (_isLoadingMore)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2)),
                  ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          backgroundColor: const Color(0xFF101726),
          selectedItemColor: const Color(0xFFE50914),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          onTap: (i) {
            setState(() => _currentNavIndex = i);
            if (i == 1) _showCategoriesModal();
            if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            if (i == 3) Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsCenterScreen()));
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.movie_creation_outlined), activeIcon: Icon(Icons.movie_creation_rounded), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.category_outlined), activeIcon: Icon(Icons.category_rounded), label: 'التصنيفات'),
            BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'بحث'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSlider() {
    final item = _heroItems.first;
    final poster = StreamService.extractPoster(item);
    final title = item['ar_title'] ?? item['en_title'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: poster.isNotEmpty ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover) : null,
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            bottom: 16, right: 16, left: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _openDetails(item),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: const Text('تشغيل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicCatalogGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.58,
        ),
        itemCount: _streamFeed.length,
        itemBuilder: (ctx, i) {
          final item = _streamFeed[i];
          final poster = StreamService.extractPoster(item);
          final title = item['ar_title'] ?? item['en_title'] ?? '';
          final score = (item['stars'] ?? '7.0').toString();

          return InkWell(
            onTap: () => _openDetails(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: poster.isNotEmpty
                        ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                        : Container(color: const Color(0xFF131B2A)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                    const SizedBox(width: 3),
                    Text(score, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCategoriesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('الأقسام والتصنيفات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ..._officialCategories.map((cat) => ListTile(
                  title: Text(cat['ar'], style: const TextStyle(color: Colors.white70)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    _openCategoryView(cat);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// صفحة عرض أعمال التصنيف عند الضغط على "المزيد" أو اختيار التصنيف
// =========================================================================
class CategoryCatalogScreen extends StatefulWidget {
  final Map<String, dynamic> category;
  const CategoryCatalogScreen({super.key, required this.category});

  @override
  State<CategoryCatalogScreen> createState() => _CategoryCatalogScreenState();
}

class _CategoryCatalogScreenState extends State<CategoryCatalogScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<dynamic> _items = [];
  final Set<String> _unique = {};
  int _page = 0;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
        if (!_isLoading && _hasMore) _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final res = await StreamService.fetchByCategory(widget.category['id'], page: _page);
    final List<dynamic> fresh = [];
    for (var it in res) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_unique.contains(id)) {
        _unique.add(id);
        fresh.add(it);
      }
    }
    if (mounted) {
      setState(() {
        _items.addAll(fresh);
        _isLoading = false;
        if (fresh.isEmpty) _hasMore = false;
        _page++;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0E17),
          title: Text(widget.category['ar'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.58,
          ),
          itemCount: _items.length,
          itemBuilder: (ctx, i) {
            final it = _items[i];
            final poster = StreamService.extractPoster(it);
            final title = it['ar_title'] ?? it['en_title'] ?? '';

            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: poster.isNotEmpty
                          ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                          : Container(color: const Color(0xFF131B2A)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunching = false;
  List<dynamic> _episodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = (widget.media['is_series_fixed'] == true) || (widget.media['season'] != null && widget.media['season'].toString() != '0');
    if (_isSeries) _loadEpisodes();
  }

  void _loadEpisodes() async {
    final seriesId = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final eps = await StreamService.getSeriesEpisodes(seriesId);
    if (mounted) setState(() => _episodes = eps);
  }

  void _play(Map<String, dynamic>? episodeData, int? epIndex) async {
    setState(() => _isLaunching = true);

    final targetId = episodeData != null
        ? (episodeData['nb'] ?? episodeData['id']).toString()
        : (widget.media['nb'] ?? widget.media['id']).toString();

    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final source = await StreamService.getVideoSource(targetId);
    final subUrl = await StreamService.getArabicSubtitleUrl(targetId);

    setState(() => _isLaunching = false);

    if (source != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: title,
            subtitleTextHeader: _isSeries ? 'الموسم 1 - الحلقة $epIndex' : '',
            videoUrl: source['video_url'],
            subtitleUrl: subUrl,
            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = StreamService.extractPoster(widget.media);
    final story = widget.media['ar_content'] ?? widget.media['en_content'] ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: poster.isNotEmpty ? Image.network(poster, width: 115, height: 165, fit: BoxFit.cover) : Container(width: 115, height: 165, color: Colors.grey.shade900),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(_isSeries ? 'مسلسل' : 'فيلم', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLaunching ? null : () => _play(_isSeries && _episodes.isNotEmpty ? _episodes.first : null, 1),
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                        label: Text(_isSeries ? 'مشاهدة الحلقة 1' : 'مشاهدة الآن', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (story.isNotEmpty) ...[
              const Text('نبذة عن العمل', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.6)),
            ],
            if (_isSeries && _episodes.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('قائمة الحلقات (${_episodes.length})', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._episodes.asMap().entries.map((e) {
                final ep = e.value;
                final idx = e.key + 1;
                return ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914)),
                  title: Text('الحلقة $idx', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white54),
                    onPressed: () {
                      final targetId = (ep['nb'] ?? ep['id']).toString();
                      StreamService.getVideoSource(targetId).then((src) {
                        if (src != null) {
                          DownloadManager.instance.startDownload(
                            targetId: targetId,
                            title: '$title - حلقة $idx',
                            url: src['video_url'],
                            poster: poster,
                          );
                        }
                      });
                    },
                  ),
                  onTap: () => _play(ep, idx),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// مشغل الفيديو المتكامل والمطور وفق الصور 1000018617 / 1000018618 / 1000018627
// =========================================================================
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String subtitleTextHeader;
  final String videoUrl;
  final String subtitleUrl;
  final List<Map<String, dynamic>> qualities;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    this.subtitleTextHeader = '',
    required this.videoUrl,
    this.subtitleUrl = '',
    required this.qualities,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _showControls = true;
  Timer? _hideTimer;

  String _activeQuality = '240p';
  BoxFit _videoFit = BoxFit.contain;

  List<Subtitle> _subtitles = [];
  String _currentSubText = '';

  @override
  void initState() {
    super.initState();
    _initPlayer(widget.videoUrl);
    if (widget.subtitleUrl.isNotEmpty) _loadSubs(widget.subtitleUrl);
  }

  void _loadSubs(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() => _subtitles = _parseSrt(utf8.decode(res.bodyBytes, allowMalformed: true)));
      }
    } catch (_) {}
  }

  List<Subtitle> _parseSrt(String text) {
    final List<Subtitle> list = [];
    final pattern = RegExp(r'(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\r?\n([\s\S]*?)(?=\n\n|\r\n\r\n|$)');
    final matches = pattern.allMatches(text);
    int idx = 0;
    for (var m in matches) {
      final s = _durationFromStr(m.group(1)!);
      final e = _durationFromStr(m.group(2)!);
      final txt = m.group(3)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (txt.isNotEmpty) list.add(Subtitle(index: idx++, start: s, end: e, text: txt));
    }
    return list;
  }

  Duration _durationFromStr(String str) {
    final parts = str.replaceAll(',', '.').split(':');
    final sParts = parts[2].split('.');
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      seconds: int.parse(sParts[0]),
      milliseconds: int.parse(sParts[1].padRight(3, '0').substring(0, 3)),
    );
  }

  void _initPlayer(String url) async {
    await _controller?.dispose();
    if (mounted) setState(() => _isReady = false);

    _controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: StreamService.stealthHeaders);
    await _controller!.initialize();
    _controller!.play();

    _controller!.addListener(() {
      if (_controller!.value.isInitialized && _subtitles.isNotEmpty) {
        final pos = _controller!.value.position;
        final sub = _subtitles.firstWhere((s) => pos >= s.start && pos <= s.end, orElse: () => Subtitle(index: -1, start: Duration.zero, end: Duration.zero, text: ''));
        if (sub.text != _currentSubText && mounted) {
          setState(() => _currentSubText = sub.text);
        }
      }
      if (mounted) setState(() {});
    });

    _startTimer();
    if (mounted) setState(() => _isReady = true);
  }

  void _startTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startTimer();
  }

  String _formatTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _openSettingsBottomSheet() {
    final settings = PlayerSettings.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined, color: Colors.white70),
                title: const Text('دقة الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text(_activeQuality, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showQualityPicker();
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.closed_caption_outlined, color: Colors.white70),
                title: const Text('إعدادات الترجمة المتقدمة', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()));
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70),
                title: const Text('أبعاد الشاشة', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text(_videoFit == BoxFit.cover ? 'ممتلئ' : 'أصلي', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                onTap: () {
                  setState(() {
                    _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
                  });
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.fast_forward_rounded, color: Colors.white70),
                title: const Text('فترة تمرير الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text('${settings.seekDuration} ثوانٍ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showSeekPicker();
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                title: const Text('حذف وتخطي المشاهد غير الملائمة', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: settings.skipSensitiveScenes,
                activeColor: const Color(0xFFE50914),
                onChanged: (val) {
                  settings.updateSkipScenes(val);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSeekPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2A),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [5, 10, 15, 30].map((s) => ListTile(
          title: Text('$s ثوانٍ', style: const TextStyle(color: Colors.white)),
          onTap: () {
            PlayerSettings.instance.updateSeek(s);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2A),
      builder: (_) => ListView(
        shrinkWrap: true,
        children: widget.qualities.map((q) {
          final res = q['resolution'] ?? '240p';
          final url = q['url'] ?? '';
          return ListTile(
            title: Text(res, style: const TextStyle(color: Colors.white)),
            trailing: _activeQuality == res ? const Icon(Icons.check, color: Color(0xFFE50914)) : null,
            onTap: () {
              Navigator.pop(context);
              setState(() => _activeQuality = res);
              _initPlayer(url);
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = PlayerSettings.instance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: (_isReady && _controller != null)
                    ? FittedBox(
                        fit: _videoFit,
                        child: SizedBox(
                          width: _controller!.value.size.width,
                          height: _controller!.value.size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : const CircularProgressIndicator(color: Color(0xFFE50914)),
              ),

              // النص المترجم القابل للتخصيص
              if (_currentSubText.isNotEmpty)
                Positioned(
                  bottom: 60, left: 20, right: 20,
                  child: Center(
                    child: Text(
                      _currentSubText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: settings.subColor,
                        fontSize: settings.subFontSize,
                        fontWeight: FontWeight.bold,
                        shadows: settings.subHasShadow ? [const Shadow(blurRadius: 10, color: Colors.black)] : null,
                      ),
                    ),
                  ),
                ),

              if (_showControls) ...[
                Positioned(
                  top: 10, left: 14, right: 14,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                            if (widget.subtitleTextHeader.isNotEmpty)
                              Text(widget.subtitleTextHeader, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.tune_rounded, color: Colors.white),
                          onPressed: _openSettingsBottomSheet,
                        ),
                      ],
                    ),
                  ),
                ),

                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white),
                        onPressed: () {
                          final p = _controller!.value.position - Duration(seconds: settings.seekDuration);
                          _controller!.seekTo(p < Duration.zero ? Duration.zero : p);
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 48,
                        icon: Icon(_controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                          });
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.fast_forward_rounded, color: Colors.white),
                        onPressed: () {
                          final p = _controller!.value.position + Duration(seconds: settings.seekDuration);
                          _controller!.seekTo(p);
                        },
                      ),
                    ],
                  ),
                ),

                if (_controller != null && _controller!.value.isInitialized)
                  Positioned(
                    bottom: 12, left: 16, right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            thumbColor: const Color(0xFFE50914),
                            activeTrackColor: const Color(0xFFE50914),
                            inactiveTrackColor: Colors.white24,
                          ),
                          child: Slider(
                            value: _controller!.value.position.inMilliseconds.toDouble().clamp(0.0, _controller!.value.duration.inMilliseconds.toDouble()),
                            min: 0.0,
                            max: _controller!.value.duration.inMilliseconds.toDouble(),
                            onChanged: (v) => _controller!.seekTo(Duration(milliseconds: v.toInt())),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTime(_controller!.value.position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                              Row(
                                children: [
                                  Text(_formatTime(_controller!.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () {
                                      final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
                                      SystemChrome.setPreferredOrientations(isPortrait
                                          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
                                          : [DeviceOrientation.portraitUp]);
                                    },
                                    child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// شاشة إعدادات الترجمة المتقدمة (مطابقة للصورة 1000018629)
// =========================================================================
class SubtitleSettingsScreen extends StatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  State<SubtitleSettingsScreen> createState() => _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState extends State<SubtitleSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = PlayerSettings.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0E17),
          title: const Text('إعدادات الترجمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // شاشة المعاينة الحية للترجمة
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1534447677768-be436bb09401?q=80&w=600'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Center(
                child: Text(
                  'ابقَ أصدقائك قريبين، ولكن أعداءك أقرب\nKeep your friends close, but your enemies closer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: s.subColor,
                    fontSize: s.subFontSize,
                    fontWeight: FontWeight.bold,
                    shadows: s.subHasShadow ? [const Shadow(blurRadius: 10, color: Colors.black)] : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              title: const Text('حجم خط الترجمة', style: TextStyle(color: Colors.white, fontSize: 13)),
              trailing: DropdownButton<double>(
                dropdownColor: const Color(0xFF131B2A),
                value: s.subFontSize,
                items: const [
                  DropdownMenuItem(value: 14.0, child: Text('صغير', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: 18.0, child: Text('متوسط', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: 24.0, child: Text('كبير', style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => setState(() => s.updateSubStyle(size: v)),
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              title: const Text('لون الخط', style: TextStyle(color: Colors.white, fontSize: 13)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _colorBubble(Colors.white, s.subColor == Colors.white, () => setState(() => s.updateSubStyle(color: Colors.white))),
                  _colorBubble(Colors.yellow, s.subColor == Colors.yellow, () => setState(() => s.updateSubStyle(color: Colors.yellow))),
                  _colorBubble(const Color(0xFF00F0FF), s.subColor == const Color(0xFF00F0FF), () => setState(() => s.updateSubStyle(color: const Color(0xFF00F0FF)))),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            SwitchListTile(
              title: const Text('ظل حواف الخط', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: s.subHasShadow,
              activeColor: const Color(0xFFE50914),
              onChanged: (v) => setState(() => s.updateSubStyle(shadow: v)),
            ),
            const SizedBox(height: 30),
            OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
              onPressed: () => setState(() => s.resetSubtitles()),
              child: const Text('إعادة ضبط إعدادات الترجمة', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorBubble(Color c, bool isSelected, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: const Color(0xFFE50914), width: 2.5) : null,
        ),
      ),
    );
  }
}

// =========================================================================
// مركز الإعدادات والتصفية (مطابق للصورة 1000018627 و 1000018628)
// =========================================================================
class SettingsCenterScreen extends StatefulWidget {
  const SettingsCenterScreen({super.key});

  @override
  State<SettingsCenterScreen> createState() => _SettingsCenterScreenState();
}

class _SettingsCenterScreenState extends State<SettingsCenterScreen> {
  @override
  Widget build(BuildContext context) {
    final s = PlayerSettings.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(title: const Text('الإعدادات العامة'), backgroundColor: const Color(0xFF0A0E17)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('تصفية المحتوى', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: ['الافتراضي', 'عائلي', 'أطفال'].map((lvl) {
                final isSel = s.filterLevel == lvl;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSel ? const Color(0xFFE50914) : const Color(0xFF131B2A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => setState(() => s.updateFilter(lvl)),
                      child: Text(lvl, style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('حذف وتخطي المشاهد غير الملائمة', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: s.skipSensitiveScenes,
              activeColor: const Color(0xFFE50914),
              onChanged: (v) => setState(() => s.updateSkipScenes(v)),
            ),
            const Divider(color: Colors.white10, height: 32),
            ListTile(
              title: const Text('فترة تمرير الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
              trailing: Text('${s.seekDuration} ثوانٍ', style: const TextStyle(color: Colors.white54)),
            ),
            ListTile(
              title: const Text('إعدادات مظهر الترجمة', style: TextStyle(color: Colors.white, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _results = [];
  bool _isSearching = false;

  void _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final res = await StreamService.searchContent(q);
    if (mounted) {
      setState(() {
        _results = res;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0E17),
          elevation: 0,
          title: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'ابحث عن فيلم أو أنمي أو مسلسل...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none),
            onSubmitted: _search,
          ),
        ),
        body: _isSearching
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.6, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final item = _results[i];
                  final poster = StreamService.extractPoster(item);
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Map<String, dynamic>> _completed = [];

  @override
  void initState() {
    super.initState();
    LocalStorageService.getList('downloaded_works_list').then((list) {
      if (mounted) setState(() => _completed = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E17),
        appBar: AppBar(title: const Text('التنزيلات'), backgroundColor: const Color(0xFF0A0E17), elevation: 0),
        body: _completed.isEmpty
            ? const Center(child: Text('لا توجد ملفات مكتملة', style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                itemCount: _completed.length,
                itemBuilder: (ctx, i) {
                  final item = _completed[i];
                  return ListTile(
                    leading: const Icon(Icons.play_circle_fill, color: Color(0xFFE50914)),
                    title: Text(item['title'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text(item['size'] ?? '', style: const TextStyle(color: Colors.white38)),
                  );
                },
              ),
      ),
    );
  }
}
