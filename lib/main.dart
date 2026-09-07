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

// -------------------------------------------------------------
// مدير التنزيلات المتقدم (Active & Completed Downloads)
// -------------------------------------------------------------
class ActiveDownload {
  final String id;
  final String title;
  double progress;
  http.Client? client;
  bool isCancelled = false;

  ActiveDownload({required this.id, required this.title, this.progress = 0.0});
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final Map<String, ActiveDownload> activeDownloads = {};

  void startDownload({
    required String targetId,
    required String title,
    required String url,
    required String poster,
  }) async {
    if (activeDownloads.containsKey(targetId)) return;

    final download = ActiveDownload(id: targetId, title: title);
    activeDownloads[targetId] = download;
    notifyListeners();

    try {
      final dir = Directory('/data/data/com.example.stream1_app/app_flutter');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final safeName = targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final filePath = '${dir.path}/$safeName.mp4';
      final file = File(filePath);

      final client = http.Client();
      download.client = client;

      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      final totalBytes = response.contentLength ?? 1;
      int receivedBytes = 0;

      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        if (download.isCancelled) {
          sink.close();
          if (file.existsSync()) file.deleteSync();
          return;
        }
        receivedBytes += chunk.length;
        sink.add(chunk);
        download.progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
        notifyListeners();
      }).asFuture();

      await sink.close();

      if (!download.isCancelled) {
        final fileSizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('downloaded_works_list');
        List<dynamic> dList = raw != null ? jsonDecode(raw) : [];
        dList.removeWhere((x) => x['id'].toString() == targetId);
        dList.insert(0, {
          'id': targetId,
          'title': title,
          'path': filePath,
          'size': '$fileSizeMb MB',
          'poster': poster,
        });
        await prefs.setString('downloaded_works_list', jsonEncode(dList));
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

// -------------------------------------------------------------
// مدير الحالة واللغة والمظهر والوضع العائلي
// -------------------------------------------------------------
class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  bool isDark = true;
  String lang = 'ar';
  bool isLoggedIn = false;
  bool isAdmin = false;
  String username = '';
  String deviceId = '';

  bool isFamilyMode = true;
  List<String> profiles = ['الرئيسي', 'أنمي', 'أطفال'];
  String currentProfile = 'الرئيسي';

  void initSession() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('app_device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'usr_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString('app_device_id', deviceId);
    }
    currentProfile = prefs.getString('active_profile') ?? 'الرئيسي';
    isFamilyMode = prefs.getBool('app_family_mode') ?? true;
    StreamService.sendHeartbeat(deviceId);
    Timer.periodic(const Duration(minutes: 4), (_) {
      StreamService.sendHeartbeat(deviceId);
    });
  }

  void toggleFamilyMode(bool val) async {
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

  void setLanguage(String newLang) {
    lang = newLang;
    notifyListeners();
  }

  void login(String user, String pass) {
    username = user;
    isLoggedIn = true;
    isAdmin = (user.trim().toLowerCase() == 'admin' && pass.trim() == 'admin123');
    notifyListeners();
  }

  void logout() {
    isLoggedIn = false;
    isAdmin = false;
    username = '';
    notifyListeners();
  }

  String tr(String arKey, String enKey) => lang == 'ar' ? arKey : enKey;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppState.instance.initSession();
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
              cardColor: const Color(0xFF0F1422),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFFE50914),
                surface: Color(0xFF0F1422),
                secondary: Color(0xFF00F0FF),
              ),
            )
          : ThemeData.light().copyWith(
              scaffoldBackgroundColor: const Color(0xFFF3F4F6),
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
// الشاشة الرئيسية
// -------------------------------------------------------------
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
  List<dynamic> _trending = [];
  List<dynamic> _featuredMovies = [];
  List<dynamic> _featuredSeries = [];
  List<dynamic> _activeGrid = [];
  final Set<int> _seenGridIds = {};

  List<Map<String, dynamic>> _continueWatchingList = [];
  List<String> _recentSearches = [];

  int _currentBannerPage = 0;
  Timer? _bannerTimer;

  int _page = 1;
  int _tabIndex = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _activeTitle = '🔥 الأكثر تداولاً وشهرة';
  Map<String, dynamic>? _selectedGenre;

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'ar': 'الكل', 'en': 'All'},
    {'id': 'anime', 'ar': 'أنمي ياباني', 'en': 'Anime'},
    {'id': '28', 'ar': 'أكشن', 'en': 'Action'},
    {'id': '12', 'ar': 'مغامرة', 'en': 'Adventure'},
    {'id': '35', 'ar': 'كوميديا', 'en': 'Comedy'},
    {'id': '80', 'ar': 'جريمة', 'en': 'Crime'},
    {'id': '18', 'ar': 'دراما', 'en': 'Drama'},
    {'id': '27', 'ar': 'رعب', 'en': 'Horror'},
    {'id': '878', 'ar': 'خيال علمي', 'en': 'Sci-Fi'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _tabIndex = _tabController.index;
        _selectedGenre = null;
        _fetchTabContent(reset: true);
      }
    });

    _fetchTabContent(reset: true);
    _loadContinueWatching();
    _loadSearchHistory();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore) {
          _fetchTabContent(reset: false);
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
      if (item['adult'] == true) return false;

      final title = (item['title'] ?? item['name'] ?? '').toString().toLowerCase();
      final originalTitle = (item['original_title'] ?? item['original_name'] ?? '').toString().toLowerCase();
      final overview = (item['overview'] ?? '').toString().toLowerCase();

      for (var word in blockedTerms) {
        if (title.contains(word) || originalTitle.contains(word) || overview.contains(word)) {
          return false;
        }
      }

      final genreIds = List<int>.from(item['genre_ids'] ?? []);
      if (genreIds.contains(10749) && (overview.contains('جسد') || overview.contains('شهوة'))) {
        return false;
      }

      return true;
    }).toList();
  }

  void _fetchTabContent({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasMore = true;
      _seenGridIds.clear();
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';
    final adult = AppState.instance.isFamilyMode ? 'false' : 'true';

    try {
      if (reset && _tabIndex == 0) {
        final shelfResponses = await Future.wait([
          http.get(Uri.parse('https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=$lang&include_adult=$adult&page=1')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/movie/popular?api_key=$key&language=$lang&include_adult=$adult&page=1')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/tv/popular?api_key=$key&language=$lang&include_adult=$adult&page=1')).timeout(const Duration(seconds: 8)),
        ]);

        if (mounted) {
          _trending = _filterStrictFamily(jsonDecode(shelfResponses[0].body)['results'] ?? []);
          _featuredMovies = _filterStrictFamily(jsonDecode(shelfResponses[1].body)['results'] ?? []);
          _featuredSeries = _filterStrictFamily(jsonDecode(shelfResponses[2].body)['results'] ?? []);
        }
      }

      String endpoint;
      if (_selectedGenre != null && _selectedGenre!['id'] != 'all') {
        final gId = _selectedGenre!['id'];
        endpoint = (gId == 'anime')
            ? 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=$lang&with_genres=16&with_original_language=ja&sort_by=popularity.desc&page=$_page&include_adult=$adult'
            : 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=$lang&with_genres=$gId&sort_by=popularity.desc&page=$_page&include_adult=$adult';
      } else if (_tabIndex == 1) {
        endpoint = 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=$lang&include_adult=$adult&sort_by=popularity.desc&page=$_page';
      } else if (_tabIndex == 2) {
        endpoint = 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=$lang&include_adult=$adult&sort_by=popularity.desc&page=$_page';
      } else {
        endpoint = 'https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=$lang&include_adult=$adult&page=$_page';
      }

      final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final raw = jsonDecode(res.body)['results'] ?? [];
        final filtered = _filterStrictFamily(raw);

        final List<dynamic> nonDuplicate = [];
        for (var item in filtered) {
          final id = item['id'] as int? ?? 0;
          if (!_seenGridIds.contains(id)) {
            _seenGridIds.add(id);
            nonDuplicate.add(item);
          }
        }

        setState(() {
          if (reset) {
            _activeGrid = nonDuplicate;
          } else {
            _activeGrid.addAll(nonDuplicate);
          }
          if (filtered.isEmpty || nonDuplicate.isEmpty) _hasMore = false;
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
    final app = AppState.instance;
    setState(() {
      _activeTitle = genre['id'] == 'all'
          ? app.tr('🔥 الأكثر تداولاً وشهرة', '🔥 Trending Now')
          : app.tr('تصنيف: ${genre['ar']}', 'Category: ${genre['en']}');
    });
    _fetchTabContent(reset: true);
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_trending.isNotEmpty && _bannerController.hasClients) {
        final next = (_currentBannerPage + 1) % (_trending.length.clamp(0, 7));
        _bannerController.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
  }

  void _loadContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    final raw = prefs.getString('continue_watching_list_$p');
    if (raw != null) {
      try {
        final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
        if (mounted) setState(() => _continueWatchingList = list);
      } catch (_) {}
    }
  }

  void _removeContinueWatchingItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    _continueWatchingList.removeWhere((item) => item['id'].toString() == id);
    await prefs.setString('continue_watching_list_$p', jsonEncode(_continueWatchingList));
    setState(() {});
  }

  void _clearAllContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    await prefs.remove('continue_watching_list_$p');
    setState(() => _continueWatchingList.clear());
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
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';
    final adult = AppState.instance.isFamilyMode ? 'false' : 'true';

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$key&language=$lang&include_adult=$adult&query=${Uri.encodeComponent(clean)}')).timeout(const Duration(seconds: 8));
      Navigator.pop(context);

      if (res.statusCode == 200 && mounted) {
        final list = _filterStrictFamily(jsonDecode(res.body)['results'] ?? []);
        setState(() {
          _activeGrid = list;
          _hasMore = false;
          _activeTitle = AppState.instance.tr('نتائج البحث عن: $clean', 'Search: $clean');
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
    final app = AppState.instance;
    final isRtl = app.lang == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        drawer: Drawer(
          backgroundColor: Theme.of(context).cardColor,
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
                  children: [
                    const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(app.isFamilyMode ? 'الوضع العائلي: محمي ومفعل 🛡️' : 'الوضع العائلي: معطل', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shield_rounded, color: Color(0xFF10B981)),
                title: Text(app.tr('الوضع العائلي الصارم', 'Strict Family Mode')),
                subtitle: Text(app.tr('حجب تام لكافة الأفلام والأنميات غير الملائمة', 'Block sensitive titles'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                value: app.isFamilyMode,
                onChanged: (val) {
                  app.toggleFamilyMode(val);
                  _fetchTabContent(reset: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_done_rounded, color: Color(0xFF10B981)),
                title: Text(app.tr('مدير التنزيلات (الجارية والمنتهية)', 'Downloads Manager')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
                title: Text(app.tr('قائمة المفضلة', 'Favorites')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.watch_later_rounded, color: Color(0xFF00F0FF)),
                title: Text(app.tr('المشاهدة لاحقاً', 'Watch Later')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen()));
                },
              ),
              if (app.isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF00F0FF)),
                  title: Text(app.tr('👑 لوحة تحكم المشرف (Admin)', '👑 Admin Dashboard')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                  },
                ),
              const Divider(),
              SwitchListTile(
                secondary: Icon(app.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                title: Text(app.tr('المظهر الداكن', 'Dark Theme')),
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(app.tr('التصنيفات والأنواع:', 'Categories:'), style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              ..._genres.map((g) => ListTile(
                    dense: true,
                    leading: Icon(
                      g['id'] == 'anime' ? Icons.animation_rounded : Icons.movie_creation_outlined,
                      size: 20,
                      color: g['id'] == 'anime' ? const Color(0xFF00F0FF) : Colors.grey,
                    ),
                    title: Text(isRtl ? g['ar'] : g['en']),
                    onTap: () {
                      Navigator.pop(context);
                      _filterGenre(g);
                    },
                  )),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: Theme.of(context).cardColor,
          elevation: 0,
          title: _isSearchExpanded
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: app.tr('ابحث بالاسم...', 'Search...'),
                    border: InputBorder.none,
                  ),
                )
              : const Text('ONEBR TV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              icon: Icon(_isSearchExpanded ? Icons.close : Icons.search, color: const Color(0xFF00F0FF)),
              onPressed: () {
                setState(() {
                  _isSearchExpanded = !_isSearchExpanded;
                  if (!_isSearchExpanded) _searchController.clear();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded, color: Color(0xFF10B981)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFE50914),
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: app.tr('الكل', 'All')),
              Tab(text: app.tr('الأفلام فقط', 'Movies Only')),
              Tab(text: app.tr('المسلسلات فقط', 'Series Only')),
            ],
          ),
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: () async => _fetchTabContent(reset: true),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSearchExpanded && _recentSearches.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          color: Theme.of(context).cardColor,
                          child: Wrap(
                            spacing: 8,
                            children: _recentSearches.map((s) => ActionChip(
                              backgroundColor: const Color(0xFF172033),
                              label: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              onPressed: () {
                                _searchController.text = s;
                                _search(s);
                              },
                            )).toList(),
                          ),
                        ),
                      ],

                      if (_tabIndex == 0 && _selectedGenre == null) ...[
                        if (_trending.isNotEmpty) _buildAutoHeroSlider(),
                        if (_continueWatchingList.isNotEmpty) _buildContinueWatchingShelf(),
                        if (_featuredMovies.isNotEmpty) _buildSectionShelf('🎬 أفلام مميزة ومختارة', _featuredMovies),
                        if (_featuredSeries.isNotEmpty) _buildSectionShelf('📺 مسلسلات وأنمي رائجة', _featuredSeries),
                      ],

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                        child: Text(_activeTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      ),
                      _buildResponsiveGrid(_activeGrid),
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

  Widget _buildAutoHeroSlider() {
    final bannerItems = _trending.take(7).toList();
    final width = MediaQuery.of(context).size.width;
    final height = (width * 0.55).clamp(200.0, 320.0);

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _bannerController,
        itemCount: bannerItems.length,
        itemBuilder: (ctx, i) {
          final item = bannerItems[i];
          final title = item['title'] ?? item['name'] ?? '';
          final backdrop = item['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${item['backdrop_path']}' : '';

          return Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: double.infinity,
                height: height,
                decoration: BoxDecoration(
                  image: backdrop.isNotEmpty ? DecorationImage(image: NetworkImage(backdrop), fit: BoxFit.cover) : null,
                ),
              ),
              Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Theme.of(context).scaffoldBackgroundColor, Colors.transparent],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                  onPressed: () => _openDetails(item),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContinueWatchingShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('▶ متابعة المشاهدة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF00F0FF))),
              TextButton(
                onPressed: _clearAllContinueWatching,
                child: const Text('مسح الكل', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _continueWatchingList.length,
            itemBuilder: (ctx, i) {
              final item = _continueWatchingList[i];
              return Container(
                width: 160,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                child: Stack(
                  children: [
                    InkWell(
                      onTap: () => _openDetails(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item['backdrop_path'] != null
                            ? Image.network('https://image.tmdb.org/t/p/w300${item['backdrop_path']}', fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                            : Container(color: Colors.grey.shade900),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: InkWell(
                        onTap: () => _removeContinueWatchingItem(item['id'].toString()),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 8,
                      left: 8,
                      child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionShelf(String title, List<dynamic> list) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth / 3.8).clamp(85.0, 115.0);
    final cardHeight = cardWidth * 1.45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0), child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        SizedBox(
          height: cardHeight + 42,
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
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        child: poster.isNotEmpty ? Image.network(poster, height: cardHeight, width: double.infinity, fit: BoxFit.cover) : Container(height: cardHeight, color: Colors.grey.shade900),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                            Text('⭐ $score', style: const TextStyle(fontSize: 8.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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

  Widget _buildResponsiveGrid(List<dynamic> list) {
    final width = MediaQuery.of(context).size.width;
    final count = width > 900 ? 6 : (width > 600 ? 5 : (width > 380 ? 4 : 3));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.58,
        ),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          final title = item['title'] ?? item['name'] ?? '';
          final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
          final score = (item['vote_average'] ?? 8.0).toStringAsFixed(1);
          final isTv = item['first_air_date'] != null || item['name'] != null;

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: isTv ? const Color(0xFF00F0FF) : const Color(0xFFE50914), borderRadius: BorderRadius.circular(3)),
                            child: Text(isTv ? 'مسلسل' : 'فيلم', style: const TextStyle(fontSize: 8.5, color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                        Text('⭐ $score', style: const TextStyle(fontSize: 8.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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
// شاشة التفاصيل الكاملة
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunching = false;
  bool _isLoadingEpisodes = true;
  bool _isFav = false;
  bool _isWatchLater = false;

  Map<String, dynamic>? _ceeData;
  List<dynamic> _seasons = [];
  List<dynamic> _episodes = [];
  List<dynamic> _similarMedia = [];
  int _selectedSeasonNumber = 1;
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media['first_air_date'] != null || widget.media['name'] != null;
    _checkSavedStates();
    _saveToContinueWatching();
    _matchExactContent();
    _loadSimilar();
    if (_isSeries) _loadSeasons();
  }

  void _checkSavedStates() async {
    final id = widget.media['id'].toString();
    final isFav = await FavoritesService.isFavorited(id);
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    final wlList = prefs.getStringList('watch_later_ids_$p') ?? [];

    if (mounted) {
      setState(() {
        _isFav = isFav;
        _isWatchLater = wlList.contains(id);
      });
    }
  }

  void _toggleWatchLater() async {
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    final id = widget.media['id'].toString();
    final raw = prefs.getString('watch_later_items_$p');
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    List<String> ids = prefs.getStringList('watch_later_ids_$p') ?? [];

    if (_isWatchLater) {
      list.removeWhere((x) => x['id'].toString() == id);
      ids.remove(id);
    } else {
      list.insert(0, widget.media);
      ids.add(id);
    }

    await prefs.setString('watch_later_items_$p', jsonEncode(list));
    await prefs.setStringList('watch_later_ids_$p', ids);

    if (mounted) {
      setState(() => _isWatchLater = !_isWatchLater);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isWatchLater ? 'تمت الإضافة للمشاهدة لاحقاً' : 'تمت الإزالة من المشاهدة لاحقاً'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _saveToContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    final raw = prefs.getString('continue_watching_list_$p');
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.removeWhere((item) => item['id'].toString() == widget.media['id'].toString());
    list.insert(0, widget.media);
    if (list.length > 10) list = list.sublist(0, 10);
    prefs.setString('continue_watching_list_$p', jsonEncode(list));
  }

  Future<void> _matchExactContent() async {
    final queryEn = widget.media['original_title'] ?? widget.media['original_name'] ?? widget.media['title'] ?? widget.media['name'] ?? '';
    final releaseDate = (widget.media['release_date'] ?? widget.media['first_air_date'] ?? '').toString();
    final year = releaseDate.split('-').first;

    try {
      final b64 = base64.encode(utf8.encode(queryEn)).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/15/video_title_search/$b64/itemsPerPage/15/pageNumber/0/level/0'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);

        if (results.isNotEmpty) {
          var matched = results.firstWhere(
            (r) => (r['year']?.toString() == year),
            orElse: () => results.first,
          );
          setState(() => _ceeData = matched);
        }
      }
    } catch (_) {}
  }

  void _loadSimilar() async {
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;
    final type = _isSeries ? 'tv' : 'movie';
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      final res = await http.get(Uri.parse('https://api.themoviedb.org/3/$type/$tmdbId/recommendations?api_key=$key&language=$lang')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _similarMedia = jsonDecode(res.body)['results'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSeasons() async {
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      final tvRes = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId?api_key=$key&language=$lang')).timeout(const Duration(seconds: 5));
      if (tvRes.statusCode == 200) {
        final data = jsonDecode(tvRes.body);
        final rawSeasons = data['seasons'] as List? ?? [];
        _seasons = rawSeasons.where((s) => (s['season_number'] ?? 0) > 0).toList();

        if (_seasons.isNotEmpty) {
          _selectedSeasonNumber = _seasons.first['season_number'] ?? 1;
          _loadEpisodesForSeason(_selectedSeasonNumber);
          return;
        }
      }
    } catch (_) {}

    _seasons = [{'season_number': 1, 'name': 'الموسم 1'}];
    _episodes = List.generate(24, (i) => {'episode_number': i + 1});
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  Future<void> _loadEpisodesForSeason(int sNum) async {
    setState(() => _isLoadingEpisodes = true);
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      final epRes = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/season/$sNum?api_key=$key&language=$lang')).timeout(const Duration(seconds: 5));
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
        _episodes = List.generate(24, (i) => {'episode_number': i + 1});
        _isLoadingEpisodes = false;
      });
    }
  }

  void _playStream({int? episodeNum, String? epTitle}) async {
    setState(() => _isLaunching = true);

    String targetId = _ceeData != null ? _ceeData!['nb'].toString() : widget.media['id'].toString();
    final title = epTitle ?? widget.media['title'] ?? widget.media['name'] ?? 'بث مباشر';

    StreamService.recordWatchEvent(targetId, title);

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
        const SnackBar(content: Text('جاري معالجة سيرفر هذا العمل، يرجى المحاولة بعد لحظات'), backgroundColor: Color(0xFFE50914)),
      );
    }
  }

  void _triggerDownload() async {
    String targetId = _ceeData != null ? _ceeData!['nb'].toString() : widget.media['id'].toString();
    final title = widget.media['title'] ?? widget.media['name'] ?? 'Video';

    final data = await StreamService.getVideoSource(targetId);
    if (data != null) {
      final qualities = List<Map<String, dynamic>>.from(data['qualities'] ?? []);
      final dlUrl = qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first)['url'];

      DownloadManager.instance.startDownload(
        targetId: targetId,
        title: title,
        url: dlUrl,
        poster: widget.media['poster_path'] ?? '',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بدأ تنزيل $title في قائمة التنزيلات الجارية!'), backgroundColor: const Color(0xFF10B981)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final poster = widget.media['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}' : '';
    final story = widget.media['overview'] ?? 'لا يوجد وصف متاح حالياً.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(title, style: const TextStyle(fontSize: 16)),
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
                    borderRadius: BorderRadius.circular(8),
                    child: poster.isNotEmpty ? Image.network(poster, width: 110, height: 160, fit: BoxFit.cover) : Container(width: 110, height: 160, color: Colors.grey.shade900),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _triggerDownload,
                          icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                          label: const Text('تنزيل في التطبيق', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                  onPressed: _isLaunching ? null : () => _playStream(episodeNum: 1, epTitle: '$title - حلقة 1'),
                  icon: _isLaunching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: Text(_isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة الآن', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 18),
              const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),

              if (_isSeries) ...[
                const SizedBox(height: 18),
                if (_seasons.isNotEmpty) ...[
                  const Text('المواسم:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _seasons.length,
                      itemBuilder: (ctx, i) {
                        final sNum = _seasons[i]['season_number'] ?? (i + 1);
                        final isSelected = _selectedSeasonNumber == sNum;
                        return InkWell(
                          onTap: () {
                            setState(() => _selectedSeasonNumber = sNum);
                            _loadEpisodesForSeason(sNum);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE50914) : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Text('الموسم $sNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('الحلقات (${_episodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1.3),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final epNum = i + 1;
                          return InkWell(
                            onTap: () => _playStream(episodeNum: epNum, epTitle: '$title - حلقة $epNum'),
                            child: Container(
                              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white12)),
                              child: Center(child: Text('$epNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ),
                          );
                        },
                      ),
              ],

              if (_similarMedia.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('أعمال قد تعجبك (مشابهة):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _similarMedia.length,
                    itemBuilder: (ctx, i) {
                      final item = _similarMedia[i];
                      final pPath = item['poster_path'];
                      return InkWell(
                        onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                        child: Container(
                          width: 90,
                          margin: const EdgeInsets.only(left: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: pPath != null ? Image.network('https://image.tmdb.org/t/p/w200$pPath', fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                          ),
                        ),
                      );
                    },
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

// -------------------------------------------------------------
// المشغل: زر الخروج والقفل باليمين دون تضارب مع Chewie ومستكشف ترجمة محلي
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final VoidCallback? onNextEpisode;
  final bool isLocalFile;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.onNextEpisode,
    this.isLocalFile = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isReady = false;
  bool _isLocked = false;

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18.0;
  Color _subtitleTextColor = Colors.white;
  Color _subtitleBgColor = Colors.black87;
  double _subtitleBottomPadding = 65.0;
  List<Subtitle> _parsedSubtitles = [];
  String _activeSubtitleText = '';

  @override
  void initState() {
    super.initState();
    _initPlayer();
    if (!widget.isLocalFile) _fetchSubtitles();
  }

  void _fetchSubtitles() async {
    try {
      final infoRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (infoRes.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
        final subUrl = info['arTranslationFilePath']?.toString() ?? info['arTranslationFile']?.toString() ?? '';
        if (subUrl.isNotEmpty) {
          final subRes = await http.get(Uri.parse(subUrl), headers: StreamService.stealthHeaders);
          if (subRes.statusCode == 200 && mounted) {
            setState(() {
              _parsedSubtitles = _parseSubtitles(utf8.decode(subRes.bodyBytes, allowMalformed: true));
            });
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

  void _initPlayer() async {
    if (widget.isLocalFile) {
      _videoPlayerController = VideoPlayerController.file(File(widget.videoUrl));
    } else {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: StreamService.stealthHeaders,
      );
    }

    await _videoPlayerController!.initialize();
    _videoPlayerController!.addListener(_updateSubtitles);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      additionalOptions: (context) => [
        OptionItem(onTap: (ctx) => _openSubtitleControls(), iconData: Icons.subtitles_rounded, title: 'إعدادات الترجمة المتطورة'),
      ],
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _updateSubtitles() {
    if (!_subtitlesEnabled || _parsedSubtitles.isEmpty || _videoPlayerController == null) {
      if (_activeSubtitleText.isNotEmpty && mounted) setState(() => _activeSubtitleText = '');
      return;
    }
    final pos = _videoPlayerController!.value.position;
    String text = '';
    for (var s in _parsedSubtitles) {
      if (pos >= s.start && pos <= s.end) {
        text = s.text;
        break;
      }
    }
    if (text != _activeSubtitleText && mounted) {
      setState(() => _activeSubtitleText = text);
    }
  }

  // مستكشف ملفات مدمج محلي يعتمد على فحص المجلدات مباشرة
  void _pickLocalSubtitleFile() {
    showDialog(
      context: context,
      builder: (ctx) {
        List<File> files = [];
        final paths = ['/sdcard/Download', '/sdcard/Documents', '/sdcard'];
        for (var p in paths) {
          final d = Directory(p);
          if (d.existsSync()) {
            try {
              files.addAll(d.listSync().whereType<File>().where((f) => f.path.endsWith('.srt') || f.path.endsWith('.vtt')));
            } catch (_) {}
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF0F1422),
          title: const Text('اختر ملف الترجمة من الهاتف:', style: TextStyle(fontSize: 15)),
          content: files.isEmpty
              ? const Text('لم يتم العثور على ملفات .srt في مجلد التنزيلات', style: TextStyle(fontSize: 12, color: Colors.grey))
              : SizedBox(
                  width: double.maxFinite,
                  height: 250,
                  child: ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.subtitles_rounded, color: Color(0xFF00F0FF)),
                      title: Text(files[i].path.split('/').last, style: const TextStyle(fontSize: 12)),
                      onTap: () {
                        final content = files[i].readAsStringSync();
                        setState(() {
                          _parsedSubtitles = _parseSubtitles(content);
                          _subtitlesEnabled = true;
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تطبيق ملف الترجمة بنجاح!')));
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _openSubtitleControls() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                title: const Text('تشغيل الترجمة'),
                value: _subtitlesEnabled,
                onChanged: (v) {
                  setSheetState(() => _subtitlesEnabled = v);
                  setState(() => _subtitlesEnabled = v);
                },
              ),
              const Text('حجم خط الترجمة:', style: TextStyle(fontSize: 12, color: Colors.white70)),
              Slider(
                value: _subtitleFontSize, min: 14.0, max: 32.0, divisions: 9,
                label: _subtitleFontSize.round().toString(),
                onChanged: (v) {
                  setSheetState(() => _subtitleFontSize = v);
                  setState(() => _subtitleFontSize = v);
                },
              ),
              const Text('ارتفاع موضع الترجمة (لتجنب الأسفل في الوضع العمودي):', style: TextStyle(fontSize: 12, color: Colors.white70)),
              Slider(
                value: _subtitleBottomPadding, min: 30.0, max: 140.0, divisions: 11,
                label: '${_subtitleBottomPadding.round()}px',
                onChanged: (v) {
                  setSheetState(() => _subtitleBottomPadding = v);
                  setState(() => _subtitleBottomPadding = v);
                },
              ),
              Row(
                children: [
                  const Text('لون الخط: ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  _colorChip(Colors.white, () { setSheetState(() => _subtitleTextColor = Colors.white); setState(() => _subtitleTextColor = Colors.white); }),
                  _colorChip(const Color(0xFFFDE047), () { setSheetState(() => _subtitleTextColor = const Color(0xFFFDE047)); setState(() => _subtitleTextColor = const Color(0xFFFDE047)); }),
                  _colorChip(const Color(0xFF00F0FF), () { setSheetState(() => _subtitleTextColor = const Color(0xFF00F0FF)); setState(() => _subtitleTextColor = const Color(0xFF00F0FF)); }),
                ],
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.file_open_rounded, color: Color(0xFF00F0FF)),
                title: const Text('اختيار ملف ترجمة من الهاتف (.srt)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickLocalSubtitleFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorChip(Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(margin: const EdgeInsets.symmetric(horizontal: 6), width: 24, height: 24, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white54))),
    );
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_updateSubtitles);
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
            Center(
              child: (_isReady && _chewieController != null)
                  ? Chewie(controller: _chewieController!)
                  : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
            ),

            if (_subtitlesEnabled && _activeSubtitleText.isNotEmpty)
              Positioned(
                bottom: _subtitleBottomPadding,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: _subtitleBgColor, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      _activeSubtitleText,
                      style: TextStyle(color: _subtitleTextColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // زر الخروج وزر القفل في الزاوية العلوية اليمنى
            if (!_isLocked)
              Positioned(
                top: 14,
                right: 14,
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                        tooltip: 'قفل الشاشة',
                        onPressed: () => setState(() => _isLocked = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                        tooltip: 'إغلاق المشغل',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isLocked)
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFE50914).withOpacity(0.8), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                    tooltip: 'إلغاء قفل الشاشة',
                    onPressed: () => setState(() => _isLocked = false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// لوحة تحكم المشرف الشاملة
// -------------------------------------------------------------
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  int _activeUsers = 0;
  int _totalViews = 0;
  List<Map<String, dynamic>> _recentPlays = [];
  Map<String, int> _heatmap = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() async {
    setState(() => _loading = true);
    final stats = await StreamService.getRealAdminStats();
    if (mounted) {
      setState(() {
        _activeUsers = stats['active_users'] ?? 0;
        _totalViews = stats['total_views'] ?? 0;
        _recentPlays = List<Map<String, dynamic>>.from(stats['recent_plays'] ?? []);
        _heatmap = Map<String, int>.from(stats['heatmap'] ?? {});
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return Directionality(
      textDirection: app.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(app.tr('👑 لوحة تحكم المشرف والخريطة الحية', '👑 Admin & Heatmap Dashboard')),
          backgroundColor: const Color(0xFF0F1422),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F0FF)), onPressed: _loadStats)
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(app.tr('📊 إحصائيات المنصة الحية:', '📊 Live Stats:'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statCard('المستخدمين المتصلين الآن', '$_activeUsers', Icons.wifi_tethering_rounded, const Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      _statCard('إجمالي المشاهدات الحقيقية', '$_totalViews', Icons.play_circle_filled_rounded, const Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Text('🔥 الخريطة الحرارية للمشاهدين (Live Traffic Heatmap):', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                    child: Column(
                      children: _heatmap.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 70, child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: (e.value / (_activeUsers == 0 ? 1 : _activeUsers)).clamp(0.1, 1.0),
                                color: const Color(0xFFE50914),
                                backgroundColor: const Color(0xFF172033),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('${e.value} مشاهد', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text('📺 أحدث المشاهدات الحية:', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._recentPlays.map((p) => Card(
                    color: const Color(0xFF0F1422),
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.live_tv_rounded, color: Color(0xFFE50914), size: 20),
                      title: Text(p['title'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      trailing: Text(p['time'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  )),
                ],
              ),
      ),
    );
  }

  Widget _statCard(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF0F1422), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة مدير التنزيلات
// -------------------------------------------------------------
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
    DownloadManager.instance.addListener(() => setState(() {}));
  }

  void _loadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('downloaded_works_list');
    if (raw != null) {
      setState(() => _completed = List<Map<String, dynamic>>.from(jsonDecode(raw)));
    }
  }

  void _deleteCompleted(int index) async {
    final item = _completed[index];
    final path = item['path'];
    if (path != null) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
    setState(() => _completed.removeAt(index));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('downloaded_works_list', jsonEncode(_completed));
  }

  @override
  Widget build(BuildContext context) {
    final active = DownloadManager.instance.activeDownloads.values.toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('📥 مدير التنزيلات'), backgroundColor: Theme.of(context).cardColor),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (active.isNotEmpty) ...[
              const Text('⏳ التنزيلات الجارية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF00F0FF))),
              const SizedBox(height: 8),
              ...active.map((d) => Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                          IconButton(
                            icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                            onPressed: () => DownloadManager.instance.cancelDownload(d.id),
                          ),
                        ],
                      ),
                      LinearProgressIndicator(value: d.progress, color: const Color(0xFF10B981)),
                      const SizedBox(height: 4),
                      Text('${(d.progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              )),
              const Divider(height: 24),
            ],

            const Text('✅ الأعمال المنزلة الجاهزة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981))),
            const SizedBox(height: 8),
            if (_completed.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('لا توجد أعمال منزلة بعد', style: TextStyle(color: Colors.grey))),
              )
            else
              ..._completed.asMap().entries.map((e) => Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 32),
                  title: Text(e.value['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('الحجم: ${e.value['size'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    onPressed: () => _deleteCompleted(e.key),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          mediaId: e.value['id'] ?? '',
                          title: e.value['title'] ?? '',
                          videoUrl: e.value['path'] ?? '',
                          qualities: const [],
                          isLocalFile: true,
                        ),
                      ),
                    );
                  },
                ),
              )),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة المشاهدة لاحقاً
// -------------------------------------------------------------
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
    final prefs = await SharedPreferences.getInstance();
    final p = AppState.instance.currentProfile;
    final raw = prefs.getString('watch_later_items_$p');
    if (raw != null) {
      setState(() => _items = List<Map<String, dynamic>>.from(jsonDecode(raw)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('🕒 المشاهدة لاحقاً'), backgroundColor: Theme.of(context).cardColor),
        body: _items.isEmpty
            ? const Center(child: Text('لا توجد عناصر في قائمة المشاهدة لاحقاً'))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 0.58),
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _load()),
                    child: Container(
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6)),
                      child: Column(
                        children: [
                          Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(6)), child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container())),
                          Padding(padding: const EdgeInsets.all(4), child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5))),
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
// شاشة المفضلة
// -------------------------------------------------------------
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
        appBar: AppBar(title: const Text('⭐ قائمة المفضلة'), backgroundColor: Theme.of(context).cardColor),
        body: _favorites.isEmpty
            ? const Center(child: Text('لا توجد عناصر في المفضلة'))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 0.58),
                itemCount: _favorites.length,
                itemBuilder: (ctx, i) {
                  final item = _favorites[i];
                  final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                    child: Container(
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6)),
                      child: Column(
                        children: [
                          Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(6)), child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container())),
                          Padding(padding: const EdgeInsets.all(4), child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5))),
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
