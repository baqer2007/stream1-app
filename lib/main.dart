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

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 40, String idField = 'nb'}) async {
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
  http.Client? client;
  bool isCancelled = false;

  ActiveDownload({
    required this.id,
    required this.title,
    required this.url,
    required this.poster,
    this.progress = 0.0,
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
      final safeName = targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final filePath = '$basePath/$safeName.mp4';
      final file = File(filePath);

      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = file.lengthSync();
      }

      await LocalStorageService.appendItem('downloaded_works_list', {
        'nb': targetId,
        'title': title,
        'path': filePath,
        'size': 'قيد التنزيل',
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
      final totalBytes = (response.contentLength ?? 0) + downloadedBytes;

      final sink = file.openWrite(mode: FileMode.append);

      await response.stream.listen((chunk) {
        if (download.isCancelled) {
          sink.close();
          return;
        }
        downloadedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          download.progress = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
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

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  bool isDark = true;

  void toggleTheme() {
    isDark = !isDark;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OnebrTvApp());
}

class OnebrTvApp extends StatelessWidget {
  const OnebrTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'ONEBR TV',
          theme: state.isDark
              ? ThemeData.dark().copyWith(
                  scaffoldBackgroundColor: const Color(0xFF07090E),
                  primaryColor: const Color(0xFFE50914),
                  cardColor: const Color(0xFF111726),
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFFE50914),
                    surface: Color(0xFF111726),
                    secondary: Color(0xFF00F0FF),
                  ),
                )
              : ThemeData.light().copyWith(
                  scaffoldBackgroundColor: const Color(0xFFF1F5F9),
                  primaryColor: const Color(0xFFE50914),
                  cardColor: Colors.white,
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFFE50914),
                    surface: Colors.white,
                    secondary: Color(0xFF0284C7),
                  ),
                ),
          home: const MainHomeScreen(),
        );
      },
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  bool _isSearchExpanded = false;
  List<dynamic> _activeGrid = [];
  final Set<String> _loadedIds = {};
  List<Map<String, dynamic>> _continueWatchingList = [];

  int _page = 0;
  int _tabIndex = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _activeTitle = 'أحدث الإضافات';
  Map<String, dynamic>? _selectedCategory;

  // معرفات التصنيفات الحقيقية المستخرجة من شبكة cee.buzz
  final List<Map<String, dynamic>> _officialCategories = [
    {'id': 0, 'ar': 'الكل'},
    {'id': 84, 'ar': 'أكشن'},
    {'id': 62, 'ar': 'دراما'},
    {'id': 59, 'ar': 'كوميديا'},
    {'id': 70, 'ar': 'رعب'},
    {'id': 56, 'ar': 'مغامرة'},
    {'id': 60, 'ar': 'جريمة'},
    {'id': 78, 'ar': 'خيال علمي'},
    {'id': 77, 'ar': 'رومانسي'},
    {'id': 57, 'ar': 'رسوم متحركة'},
    {'id': 65, 'ar': 'عائلي'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _tabIndex = _tabController.index;
          _selectedCategory = null;
          _activeTitle = _tabIndex == 1 ? 'الأفلام' : (_tabIndex == 2 ? 'المسلسلات' : 'أحدث الإضافات');
        });
        _fetchContent(reset: true);
      }
    });

    _fetchContent(reset: true);
    _loadContinueWatching();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
        if (!_isLoadingMore && _hasMore) {
          _fetchContent(reset: false);
        }
      }
    });
  }

  /// التمييز القاطع المكتشف من السيرفر
  static bool checkIsSeries(Map<String, dynamic> item) {
    if (item['is_series_fixed'] == true) return true;
    if (item['is_series_fixed'] == false) return false;

    // فحص حقل videoKind المباشر من الرابط
    final kind = item['kind']?.toString();
    final season = item['season']?.toString();
    final rootSeries = item['rootSeries']?.toString();

    if (season == '0' || rootSeries == '0') return false;
    if (kind == '1' && season != null && season != '0') return true;

    final en = (item['en_title'] ?? '').toString().toLowerCase();
    final ar = (item['title'] ?? item['ar_title'] ?? '').toString().toLowerCase();
    if (en.contains('movie') || en.contains('film') || ar.contains('فيلم')) return false;
    if (en.contains('season') || ar.contains('الموسم') || ar.contains('مسلسل')) return true;

    return false;
  }

  Future<void> _fetchContent({bool reset = false}) async {
    if (reset) {
      _page = 0;
      _hasMore = true;
      _loadedIds.clear();
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      List<dynamic> rawList = [];

      if (_selectedCategory != null && _selectedCategory!['id'] != 0) {
        rawList = await StreamService.fetchByCategory(_selectedCategory!['id'], page: _page);
      } else if (_tabIndex == 0) {
        final res = await Future.wait([
          StreamService.fetchFeed(isSeries: false, page: _page, perPage: 16),
          StreamService.fetchFeed(isSeries: true, page: _page, perPage: 16),
        ]);
        rawList = [...res[0], ...res[1]]..shuffle();
      } else if (_tabIndex == 1) {
        rawList = await StreamService.fetchFeed(isSeries: false, page: _page, perPage: 32);
      } else {
        rawList = await StreamService.fetchFeed(isSeries: true, page: _page, perPage: 32);
      }

      final List<dynamic> uniqueItems = [];
      for (var item in rawList) {
        final id = (item['nb'] ?? item['id'])?.toString();
        if (id != null && !_loadedIds.contains(id)) {
          if (_tabIndex == 1 && checkIsSeries(item)) continue;
          if (_tabIndex == 2 && !checkIsSeries(item)) continue;

          _loadedIds.add(id);
          uniqueItems.add(item);
        }
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _activeGrid = uniqueItems;
          } else {
            _activeGrid.addAll(uniqueItems);
          }
          if (uniqueItems.isEmpty) _hasMore = false;
          _page++;
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  void _search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    setState(() => _isLoadingInitial = true);
    final results = await StreamService.searchContent(clean);

    _loadedIds.clear();
    final List<dynamic> uniqueList = [];
    for (var item in results) {
      final id = (item['nb'] ?? item['id'])?.toString();
      if (id != null && !_loadedIds.contains(id)) {
        _loadedIds.add(id);
        uniqueList.add(item);
      }
    }

    if (mounted) {
      setState(() {
        _activeGrid = uniqueList;
        _isLoadingInitial = false;
        _hasMore = false;
        _activeTitle = 'نتائج البحث: $clean';
      });
    }
  }

  void _loadContinueWatching() async {
    final list = await LocalStorageService.getList('continue_watching_list');
    if (mounted) setState(() => _continueWatchingList = list);
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)))
        .then((_) => _loadContinueWatching());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Drawer(
          backgroundColor: Theme.of(context).cardColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.only(top: 48, bottom: 24, right: 20, left: 20),
                color: const Color(0xFF1E293B),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    SizedBox(height: 6),
                    Text('منصة البث المباشر', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                title: const Text('التنزيلات', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                title: const Text('المفضلة', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.watch_later_rounded, color: Color(0xFF00F0FF)),
                title: const Text('المشاهدة لاحقاً', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen()));
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('المظهر الداكن', style: TextStyle(fontWeight: FontWeight.bold)),
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text('التصنيفات الرسمية', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              ..._officialCategories.map((cat) => ListTile(
                    dense: true,
                    title: Text(cat['ar']),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedCategory = cat;
                        _activeTitle = cat['id'] == 0 ? 'أحدث الإضافات' : 'تصنيف: ${cat['ar']}';
                      });
                      _fetchContent(reset: true);
                    },
                  )),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: _isSearchExpanded
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onSubmitted: _search,
                    decoration: const InputDecoration(
                      hintText: 'بحث عن عمل...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                )
              : const Text('ONEBR TV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE50914))),
          actions: [
            IconButton(
              icon: Icon(_isSearchExpanded ? Icons.close : Icons.search),
              onPressed: () {
                setState(() => _isSearchExpanded = !_isSearchExpanded);
                if (!_isSearchExpanded) _fetchContent(reset: true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(16),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(text: 'الكل'),
                  Tab(text: 'الأفلام'),
                  Tab(text: 'المسلسلات'),
                ],
              ),
            ),
          ),
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: () async => _fetchContent(reset: true),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_continueWatchingList.isNotEmpty && !_isSearchExpanded)
                        _buildContinueWatchingShelf(),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Text(_activeTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),

                      _buildGrid(_activeGrid),

                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
                        ),
                      const SizedBox(height: 36),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('متابعة المشاهدة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('continue_watching_list');
                  setState(() => _continueWatchingList.clear());
                },
                child: const Text('مسح', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _continueWatchingList.length,
            itemBuilder: (ctx, i) {
              final item = _continueWatchingList[i];
              final poster = StreamService.extractPoster(item);
              final title = item['ar_title'] ?? item['en_title'] ?? item['title'] ?? '';

              return Container(
                width: 155,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      InkWell(
                        onTap: () => _openDetails(item),
                        child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover, width: double.infinity, height: double.infinity) : Container(color: Colors.grey.shade900),
                      ),
                      Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]))),
                      Positioned(
                        bottom: 8, right: 10, left: 10,
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
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
    final width = MediaQuery.of(context).size.width;
    final count = width > 900 ? 6 : (width > 600 ? 5 : (width > 380 ? 4 : 3));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          final title = item['ar_title'] ?? item['en_title'] ?? item['title'] ?? '';
          final poster = StreamService.extractPoster(item);
          final score = (item['stars'] ?? '7.5').toString();
          final isSeries = checkIsSeries(item);

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                            child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSeries ? const Color(0xFF00F0FF) : const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isSeries ? 'مسلسل' : 'فيلم',
                              style: const TextStyle(fontSize: 8.5, color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(score, style: const TextStyle(fontSize: 9, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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

class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunching = false;
  bool _isLoadingEpisodes = false;
  bool _isFav = false;
  List<dynamic> _episodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = _MainHomeScreenState.checkIsSeries(widget.media);
    _checkFav();
    LocalStorageService.appendItem('continue_watching_list', widget.media);

    if (_isSeries) {
      _loadEpisodes();
    }
  }

  void _checkFav() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final list = await LocalStorageService.getList('user_favorites_list');
    final isFav = list.any((item) => (item['nb'] ?? item['id'])?.toString() == id);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _loadEpisodes() async {
    setState(() => _isLoadingEpisodes = true);
    final seriesId = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final eps = await StreamService.getSeriesEpisodes(seriesId);
    if (mounted) {
      setState(() {
        _episodes = eps;
        _isLoadingEpisodes = false;
      });
    }
  }

  void _play(Map<String, dynamic>? episodeData) async {
    setState(() => _isLaunching = true);

    final targetId = episodeData != null
        ? (episodeData['nb'] ?? episodeData['id']).toString()
        : (widget.media['nb'] ?? widget.media['id']).toString();

    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? widget.media['title'] ?? '';
    final fullTitle = episodeData != null ? '$title - حلقة ${episodeData['episodeNumber'] ?? ''}' : title;

    final source = await StreamService.getVideoSource(targetId);
    final subUrl = await StreamService.getArabicSubtitleUrl(targetId);

    setState(() => _isLaunching = false);

    if (source != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: fullTitle,
            videoUrl: source['video_url'],
            subtitleUrl: subUrl,
            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل رابط التشغيل')),
      );
    }
  }

  void _triggerDownload() async {
    final targetId = (widget.media['nb'] ?? widget.media['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? 'Video';

    final data = await StreamService.getVideoSource(targetId);
    if (data != null) {
      final qualities = List<Map<String, dynamic>>.from(data['qualities'] ?? []);
      final dlUrl = qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first)['url'];

      DownloadManager.instance.startDownload(
        targetId: targetId,
        title: title,
        url: dlUrl,
        poster: StreamService.extractPoster(widget.media),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بدأ التنزيل: $title')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? widget.media['title'] ?? '';
    final poster = StreamService.extractPoster(widget.media);
    final story = widget.media['ar_content'] ?? widget.media['en_content'] ?? widget.media['content'] ?? '';
    final score = (widget.media['stars'] ?? '7.5').toString();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
              onPressed: () async {
                final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
                final list = await LocalStorageService.getList('user_favorites_list');
                final exists = list.any((item) => (item['nb'] ?? item['id'])?.toString() == id);
                if (exists) {
                  await LocalStorageService.removeItem('user_favorites_list', id);
                  setState(() => _isFav = false);
                } else {
                  await LocalStorageService.appendItem('user_favorites_list', widget.media);
                  setState(() => _isFav = true);
                }
              },
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
                    borderRadius: BorderRadius.circular(14),
                    child: poster.isNotEmpty ? Image.network(poster, width: 110, height: 160, fit: BoxFit.cover) : Container(width: 110, height: 160, color: Colors.grey.shade900),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(score, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(_isSeries ? 'مسلسل' : 'فيلم', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _triggerDownload,
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('تنزيل', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _isLaunching ? null : () => _play(_isSeries && _episodes.isNotEmpty ? _episodes.first : null),
                  child: _isLaunching
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة الفيلم الآن',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                ),
              ),

              if (story.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('القصة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(story, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
              ],

              // لن تظهر الحلقات إلا إذا كان العمل مسلسلاً فعلياً وقائمة الحلقات غير فارغة
              if (_isSeries && _episodes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('الحلقات (${_episodes.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final ep = _episodes[i];
                          final epNum = ep['episodeNumber'] ?? (i + 1);
                          return InkWell(
                            onTap: _isLaunching ? null : () => _play(ep),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('حلقة $epNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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

class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final String subtitleUrl;
  final List<Map<String, dynamic>> qualities;
  final bool isLocalFile;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    this.subtitleUrl = '',
    required this.qualities,
    this.isLocalFile = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;

  String _currentStreamUrl = '';
  String _activeQualityName = 'تلقائي';

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18.0;
  Color _subtitleTextColor = Colors.white;
  Color _subtitleBgColor = Colors.black54;
  double _subtitleBottomPadding = 60.0;
  List<Subtitle> _parsedSubtitles = [];
  String _activeSubtitleText = '';

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.videoUrl;
    _initVideo(_currentStreamUrl);
    if (!widget.isLocalFile && widget.subtitleUrl.isNotEmpty) {
      _fetchSubs(widget.subtitleUrl);
    }
  }

  void _fetchSubs(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() => _parsedSubtitles = _parseSubtitles(utf8.decode(res.bodyBytes, allowMalformed: true)));
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

  void _initVideo(String url) async {
    await _controller?.dispose();
    if (mounted) setState(() => _isReady = false);

    _controller = widget.isLocalFile
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: StreamService.stealthHeaders,
          );

    await _controller!.initialize();
    _controller!.play();

    _controller!.addListener(() {
      if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty && _controller!.value.isInitialized) {
        final pos = _controller!.value.position;
        final sub = _parsedSubtitles.firstWhere(
          (s) => pos >= s.start && pos <= s.end,
          orElse: () => Subtitle(index: -1, start: Duration.zero, end: Duration.zero, text: ''),
        );
        if (sub.text != _activeSubtitleText && mounted) {
          setState(() => _activeSubtitleText = sub.text);
        }
      }
      if (mounted) setState(() {});
    });

    _startHideControlsTimer();
    if (mounted) setState(() => _isReady = true);
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F0FF)),
              title: const Text('تلقائي'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _activeQualityName = 'تلقائي');
              },
            ),
            const Divider(color: Colors.white12),
            ...widget.qualities.map((q) {
              final res = q['resolution'] ?? '720p';
              final url = q['url'] ?? '';

              return ListTile(
                leading: const Icon(Icons.hd_outlined, color: Colors.white70),
                title: Text(res),
                onTap: () {
                  Navigator.pop(context);
                  if (url != _currentStreamUrl && url.isNotEmpty) {
                    setState(() {
                      _activeQualityName = res;
                      _currentStreamUrl = url;
                    });
                    _initVideo(url);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openSubtitleSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إعدادات الترجمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                SwitchListTile(
                  title: const Text('تفعيل الترجمة', style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: _subtitlesEnabled,
                  onChanged: (val) {
                    setSheet(() => _subtitlesEnabled = val);
                    setState(() => _subtitlesEnabled = val);
                  },
                ),
                Text('الموضع العمودي: ${_subtitleBottomPadding.toInt()}px', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Slider(
                  value: _subtitleBottomPadding,
                  min: 10,
                  max: 350,
                  divisions: 34,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (val) {
                    setSheet(() => _subtitleBottomPadding = val);
                    setState(() => _subtitleBottomPadding = val);
                  },
                ),
                Text('حجم الخط: ${_subtitleFontSize.toInt()}px', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Slider(
                  value: _subtitleFontSize,
                  min: 14,
                  max: 34,
                  divisions: 10,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (val) {
                    setSheet(() => _subtitleFontSize = val);
                    setState(() => _subtitleFontSize = val);
                  },
                ),
                Row(
                  children: [
                    const Text('اللون: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    _colorOption(Colors.white, () {
                      setSheet(() => _subtitleTextColor = Colors.white);
                      setState(() => _subtitleTextColor = Colors.white);
                    }),
                    _colorOption(const Color(0xFFFDE047), () {
                      setSheet(() => _subtitleTextColor = const Color(0xFFFDE047));
                      setState(() => _subtitleTextColor = const Color(0xFFFDE047));
                    }),
                    _colorOption(const Color(0xFF00F0FF), () {
                      setSheet(() => _subtitleTextColor = const Color(0xFF00F0FF));
                      setState(() => _subtitleTextColor = const Color(0xFF00F0FF));
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الخلفية: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    TextButton(
                      onPressed: () {
                        setSheet(() => _subtitleBgColor = Colors.transparent);
                        setState(() => _subtitleBgColor = Colors.transparent);
                      },
                      child: const Text('شفاف'),
                    ),
                    TextButton(
                      onPressed: () {
                        setSheet(() => _subtitleBgColor = Colors.black54);
                        setState(() => _subtitleBgColor = Colors.black54);
                      },
                      child: const Text('شبه شفاف'),
                    ),
                    TextButton(
                      onPressed: () {
                        setSheet(() => _subtitleBgColor = Colors.black);
                        setState(() => _subtitleBgColor = Colors.black);
                      },
                      child: const Text('معتم'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorOption(Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;

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
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
              ),

              if (_subtitlesEnabled && _activeSubtitleText.isNotEmpty)
                Positioned(
                  bottom: _subtitleBottomPadding,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: _subtitleBgColor, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          _activeSubtitleText,
                          style: TextStyle(color: _subtitleTextColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),

              if (_showControls && !_isLocked) ...[
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
                        onPressed: _openSubtitleSettings,
                      ),
                      IconButton(
                        icon: const Icon(Icons.high_quality_rounded, color: Colors.white),
                        onPressed: _showQualitySheet,
                      ),
                      IconButton(
                        icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                        onPressed: () => setState(() => _isLocked = true),
                      ),
                    ],
                  ),
                ),

                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                        onPressed: () {
                          if (_controller != null) {
                            final p = _controller!.value.position - const Duration(seconds: 10);
                            _controller!.seekTo(p < Duration.zero ? Duration.zero : p);
                          }
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 52,
                        icon: Icon(
                          _controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          if (_controller != null) {
                            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                            setState(() {});
                            _startHideControlsTimer();
                          }
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                        onPressed: () {
                          if (_controller != null) {
                            final p = _controller!.value.position + const Duration(seconds: 10);
                            _controller!.seekTo(p);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                if (_controller != null && _controller!.value.isInitialized)
                  Positioned(
                    bottom: 10,
                    left: 14,
                    right: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: _controller!.value.position.inMilliseconds.toDouble().clamp(0.0, _controller!.value.duration.inMilliseconds.toDouble()),
                          min: 0.0,
                          max: _controller!.value.duration.inMilliseconds.toDouble(),
                          activeColor: const Color(0xFFE50914),
                          inactiveColor: Colors.white24,
                          onChanged: (v) {
                            _controller!.seekTo(Duration(milliseconds: v.toInt()));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            IconButton(
                              icon: Icon(
                                orientation == Orientation.portrait ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                if (orientation == Orientation.portrait) {
                                  SystemChrome.setPreferredOrientations([
                                    DeviceOrientation.landscapeLeft,
                                    DeviceOrientation.landscapeRight,
                                  ]);
                                } else {
                                  SystemChrome.setPreferredOrientations([
                                    DeviceOrientation.portraitUp,
                                  ]);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],

              if (_isLocked)
                Positioned(
                  top: 14,
                  right: 14,
                  child: IconButton(
                    icon: const Icon(Icons.lock_rounded, color: Color(0xFFE50914), size: 28),
                    onPressed: () => setState(() => _isLocked = false),
                  ),
                ),
            ],
          ),
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
    _loadCompleted();
  }

  void _loadCompleted() async {
    final list = await LocalStorageService.getList('downloaded_works_list');
    if (mounted) setState(() => _completed = list);
  }

  void _deleteCompleted(int index) async {
    final item = _completed[index];
    final path = item['path'];
    if (path != null) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
    await LocalStorageService.removeItem('downloaded_works_list', item['nb'].toString());
    _loadCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التنزيلات'), backgroundColor: Colors.transparent, elevation: 0),
        body: _completed.isEmpty
            ? const Center(child: Text('لا توجد ملفات مكتملة'))
            : ListView.builder(
                itemCount: _completed.length,
                itemBuilder: (ctx, i) {
                  final item = _completed[i];
                  return ListTile(
                    leading: const Icon(Icons.play_circle_fill, color: Color(0xFF10B981)),
                    title: Text(item['title'] ?? ''),
                    subtitle: Text(item['size'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _deleteCompleted(i),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          mediaId: item['nb'],
                          title: item['title'],
                          videoUrl: item['path'],
                          qualities: const [],
                          isLocalFile: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _favorites = [];

  @override
  void initState() {
    super.initState();
    LocalStorageService.getList('user_favorites_list').then((list) => setState(() => _favorites = list));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المفضلة'), backgroundColor: Colors.transparent, elevation: 0),
        body: _favorites.isEmpty
            ? const Center(child: Text('القائمة فارغة'))
            : ListView.builder(
                itemCount: _favorites.length,
                itemBuilder: (ctx, i) {
                  final item = _favorites[i];
                  return ListTile(
                    leading: const Icon(Icons.movie, color: Color(0xFFE50914)),
                    title: Text(item['ar_title'] ?? item['en_title'] ?? item['title'] ?? ''),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                  );
                },
              ),
      ),
    );
  }
}

class WatchLaterScreen extends StatefulWidget {
  const WatchLaterScreen({super.key});

  @override
  State<WatchLaterScreen> createState() => _WatchLaterScreenState();
}

class _WatchLaterScreenState extends State<WatchLaterScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    LocalStorageService.getList('watch_later_items').then((list) => setState(() => _items = list));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المشاهدة لاحقاً'), backgroundColor: Colors.transparent, elevation: 0),
        body: _items.isEmpty
            ? const Center(child: Text('القائمة فارغة'))
            : ListView.builder(
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  return ListTile(
                    leading: const Icon(Icons.play_arrow, color: Color(0xFF00F0FF)),
                    title: Text(item['ar_title'] ?? item['en_title'] ?? item['title'] ?? ''),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                  );
                },
              ),
      ),
    );
  }
}
