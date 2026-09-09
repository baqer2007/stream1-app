import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

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

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 30, String idField = 'nb'}) async {
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

      if (!download.isCancelled && file.existsSync() && file.lengthSync() > 1024 * 512) {
        final fileSizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        await LocalStorageService.appendItem('downloaded_works_list', {
          'nb': targetId,
          'title': title,
          'path': filePath,
          'size': '$fileSizeMb MB',
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
  String lang = 'ar';
  bool isLoggedIn = false;
  bool isAdmin = true;
  String username = '';
  String deviceId = '';

  bool isFamilyMode = false;
  List<String> profiles = ['الرئيسي', 'أنمي', 'أطفال'];
  String currentProfile = 'الرئيسي';

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('app_device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'usr_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('app_device_id', deviceId);
    }
    currentProfile = prefs.getString('active_profile') ?? 'الرئيسي';
    isFamilyMode = prefs.getBool('app_family_mode') ?? false;
    StreamService.sendHeartbeat(deviceId);
  }

  Future<void> toggleFamilyMode(bool val) async {
    isFamilyMode = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_family_mode', val);
    notifyListeners();
  }

  void switchProfile(String profileName) async {
    currentProfile = profileName;
    if (profileName == 'أطفال') isFamilyMode = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_profile', profileName);
    notifyListeners();
  }

  void toggleTheme() {
    isDark = !isDark;
    notifyListeners();
  }

  String tr(String arKey, String enKey) => lang == 'ar' ? arKey : enKey;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.initSession();
  StreamService.startRelayWorker();
  runApp(const OnebrTvApp());
}

class OnebrTvApp extends StatefulWidget {
  const OnebrTvApp({super.key});

  @override
  State<OnebrTvApp> createState() => _OnebrTvAppState();
}

class _OnebrTvAppState extends State<OnebrTvApp> {
  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
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
  final PageController _bannerController = PageController();
  late TabController _tabController;

  bool _isSearchExpanded = false;
  List<dynamic> _bannerList = [];
  List<dynamic> _activeGrid = [];
  final Set<String> _loadedIds = {};
  List<Map<String, dynamic>> _continueWatchingList = [];
  List<String> _recentSearches = [];

  int _currentBannerPage = 0;
  Timer? _bannerTimer;

  int _page = 0;
  int _tabIndex = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _activeTitle = 'أحدث الأعمال المضافة';
  Map<String, dynamic>? _selectedGenre;

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'ar': 'الكل', 'en': 'All'},
    {'id': 'anime', 'ar': 'أنمي', 'query': 'anime'},
    {'id': 'action', 'ar': 'أكشن', 'query': 'action'},
    {'id': 'adventure', 'ar': 'مغامرة', 'query': 'adventure'},
    {'id': 'comedy', 'ar': 'كوميديا', 'query': 'comedy'},
    {'id': 'crime', 'ar': 'جريمة', 'query': 'crime'},
    {'id': 'drama', 'ar': 'دراما', 'query': 'drama'},
    {'id': 'horror', 'ar': 'رعب', 'query': 'horror'},
    {'id': 'scifi', 'ar': 'خيال علمي', 'query': 'sci-fi'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _tabIndex = _tabController.index;
          _selectedGenre = null;
          _activeTitle = 'أحدث الأعمال المضافة';
        });
        _fetchContent(reset: true);
      }
    });

    _fetchContent(reset: true);
    _loadContinueWatching();
    _loadSearchHistory();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _fetchContent(reset: false);
        }
      }
    });

    _startBannerTimer();
  }

  List<dynamic> _filterStrictFamily(List<dynamic> list) {
    if (!AppState.instance.isFamilyMode) return list;

    final blockedTerms = [
      'overflow', 'ecchi', 'hentai', 'erotic', 'sensual', 'sex', 'nude',
      'حمام', 'إباحي', 'جنسي', 'عري', 'إيتشي', 'شذوذ', 'adult', 'lust'
    ];

    return list.where((item) {
      final title = (item['ar_title'] ?? item['en_title'] ?? item['title'] ?? '').toString().toLowerCase();
      final overview = (item['ar_content'] ?? item['en_content'] ?? item['content'] ?? '').toString().toLowerCase();

      for (var word in blockedTerms) {
        if (title.contains(word) || overview.contains(word)) return false;
      }
      return true;
    }).toList();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_bannerList.isNotEmpty && _bannerController.hasClients) {
        final next = (_currentBannerPage + 1) % (_bannerList.length.clamp(0, 6));
        _bannerController.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
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
      List<dynamic> results = [];
      if (_selectedGenre != null && _selectedGenre!['id'] != 'all') {
        final q = _selectedGenre!['query'] ?? _selectedGenre!['ar'];
        final res = await Future.wait([
          StreamService.searchContent(q, level: 0),
          StreamService.searchContent(q, level: 1),
        ]);
        results = [...res[0], ...res[1]];
      } else if (_tabIndex == 0) {
        final res = await Future.wait([
          StreamService.fetchHomeFeed(level: 0, page: _page, perPage: 16),
          StreamService.fetchHomeFeed(level: 1, page: _page, perPage: 16),
        ]);
        results = [...res[0], ...res[1]];
      } else if (_tabIndex == 1) {
        results = await StreamService.fetchHomeFeed(level: 0, page: _page, perPage: 30);
      } else {
        results = await StreamService.fetchHomeFeed(level: 1, page: _page, perPage: 30);
      }

      final filtered = _filterStrictFamily(results);
      final List<dynamic> uniqueNewItems = [];

      for (var item in filtered) {
        final id = (item['nb'] ?? item['id'])?.toString();
        if (id != null && !_loadedIds.contains(id)) {
          _loadedIds.add(id);
          uniqueNewItems.add(item);
        }
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _activeGrid = uniqueNewItems;
            if (_bannerList.isEmpty && uniqueNewItems.isNotEmpty) {
              _bannerList = uniqueNewItems.take(6).toList();
            }
          } else {
            _activeGrid.addAll(uniqueNewItems);
          }
          if (uniqueNewItems.isEmpty) _hasMore = false;
          _page++;
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  void _filterGenre(Map<String, dynamic> genre) {
    _selectedGenre = genre;
    setState(() {
      _activeTitle = genre['id'] == 'all'
          ? 'أحدث الأعمال المضافة'
          : 'تصنيف: ${genre['ar']}';
    });
    _fetchContent(reset: true);
  }

  void _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('search_history') ?? [];
    if (mounted) setState(() => _recentSearches = raw);
  }

  void _search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _recentSearches.remove(clean);
    _recentSearches.insert(0, clean);
    prefs.setStringList('search_history', _recentSearches);

    setState(() => _isLoadingInitial = true);

    final res = await Future.wait([
      StreamService.searchContent(clean, level: 0),
      StreamService.searchContent(clean, level: 1),
    ]);

    _loadedIds.clear();
    final all = _filterStrictFamily([...res[0], ...res[1]]);
    final List<dynamic> uniqueList = [];
    for (var item in all) {
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
    final p = AppState.instance.currentProfile;
    final list = await LocalStorageService.getList('continue_watching_list_$p');
    if (mounted) setState(() => _continueWatchingList = list);
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)))
        .then((_) => _loadContinueWatching());
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
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
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(28))),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.only(top: 48, bottom: 24, right: 20, left: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFF1E293B)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('الحساب: ${app.currentProfile}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('الوضع العائلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                value: app.isFamilyMode,
                onChanged: (val) {
                  app.toggleFamilyMode(val);
                  _fetchContent(reset: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                title: const Text('التنزيلات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                title: const Text('المفضلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.watch_later_rounded, color: Color(0xFF00F0FF)),
                title: const Text('المشاهدة لاحقاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen()));
                },
              ),
              if (app.isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber),
                  title: const Text('لوحة الإدارة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                  },
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('المظهر الداكن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text('التصنيفات', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              ..._genres.map((g) => ListTile(
                    dense: true,
                    title: Text(g['ar'], style: const TextStyle(fontSize: 13)),
                    onTap: () {
                      Navigator.pop(context);
                      _filterGenre(g);
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
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onSubmitted: _search,
                    decoration: const InputDecoration(
                      hintText: 'بحث...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                )
              : const Text('ONEBR TV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFE50914))),
          actions: [
            IconButton(
              icon: Icon(_isSearchExpanded ? Icons.close : Icons.search, color: const Color(0xFF00F0FF)),
              onPressed: () {
                setState(() => _isSearchExpanded = !_isSearchExpanded);
                if (!_isSearchExpanded) _fetchContent(reset: true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                      if (_tabIndex == 0 && _selectedGenre == null && _bannerList.isNotEmpty && !_isSearchExpanded)
                        _buildHeroBanner(),

                      if (_continueWatchingList.isNotEmpty && !_isSearchExpanded)
                        _buildContinueWatchingShelf(),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Text(_activeTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
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

  Widget _buildHeroBanner() {
    final width = MediaQuery.of(context).size.width;
    final height = (width * 0.55).clamp(210.0, 310.0);

    return Container(
      margin: const EdgeInsets.all(16),
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            PageView.builder(
              controller: _bannerController,
              itemCount: _bannerList.length,
              onPageChanged: (i) => setState(() => _currentBannerPage = i),
              itemBuilder: (ctx, i) {
                final item = _bannerList[i];
                final poster = StreamService.extractPoster(item);
                final title = item['ar_title'] ?? item['en_title'] ?? item['title'] ?? '';

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xEE07090E), Colors.transparent],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      left: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: () => _openDetails(item),
                            child: const Text('عرض', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
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
              const Text('متابعة المشاهدة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00F0FF))),
              TextButton(
                onPressed: () async {
                  final p = AppState.instance.currentProfile;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('continue_watching_list_$p');
                  setState(() => _continueWatchingList.clear());
                },
                child: const Text('مسح السجل', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
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
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
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
          final isSeries = item['kind']?.toString() == '1' || item['isSeries'] == true;

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(isSeries ? 'مسلسل' : 'فيلم', style: const TextStyle(fontSize: 8.5, color: Colors.black, fontWeight: FontWeight.bold)),
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
  bool _isWatchLater = false;

  List<dynamic> _episodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media['kind']?.toString() == '1' || widget.media['isSeries'] == true;
    _checkSavedStates();
    _saveHistory();
    if (_isSeries) _loadEpisodes();
  }

  void _checkSavedStates() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final isFav = await FavoritesService.isFavorited(id);
    final p = AppState.instance.currentProfile;
    final wlList = await LocalStorageService.getList('watch_later_items_$p');
    if (mounted) {
      setState(() {
        _isFav = isFav;
        _isWatchLater = wlList.any((x) => (x['nb'] ?? x['id'])?.toString() == id);
      });
    }
  }

  void _toggleWatchLater() async {
    final p = AppState.instance.currentProfile;
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    if (_isWatchLater) {
      await LocalStorageService.removeItem('watch_later_items_$p', id);
    } else {
      await LocalStorageService.appendItem('watch_later_items_$p', widget.media);
    }
    if (mounted) setState(() => _isWatchLater = !_isWatchLater);
  }

  void _saveHistory() async {
    final p = AppState.instance.currentProfile;
    await LocalStorageService.appendItem('continue_watching_list_$p', widget.media);
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
    final fullTitle = episodeData != null ? '$title - الحلقة ${episodeData['episodeNumber'] ?? ''}' : title;

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
    final subTitle = widget.media['en_title'] ?? '';
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
              icon: Icon(_isWatchLater ? Icons.watch_later_rounded : Icons.watch_later_outlined, color: const Color(0xFF00F0FF)),
              onPressed: _toggleWatchLater,
            ),
            IconButton(
              icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
              onPressed: () async {
                final state = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
                setState(() => _isFav = state);
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
                    borderRadius: BorderRadius.circular(16),
                    child: poster.isNotEmpty ? Image.network(poster, width: 110, height: 160, fit: BoxFit.cover) : Container(width: 110, height: 160, color: Colors.grey.shade900),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        if (subTitle != title && subTitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subTitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(score, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 12),
                            Text(_isSeries ? 'مسلسل' : 'فيلم', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
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
                  onPressed: _isLaunching ? null : () => _play(_episodes.isNotEmpty ? _episodes.first : null),
                  child: _isLaunching
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة الآن',
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

              if (_isSeries) ...[
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
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
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

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isReady = false;
  bool _isLocked = false;

  String _currentStreamUrl = '';
  String _activeQualityName = 'تلقائي';
  bool _isAutoBitrate = true;

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18.0;
  Color _subtitleTextColor = Colors.white;
  Color _subtitleBgColor = Colors.black54;
  double _subtitleBottomPadding = 48.0;
  List<Subtitle> _parsedSubtitles = [];
  String _activeSubtitleText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _chewieController?.dispose();
    await _videoPlayerController?.dispose();

    if (mounted) setState(() => _isReady = false);

    _videoPlayerController = widget.isLocalFile
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: StreamService.stealthHeaders,
          );

    await _videoPlayerController!.initialize();

    _videoPlayerController!.addListener(() {
      if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty && _videoPlayerController!.value.isInitialized) {
        final pos = _videoPlayerController!.value.position;
        final sub = _parsedSubtitles.firstWhere(
          (s) => pos >= s.start && pos <= s.end,
          orElse: () => Subtitle(index: -1, start: Duration.zero, end: Duration.zero, text: ''),
        );
        if (sub.text != _activeSubtitleText && mounted) {
          setState(() => _activeSubtitleText = sub.text);
        }
      }
    });

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: false,
      allowFullScreen: true,
      deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
      deviceOrientationsOnEnterFullScreen: [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      overlay: ValueListenableBuilder(
        valueListenable: _videoPlayerController!,
        builder: (ctx, VideoPlayerValue val, child) {
          if (!_subtitlesEnabled || _activeSubtitleText.isEmpty) return const SizedBox();
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: _subtitleBottomPadding, left: 24, right: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _subtitleBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _activeSubtitleText,
                  style: TextStyle(
                    color: _subtitleTextColor,
                    fontSize: _subtitleFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F0FF)),
              title: const Text('تلقائي'),
              trailing: _isAutoBitrate ? const Icon(Icons.check, color: Color(0xFF00F0FF)) : null,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isAutoBitrate = true;
                  _activeQualityName = 'تلقائي';
                });
              },
            ),
            const Divider(color: Colors.white12),
            ...widget.qualities.map((q) {
              final res = q['resolution'] ?? '720p';
              final url = q['url'] ?? '';
              final isCurrent = url == _currentStreamUrl && !_isAutoBitrate;

              return ListTile(
                leading: const Icon(Icons.hd_outlined, color: Colors.white70),
                title: Text(res, style: TextStyle(color: isCurrent ? const Color(0xFF00F0FF) : Colors.white)),
                trailing: isCurrent ? const Icon(Icons.check, color: Color(0xFF00F0FF)) : null,
                onTap: () {
                  Navigator.pop(context);
                  if (url != _currentStreamUrl && url.isNotEmpty) {
                    setState(() {
                      _isAutoBitrate = false;
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
              Text('الموضع (الارتفاع): ${_subtitleBottomPadding.toInt()}px', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: _subtitleBottomPadding, min: 10, max: 140, divisions: 13,
                activeColor: const Color(0xFF00F0FF),
                onChanged: (val) {
                  setSheet(() => _subtitleBottomPadding = val);
                  setState(() => _subtitleBottomPadding = val);
                },
              ),
              Text('الحجم: ${_subtitleFontSize.toInt()}px', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: _subtitleFontSize, min: 14, max: 32, divisions: 9,
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
    );
  }

  Widget _colorOption(Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 22, height: 22,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          fit: StackFit.expand,
          children: [
            Center(
              child: (_isReady && _chewieController != null)
                  ? Chewie(controller: _chewieController!)
                  : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
            ),

            if (!_isLocked)
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.high_quality_rounded, color: Color(0xFF00F0FF)),
                          onPressed: _showQualitySheet,
                        ),
                        IconButton(
                          icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
                          onPressed: _openSubtitleSettings,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                          onPressed: () => setState(() => _isLocked = true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

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
    final active = DownloadManager.instance.activeDownloads.values.toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التنزيلات'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              const Text('جاري التنزيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00F0FF))),
              const SizedBox(height: 10),
              ...active.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                        IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent), onPressed: () => DownloadManager.instance.cancelDownload(d.id)),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: d.progress, color: const Color(0xFF10B981), minHeight: 6),
                    ),
                  ],
                ),
              )),
              const Divider(),
            ],
            const Text('الملفات المكتملة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            if (_completed.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: Text('لا توجد ملفات مكتملة')),
              )
            else
              ..._completed.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill, color: Color(0xFF10B981), size: 28),
                  title: Text(e.value['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(e.value['size'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), onPressed: () => _deleteCompleted(e.key)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(mediaId: e.value['nb'], title: e.value['title'], videoUrl: e.value['path'], qualities: const [], isLocalFile: true))),
                ),
              )),
          ],
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
    FavoritesService.getFavorites().then((list) => setState(() => _favorites = list));
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
    _load();
  }

  void _load() async {
    final p = AppState.instance.currentProfile;
    final list = await LocalStorageService.getList('watch_later_items_$p');
    if (mounted) setState(() => _items = list);
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

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    StreamService.getRealAdminStats().then((s) {
      if (mounted) setState(() { _stats = s; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final heatmap = Map<String, int>.from(_stats['heatmap'] ?? {});

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('لوحة الإدارة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard('المستخدمون النشطون', '${_stats['active_users'] ?? 0}'),
                      const SizedBox(width: 10),
                      _statCard('المشاهدات', '${_stats['total_views'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('مخطط النشاط', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: heatmap.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 60, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                            Expanded(child: LinearProgressIndicator(value: (e.value / 20).clamp(0.05, 1.0), color: const Color(0xFFE50914))),
                            const SizedBox(width: 10),
                            Text('${e.value}', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statCard(String title, String val) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
