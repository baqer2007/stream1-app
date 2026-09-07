import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

// -------------------------------------------------------------
// 1. محرك كاش الروابط الفائق (Link Extraction Cache)
// -------------------------------------------------------------
class StreamLinkCache {
  static final Map<String, Map<String, dynamic>> _memoryCache = {};

  static Future<Map<String, dynamic>?> getValidSource(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_memoryCache.containsKey(id)) {
      final item = _memoryCache[id]!;
      if (now - (item['timestamp'] as int) < 4 * 3600 * 1000) {
        return item['data'] as Map<String, dynamic>;
      } else {
        _memoryCache.remove(id);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_src_$id');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (now - (decoded['timestamp'] as int) < 4 * 3600 * 1000) {
          _memoryCache[id] = decoded;
          return decoded['data'] as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<void> saveSource(String id, Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = {'timestamp': now, 'data': data};
    _memoryCache[id] = payload;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_src_$id', jsonEncode(payload));
  }
}

// -------------------------------------------------------------
// 2. محرك الاستخراج والتوجيه الذكي للموقع الجغرافي
// -------------------------------------------------------------
class UniversalStreamResolver {
  static const stealthHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  /// استخراج روابط البث المباشرة الخالية من الإعلانات لمستخدمي الخارج
  static Future<Map<String, dynamic>?> resolveDirectExtraction({
    required String tmdbId,
    required bool isSeries,
    int season = 1,
    int episode = 1,
  }) async {
    final urls = isSeries
        ? [
            'https://player.autoembed.cc/embed/tv/$tmdbId/$season/$episode',
            'https://vidsrc.cc/v2/embed/tv/$tmdbId/$season/$episode',
          ]
        : [
            'https://player.autoembed.cc/embed/movie/$tmdbId',
            'https://vidsrc.cc/v2/embed/movie/$tmdbId',
          ];

    for (var url in urls) {
      try {
        final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final reg = RegExp(r"""(https?://[^\s"'<>]+\.(?:m3u8|mp4)[^\s"'<>]*)""");
          final match = reg.firstMatch(res.body);

          if (match != null) {
            final rawUrl = match.group(1)!;
            return {
              'video_url': rawUrl,
              'qualities': [{'resolution': 'تلقائي (Fast CDN)', 'url': rawUrl}],
              'source_name': 'سيرفر دولي فائق السرعة 🌍',
            };
          }
        }
      } catch (_) {}
    }

    try {
      final emergencyApi = isSeries
          ? 'https://embed.su/api/e/tv/$tmdbId/$season/$episode'
          : 'https://embed.su/api/e/movie/$tmdbId';

      final res = await http.get(Uri.parse(emergencyApi), headers: {
        'Referer': 'https://embed.su/',
        'User-Agent': stealthHeaders['User-Agent']!,
      }).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['source'] != null) {
          return {
            'video_url': data['source'],
            'qualities': [{'resolution': 'تلقائي (Multi-Quality)', 'url': data['source']}],
            'source_name': 'سيرفر عالمي احتياطي 🚀',
          };
        }
      }
    } catch (_) {}

    return null;
  }

  /// التوجيه الفوري وفق بيئة الاتصال
  static Future<Map<String, dynamic>?> resolveSmartStream({
    required String targetId,
    required String tmdbId,
    required bool isSeries,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = targetId.isNotEmpty ? targetId : tmdbId;

    final cached = await StreamLinkCache.getValidSource(cacheKey);
    if (cached != null) return cached;

    final bool isLocal = AppState.instance.isInsideIraq;

    if (isLocal && targetId.isNotEmpty) {
      try {
        final cinemanaData = await StreamService.getVideoSource(targetId).timeout(const Duration(seconds: 2));
        if (cinemanaData != null && cinemanaData['video_url'] != null) {
          cinemanaData['source_name'] = 'سيرفر سينمانا المحلي ⚡';
          await StreamLinkCache.saveSource(cacheKey, cinemanaData);
          return cinemanaData;
        }
      } catch (_) {}
    }

    final directData = await resolveDirectExtraction(
      tmdbId: tmdbId,
      isSeries: isSeries,
      season: season,
      episode: episode,
    );

    if (directData != null) {
      await StreamLinkCache.saveSource(cacheKey, directData);
      return directData;
    }

    return null;
  }
}

// -------------------------------------------------------------
// 3. طبقة التخزين الموحدة (LocalStorageService)
// -------------------------------------------------------------
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

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 25, String idField = 'id'}) async {
    final list = await getList(key);
    list.removeWhere((x) => x[idField]?.toString() == item[idField]?.toString());
    list.insert(0, item);
    if (list.length > maxLength) list.removeRange(maxLength, list.length);
    await setList(key, list);
  }

  static Future<void> removeItem(String key, String id, {String idField = 'id'}) async {
    final list = await getList(key);
    list.removeWhere((x) => x[idField]?.toString() == id);
    await setList(key, list);
  }
}

// -------------------------------------------------------------
// 4. مدير التنزيل الداخلي مع التخزين الآمن
// -------------------------------------------------------------
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
    final paths = ['/storage/emulated/0/Download', '/sdcard/Download'];
    for (var p in paths) {
      final d = Directory('$p/ONEBR_Downloads');
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
        return d.path;
      } catch (_) {}
    }
    final fallback = Directory('${Directory.systemTemp.path}/ONEBR_Downloads');
    if (!fallback.existsSync()) fallback.createSync(recursive: true);
    return fallback.path;
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
      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      final response = await client.send(request);
      final totalBytes = (response.contentLength ?? 0) + downloadedBytes;

      final sink = file.openWrite(mode: FileMode.append);
      int lastNotifiedBytes = downloadedBytes;

      await response.stream.listen((chunk) {
        if (download.isCancelled) {
          sink.close();
          return;
        }
        downloadedBytes += chunk.length;
        sink.add(chunk);

        if (totalBytes > 0 && (downloadedBytes - lastNotifiedBytes > 300 * 1024 || downloadedBytes == totalBytes)) {
          lastNotifiedBytes = downloadedBytes;
          download.progress = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
          notifyListeners();
        }
      }).asFuture();

      await sink.close();

      if (!download.isCancelled) {
        final fileSizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        await LocalStorageService.appendItem('downloaded_works_list', {
          'id': targetId,
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

// -------------------------------------------------------------
// 5. مدير الحالة العامة مع فاحص الموقع الجغرافي
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

  bool isInsideIraq = true;
  String detectedCountry = 'IQ';
  bool isNetworkChecking = true;

  Future<void> detectNetworkEnvironment() async {
    isNetworkChecking = true;
    try {
      final res = await http.get(Uri.parse('https://api.country.is/')).timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        detectedCountry = (data['country'] ?? 'IQ').toString().toUpperCase();
        isInsideIraq = (detectedCountry == 'IQ');
      } else {
        isInsideIraq = true;
      }
    } catch (_) {
      isInsideIraq = true;
    } finally {
      isNetworkChecking = false;
      notifyListeners();
    }
  }

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('app_device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'usr_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString('app_device_id', deviceId);
    }
    currentProfile = prefs.getString('active_profile') ?? 'الرئيسي';
    isFamilyMode = prefs.getBool('app_family_mode') ?? true;

    await detectNetworkEnvironment();

    StreamService.sendHeartbeat(deviceId);
    Timer.periodic(const Duration(minutes: 4), (_) => StreamService.sendHeartbeat(deviceId));
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
              dialogTheme: DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                backgroundColor: const Color(0xFF111726),
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
              dialogTheme: DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                backgroundColor: Colors.white,
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
// 6. الشاشة الرئيسية
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
    {'id': 'anime', 'ar': 'أنمي ورسوم متحركة', 'en': 'Anime & Animation'},
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
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
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
        if (title.contains(word) || originalTitle.contains(word) || overview.contains(word)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _fetchTabContent({bool reset = false}) async {
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
            if (_tabIndex == 0 && _selectedGenre == null) _trending = List.from(nonDuplicate);
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
    final p = AppState.instance.currentProfile;
    final list = await LocalStorageService.getList('continue_watching_list_$p');
    if (mounted) setState(() => _continueWatchingList = list);
  }

  void _removeContinueWatchingItem(String id) async {
    final p = AppState.instance.currentProfile;
    await LocalStorageService.removeItem('continue_watching_list_$p', id);
    _loadContinueWatching();
  }

  void _clearAllContinueWatching() async {
    final p = AppState.instance.currentProfile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('continue_watching_list_$p');
    setState(() => _continueWatchingList.clear());
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

    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';
    final adult = AppState.instance.isFamilyMode ? 'false' : 'true';

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$key&language=$lang&include_adult=$adult&query=${Uri.encodeComponent(clean)}')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final list = _filterStrictFamily(jsonDecode(res.body)['results'] ?? []);
        setState(() {
          _activeGrid = list;
          _hasMore = false;
          _activeTitle = AppState.instance.tr('نتائج البحث عن: $clean', 'Search: $clean');
        });
      }
    } catch (_) {}
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.tv_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                      child: Text('الملف: ${app.currentProfile} ${app.isFamilyMode ? "• عائلي 🛡️" : ""}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: app.isInsideIraq ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFF00F0FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            app.isInsideIraq ? Icons.offline_bolt_rounded : Icons.public_rounded,
                            size: 14,
                            color: app.isInsideIraq ? const Color(0xFF10B981) : const Color(0xFF00F0FF),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            app.isInsideIraq ? 'سيرفر محلي (العراق 🇮🇶)' : 'سيرفر دولي فائق السرعة 🌍',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: app.isInsideIraq ? const Color(0xFF10B981) : const Color(0xFF00F0FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 20),
                ),
                title: Text(app.tr('الوضع العائلي الصارم', 'Strict Family Mode'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(app.tr('حجب تام للمحتوى الحساس', 'Block sensitive titles'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                value: app.isFamilyMode,
                onChanged: (val) {
                  app.toggleFamilyMode(val);
                  _fetchTabContent(reset: true);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.switch_account_rounded, color: Color(0xFF00F0FF), size: 20),
                ),
                title: Text(app.tr('تبديل الهوية', 'Switch Profile'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                trailing: DropdownButton<String>(
                  value: app.currentProfile,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(context).cardColor,
                  items: app.profiles.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      app.switchProfile(val);
                      _loadContinueWatching();
                      _fetchTabContent(reset: true);
                    }
                  },
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.download_done_rounded, color: Color(0xFF10B981), size: 20),
                ),
                title: Text(app.tr('التنزيلات', 'Downloads'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B), size: 20),
                ),
                title: Text(app.tr('المفضلة', 'Favorites'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.watch_later_rounded, color: Color(0xFF00F0FF), size: 20),
                ),
                title: Text(app.tr('المشاهدة لاحقاً', 'Watch Later'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen()));
                },
              ),
              if (app.isAdmin)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber, size: 20),
                  ),
                  title: Text(app.tr('👑 لوحة المشرف', '👑 Admin Dashboard'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                  },
                ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 24)),
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(app.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: Colors.purpleAccent, size: 20),
                ),
                title: Text(app.tr('المظهر الداكن', 'Dark Theme'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 24)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(app.tr('التصنيفات:', 'Categories:'), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              ..._genres.map((g) => ListTile(
                    dense: true,
                    leading: Icon(
                      g['id'] == 'anime' ? Icons.animation_rounded : Icons.movie_creation_outlined,
                      size: 18,
                      color: g['id'] == 'anime' ? const Color(0xFF00F0FF) : Colors.grey,
                    ),
                    title: Text(isRtl ? g['ar'] : g['en'], style: const TextStyle(fontSize: 13)),
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
                    decoration: InputDecoration(
                      hintText: app.tr('ابحث بالاسم...', 'Search...'),
                      border: InputBorder.none,
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                )
              : const Text('ONEBR TV', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          actions: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, shape: BoxShape.circle),
                child: Icon(_isSearchExpanded ? Icons.close : Icons.search, color: const Color(0xFF00F0FF), size: 19),
              ),
              onPressed: () => setState(() => _isSearchExpanded = !_isSearchExpanded),
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, shape: BoxShape.circle),
                child: const Icon(Icons.download_for_offline_rounded, color: Color(0xFF10B981), size: 19),
              ),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFE50914).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(text: app.tr('الكل', 'All')),
                  Tab(text: app.tr('الأفلام', 'Movies')),
                  Tab(text: app.tr('المسلسلات', 'Series')),
                ],
              ),
            ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            children: _recentSearches.map((s) => ActionChip(
                              backgroundColor: Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        if (_trending.isNotEmpty) _buildCurvedHeroBanner(),
                        if (_continueWatchingList.isNotEmpty) _buildContinueWatchingShelf(),
                        if (_featuredMovies.isNotEmpty) _buildCurvedSectionShelf('🎬 أفلام مختارة', _featuredMovies),
                        if (_featuredSeries.isNotEmpty) _buildCurvedSectionShelf('📺 مسلسلات وأنمي رائجة', _featuredSeries),
                      ],

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Text(_activeTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                      _buildCurvedGrid(_activeGrid),
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

  Widget _buildCurvedHeroBanner() {
    final bannerItems = _trending.take(7).toList();
    final width = MediaQuery.of(context).size.width;
    final height = (width * 0.55).clamp(210.0, 310.0);

    return Container(
      margin: const EdgeInsets.all(16),
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            PageView.builder(
              controller: _bannerController,
              itemCount: bannerItems.length,
              onPageChanged: (i) => setState(() => _currentBannerPage = i),
              itemBuilder: (ctx, i) {
                final item = bannerItems[i];
                final backdrop = item['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${item['backdrop_path']}' : '';
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    backdrop.isNotEmpty ? Image.network(backdrop, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xDD07090E), Colors.transparent],
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
                              item['title'] ?? item['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              elevation: 4,
                            ),
                            onPressed: () => _openDetails(item),
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                            label: const Text('مشاهدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('${_currentBannerPage + 1}/${bannerItems.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
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
              const Row(
                children: [
                  Icon(Icons.play_circle_filled_rounded, color: Color(0xFF00F0FF), size: 18),
                  SizedBox(width: 6),
                  Text('متابعة المشاهدة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00F0FF))),
                ],
              ),
              TextButton(
                onPressed: _clearAllContinueWatching,
                child: const Text('مسح الكل', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
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
              return Container(
                width: 155,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      InkWell(
                        onTap: () => _openDetails(item),
                        child: item['backdrop_path'] != null
                            ? Image.network('https://image.tmdb.org/t/p/w300${item['backdrop_path']}', fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                            : Container(color: Colors.grey.shade900),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: InkWell(
                          onTap: () => _removeContinueWatchingItem(item['id'].toString()),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 10,
                        left: 10,
                        child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
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

  Widget _buildCurvedSectionShelf(String title, List<dynamic> list) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth / 3.6).clamp(95.0, 125.0);
    final cardHeight = cardWidth * 1.45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ),
        SizedBox(
          height: cardHeight + 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        child: poster.isNotEmpty ? Image.network(poster, height: cardHeight, width: double.infinity, fit: BoxFit.cover) : Container(height: cardHeight, color: Colors.grey.shade900),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('⭐ $score', style: const TextStyle(fontSize: 9, color: Color(0xFFF59E0B), fontWeight: FontWeight.w900)),
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

  Widget _buildCurvedGrid(List<dynamic> list) {
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
          final title = item['title'] ?? item['name'] ?? '';
          final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
          final score = (item['vote_average'] ?? 8.0).toStringAsFixed(1);
          final isTv = item['first_air_date'] != null || item['name'] != null;

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))],
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
                              color: isTv ? const Color(0xFF00F0FF) : const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(isTv ? 'مسلسل' : 'فيلم', style: const TextStyle(fontSize: 8.5, color: Colors.black, fontWeight: FontWeight.w900)),
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
                        Text('⭐ $score', style: const TextStyle(fontSize: 9, color: Color(0xFFF59E0B), fontWeight: FontWeight.w900)),
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
// 7. شاشة التفاصيل مع دمج المحرك الذكي
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isMatching = true;
  bool _isLaunching = false;
  bool _isLoadingEpisodes = true;
  bool _isFav = false;
  bool _isWatchLater = false;

  Map<String, dynamic>? _matchedCee;
  List<dynamic> _ceeEpisodesList = [];
  List<dynamic> _episodes = [];
  List<dynamic> _seasons = [];
  List<dynamic> _similarMedia = [];
  int _selectedSeasonNumber = 1;
  bool _isSeries = false;

  String _displayEnglishTitle = '';

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media['first_air_date'] != null || widget.media['name'] != null;
    _checkSavedStates();
    _saveHistory();
    _resolveRealTitlesAndMatch();
    _loadSimilar();
    if (_isSeries) _loadSeasons();
  }

  void _checkSavedStates() async {
    final id = widget.media['id'].toString();
    final isFav = await FavoritesService.isFavorited(id);
    final p = AppState.instance.currentProfile;
    final wlList = await LocalStorageService.getList('watch_later_items_$p');
    final isWl = wlList.any((x) => x['id']?.toString() == id);

    if (mounted) {
      setState(() {
        _isFav = isFav;
        _isWatchLater = isWl;
      });
    }
  }

  void _toggleWatchLater() async {
    final p = AppState.instance.currentProfile;
    final id = widget.media['id'].toString();

    if (_isWatchLater) {
      await LocalStorageService.removeItem('watch_later_items_$p', id);
    } else {
      await LocalStorageService.appendItem('watch_later_items_$p', widget.media);
    }

    if (mounted) {
      setState(() => _isWatchLater = !_isWatchLater);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(_isWatchLater ? 'تمت الإضافة للمشاهدة لاحقاً' : 'تمت الإزالة من المشاهدة لاحقاً'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _saveHistory() async {
    final p = AppState.instance.currentProfile;
    await LocalStorageService.appendItem('continue_watching_list_$p', widget.media);
  }

  String _clean(String s) {
    return s.toLowerCase()
        .replaceAll(RegExp(r'[:\-_–—!?.()\[\]\/\\#&,"]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final w1 = s1.split(' ').where((w) => w.length > 1).toSet();
    final w2 = s2.split(' ').where((w) => w.length > 1).toSet();

    if (w1.isEmpty || w2.isEmpty) {
      return s1.contains(s2) || s2.contains(s1) ? 0.8 : 0.0;
    }

    final intersection = w1.intersection(w2);
    final union = w1.union(w2);
    final jaccard = intersection.length / union.length;

    bool substringMatch = s1.contains(s2) || s2.contains(s1);
    if (substringMatch && (s1.length > 6 && s2.length > 6)) {
      return max(jaccard, 0.75);
    }

    return jaccard;
  }

  Future<void> _resolveRealTitlesAndMatch() async {
    setState(() => _isMatching = true);

    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;
    final type = _isSeries ? 'tv' : 'movie';

    final Set<String> searchQueries = {};

    final origName = (widget.media['original_name'] ?? widget.media['original_title'] ?? '').toString().trim();
    final transName = (widget.media['name'] ?? widget.media['title'] ?? '').toString().trim();

    if (origName.isNotEmpty) {
      searchQueries.add(origName);
      if (origName.contains(':')) searchQueries.add(origName.split(':').last.trim());
      if (origName.contains('-')) searchQueries.add(origName.split('-').first.trim());
    }
    if (transName.isNotEmpty) {
      searchQueries.add(transName);
      if (transName.contains(':')) searchQueries.add(transName.split(':').last.trim());
    }

    try {
      final endpoints = [
        'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$key&language=en-US',
        'https://api.themoviedb.org/3/$type/$tmdbId/alternative_titles?api_key=$key',
      ];

      final responses = await Future.wait(
        endpoints.map((u) => http.get(Uri.parse(u)).timeout(const Duration(seconds: 4))),
      );

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        final enTitle = (data['name'] ?? data['title'] ?? '').toString().trim();
        if (enTitle.isNotEmpty) {
          _displayEnglishTitle = enTitle;
          searchQueries.add(enTitle);
          if (enTitle.contains(':')) searchQueries.add(enTitle.split(':').last.trim());
          if (enTitle.contains('-')) searchQueries.add(enTitle.split('-').first.trim());
        }
      }

      if (responses[1].statusCode == 200) {
        final altData = jsonDecode(responses[1].body);
        final list = (altData['titles'] ?? altData['results'] ?? []) as List;
        for (var t in list) {
          final tName = (t['title'] ?? '').toString().trim();
          if (tName.isNotEmpty) {
            searchQueries.add(tName);
            if (tName.contains(':')) searchQueries.add(tName.split(':').last.trim());
          }
        }
      }
    } catch (_) {}

    final date = (widget.media['first_air_date'] ?? widget.media['release_date'] ?? '').toString();
    final targetYear = date.split('-').first.trim();

    await _searchCeeBuzz(searchQueries.toList(), targetYear);

    if (mounted) setState(() => _isMatching = false);
  }

  Future<void> _searchCeeBuzz(List<String> queries, String targetYear) async {
    final levels = _isSeries ? ['1', '0'] : ['0', '1'];
    final int? tYear = int.tryParse(targetYear);

    Map<String, dynamic>? bestMatch;
    double highestScore = 0.0;

    for (var lvl in levels) {
      if (bestMatch != null && highestScore >= 0.85) break;

      for (var query in queries) {
        final cleanQ = _clean(query);
        if (cleanQ.length < 2) continue;

        try {
          final b64 = base64Url.encode(utf8.encode(query)).replaceAll('=', '');
          final res = await http.get(
            Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/40/video_title_search/$b64/itemsPerPage/40/pageNumber/0/level/$lvl'),
            headers: StreamService.stealthHeaders,
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
            List list = (decoded is List) ? decoded : (decoded['articles'] ?? []);

            for (var item in list) {
              final enTitle = _clean((item['en_title'] ?? '').toString());
              final arTitle = _clean((item['title'] ?? '').toString());
              final int? itemY = int.tryParse((item['year'] ?? '').toString().trim());

              final scoreEn = _calculateSimilarity(cleanQ, enTitle);
              final scoreAr = _calculateSimilarity(cleanQ, arTitle);
              double itemScore = max(scoreEn, scoreAr);

              if (itemScore < 0.55) continue;

              if (tYear != null && itemY != null && itemY > 1900) {
                final diff = (itemY - tYear).abs();
                if (diff == 0) {
                  itemScore += 0.20;
                } else if (diff == 1) {
                  itemScore += 0.05;
                } else if (diff > 2) {
                  itemScore -= 0.35;
                }
              }

              if (itemScore > highestScore && itemScore >= 0.65) {
                highestScore = itemScore;
                bestMatch = item;
                if (highestScore >= 0.95) break;
              }
            }
          }
        } catch (_) {}

        if (bestMatch != null && highestScore >= 0.95) break;
      }
    }

    if (bestMatch != null && highestScore >= 0.65) {
      _matchedCee = bestMatch;
      if (_isSeries) {
        await _loadCeeEpisodes(bestMatch['nb'].toString());
      }
    }
  }

  Future<void> _loadCeeEpisodes(String parentId) async {
    try {
      final epRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/100/parent_id/$parentId/itemsPerPage/100/pageNumber/0/level/2'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 5));

      if (epRes.statusCode == 200) {
        dynamic epData = jsonDecode(utf8.decode(epRes.bodyBytes, allowMalformed: true));
        List list = (epData is List) ? epData : (epData['articles'] ?? []);
        if (mounted && list.isNotEmpty) {
          setState(() => _ceeEpisodesList = list);
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
        setState(() => _similarMedia = jsonDecode(res.body)['results'] ?? []);
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

  void _play(int epNum) async {
    setState(() => _isLaunching = true);

    String targetId = '';
    if (_matchedCee != null) {
      targetId = _matchedCee!['nb'].toString();
      if (_isSeries && _ceeEpisodesList.isNotEmpty && epNum <= _ceeEpisodesList.length) {
        targetId = _ceeEpisodesList[epNum - 1]['nb'].toString();
      }
    }

    final playData = await UniversalStreamResolver.resolveSmartStream(
      targetId: targetId,
      tmdbId: widget.media['id'].toString(),
      isSeries: _isSeries,
      season: _selectedSeasonNumber,
      episode: epNum,
    );

    setState(() => _isLaunching = false);

    if (playData != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId.isNotEmpty ? targetId : widget.media['id'].toString(),
            title: '${widget.media['title'] ?? widget.media['name'] ?? ''} - حلقة $epNum',
            videoUrl: playData['video_url'],
            qualities: List<Map<String, dynamic>>.from(playData['qualities'] ?? []),
            serverSourceName: playData['source_name'] ?? 'سيرفر فائق السرعة',
            onNextEpisode: epNum < _episodes.length ? () => _play(epNum + 1) : null,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر جلب رابط الفيديو من السيرفر المخصص، يرجى المحاولة لاحقاً'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _triggerDownload() async {
    if (_matchedCee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Text('العمل غير متوفر للتنزيل حالياً في السيرفر'),
          backgroundColor: Colors.orange.shade900,
        ),
      );
      return;
    }

    String targetId = _matchedCee!['nb'].toString();
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
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text('بدأ تنزيل $title بنجاح!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final originalName = widget.media['original_name'] ?? widget.media['original_title'] ?? '';
    final arabicTitle = widget.media['title'] ?? widget.media['name'] ?? '';
    final title = _displayEnglishTitle.isNotEmpty ? _displayEnglishTitle : (originalName.isNotEmpty ? originalName : arabicTitle);
    
    final poster = widget.media['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}' : '';
    final score = (widget.media['vote_average'] ?? 8.0).toStringAsFixed(1);
    final story = widget.media['overview'] ?? 'لا يوجد وصف متاح حالياً.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, shape: BoxShape.circle),
                child: Icon(_isWatchLater ? Icons.watch_later_rounded : Icons.watch_later_outlined, color: const Color(0xFF00F0FF), size: 19),
              ),
              onPressed: _toggleWatchLater,
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, shape: BoxShape.circle),
                child: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B), size: 19),
              ),
              onPressed: () async {
                final state = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
                setState(() => _isFav = state);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: poster.isNotEmpty ? Image.network(poster, width: 110, height: 160, fit: BoxFit.cover) : Container(width: 110, height: 160, color: Colors.grey.shade900),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          if (arabicTitle != title) ...[
                            const SizedBox(height: 2),
                            Text(arabicTitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                child: Text('⭐ $score', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 11)),
                              ),
                              const SizedBox(width: 8),
                              if (_isMatching)
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F0FF)))
                              else if (_matchedCee != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                  child: const Text('متوفر بسينمانا ✅', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 10)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                  child: const Text('متوفر بالسيرفر الدولي ⚡', style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 10)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF10B981)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: (_isMatching || _matchedCee == null) ? null : _triggerDownload,
                            icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981), size: 16),
                            label: const Text('تنزيل في التطبيق', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isMatching ? Colors.grey.shade800 : const Color(0xFFE50914),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 6,
                    shadowColor: const Color(0xFFE50914).withOpacity(0.5),
                  ),
                  onPressed: (_isMatching || _isLaunching) ? null : () => _play(1),
                  icon: (_isMatching || _isLaunching)
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: Text(
                    _isMatching
                        ? 'جاري تجهيز السيرفر المخصص...'
                        : (_isSeries ? 'مشاهدة الحلقة الأولى' : 'مشاهدة العمل الآن'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(story, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),

              if (_isSeries) ...[
                const SizedBox(height: 20),
                if (_seasons.isNotEmpty) ...[
                  const Text('المواسم:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
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
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE50914) : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFE50914).withOpacity(0.4), blurRadius: 6)] : null,
                            ),
                            child: Text('الموسم $sNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text('الحلقات (${_episodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final epNum = i + 1;
                          return InkWell(
                            onTap: _isMatching ? null : () => _play(epNum),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Center(
                                child: Text('$epNum', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white)),
                              ),
                            ),
                          );
                        },
                      ),
              ],

              if (_similarMedia.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('أعمال قد تعجبك (مشابهة):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 145,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _similarMedia.length,
                    itemBuilder: (ctx, i) {
                      final item = _similarMedia[i];
                      final pPath = item['poster_path'];
                      return InkWell(
                        onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                        child: Container(
                          width: 95,
                          margin: const EdgeInsets.only(left: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: pPath != null ? Image.network(pPath.startsWith('http') ? pPath : 'https://image.tmdb.org/t/p/w200$pPath', fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
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
// 8. المشغل العالمي المطور مع دعم الهيدرز الديناميكي وإيماءات اللمس
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final String serverSourceName;
  final VoidCallback? onNextEpisode;
  final bool isLocalFile;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.serverSourceName = 'High-Speed Server',
    this.onNextEpisode,
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
  String _activeQualityName = 'تلقائي (Auto)';
  bool _isAutoBitrate = true;

  double _volumeIndicator = 0.5;
  bool _showVolumeIndicator = false;
  Timer? _indicatorTimer;

  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18.0;
  Color _subtitleTextColor = Colors.white;
  Color _subtitleBgColor = Colors.black87;
  double _subtitleBottomPadding = 75.0;
  double _subtitleOffsetSeconds = 0.0;
  List<Subtitle> _parsedSubtitles = [];
  String _activeSubtitleText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentStreamUrl = widget.videoUrl;
    _init();
    if (!widget.isLocalFile) _fetchSubs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveCurrentPosition();
    }
  }

  void _saveCurrentPosition() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      final pos = _videoPlayerController!.value.position.inSeconds;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('resume_pos_${widget.mediaId}', pos);
      });
    }
  }

  void _fetchSubs() async {
    try {
      final res = await http.get(Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final subUrl = info['arTranslationFilePath']?.toString() ?? info['arTranslationFile']?.toString() ?? '';
        if (subUrl.isNotEmpty) {
          final sRes = await http.get(Uri.parse(subUrl), headers: StreamService.stealthHeaders);
          if (sRes.statusCode == 200 && mounted) {
            setState(() => _parsedSubtitles = _parseSubtitles(utf8.decode(sRes.bodyBytes, allowMalformed: true)));
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

  void _init({int startAtSecond = 0}) async {
    final oldVideo = _videoPlayerController;
    final oldChewie = _chewieController;

    setState(() => _isReady = false);

    oldVideo?.removeListener(_updateSubsAndProgress);
    oldChewie?.dispose();
    await oldVideo?.dispose();

    final Map<String, String> resolvedHeaders = _currentStreamUrl.contains('cee.buzz')
        ? StreamService.stealthHeaders
        : {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'};

    _videoPlayerController = widget.isLocalFile
        ? VideoPlayerController.file(File(_currentStreamUrl))
        : VideoPlayerController.networkUrl(Uri.parse(_currentStreamUrl), httpHeaders: resolvedHeaders);

    await _videoPlayerController!.initialize();

    final prefs = await SharedPreferences.getInstance();
    int resumePos = startAtSecond > 0 ? startAtSecond : (prefs.getInt('resume_pos_${widget.mediaId}') ?? 0);
    if (resumePos > 5 && resumePos < _videoPlayerController!.value.duration.inSeconds - 10) {
      await _videoPlayerController!.seekTo(Duration(seconds: resumePos));
    }

    _videoPlayerController!.addListener(_updateSubsAndProgress);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: false,
      allowFullScreen: true,
      showOptions: false,
    );

    if (mounted) setState(() => _isReady = true);
  }

  String _findSubtitleBinary(Duration pos) {
    int low = 0;
    int high = _parsedSubtitles.length - 1;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      final item = _parsedSubtitles[mid];
      if (pos < item.start) {
        high = mid - 1;
      } else if (pos > item.end) {
        low = mid + 1;
      } else {
        return item.text;
      }
    }
    return '';
  }

  void _updateSubsAndProgress() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    final pos = _videoPlayerController!.value.position;

    if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
      final adjustedPos = pos + Duration(milliseconds: (_subtitleOffsetSeconds * 1000).round());
      final text = _findSubtitleBinary(adjustedPos);
      if (text != _activeSubtitleText && mounted) setState(() => _activeSubtitleText = text);
    } else if (_activeSubtitleText.isNotEmpty && mounted) {
      setState(() => _activeSubtitleText = '');
    }

    if (pos.inSeconds % 5 == 0) {
      _saveCurrentPosition();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final delta = details.primaryDelta ?? 0;
    _volumeIndicator = (_volumeIndicator - (delta / constraints.maxHeight)).clamp(0.0, 1.0);
    _videoPlayerController?.setVolume(_volumeIndicator);

    setState(() => _showVolumeIndicator = true);
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
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
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F0FF), size: 20),
              ),
              title: const Text('تلقائي (Auto) - ذكي حسب سرعة الإنترنت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: _isAutoBitrate ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00F0FF)) : null,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isAutoBitrate = true;
                  _activeQualityName = 'تلقائي (Auto)';
                });
              },
            ),
            const Divider(color: Colors.white12),
            ...widget.qualities.map((q) {
              final res = q['resolution'] ?? '720p';
              final url = q['url'] ?? '';
              final isCurrent = url == _currentStreamUrl && !_isAutoBitrate;

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                  child: const Icon(Icons.hd_outlined, color: Colors.white70, size: 20),
                ),
                title: Text(res, style: TextStyle(color: isCurrent ? const Color(0xFF00F0FF) : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                trailing: isCurrent ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00F0FF)) : null,
                onTap: () {
                  Navigator.pop(context);
                  if (url != _currentStreamUrl && url.isNotEmpty) {
                    final currentSec = _videoPlayerController?.value.position.inSeconds ?? 0;
                    setState(() {
                      _isAutoBitrate = false;
                      _activeQualityName = res;
                      _currentStreamUrl = url;
                    });
                    _init(startAtSecond: currentSec);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('تشغيل الترجمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  value: _subtitlesEnabled,
                  onChanged: (v) {
                    setSheet(() => _subtitlesEnabled = v);
                    setState(() => _subtitlesEnabled = v);
                  },
                ),
                const SizedBox(height: 8),
                Text('مزامنة الصوت والترجمة: ${_subtitleOffsetSeconds.toStringAsFixed(1)} ثانية', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Slider(
                  value: _subtitleOffsetSeconds, min: -5.0, max: 5.0, divisions: 20,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (v) {
                    setSheet(() => _subtitleOffsetSeconds = v);
                    setState(() => _subtitleOffsetSeconds = v);
                  },
                ),
                const SizedBox(height: 6),
                const Text('حجم الخط:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Slider(
                  value: _subtitleFontSize, min: 14, max: 32, divisions: 9,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (v) {
                    setSheet(() => _subtitleFontSize = v);
                    setState(() => _subtitleFontSize = v);
                  },
                ),
                const Text('ارتفاع الترجمة عن أسفل الشاشة:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Slider(
                  value: _subtitleBottomPadding, min: 30, max: 140, divisions: 11,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (v) {
                    setSheet(() => _subtitleBottomPadding = v);
                    setState(() => _subtitleBottomPadding = v);
                  },
                ),
                Row(
                  children: [
                    const Text('لون الخط: ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    _colorChip(Colors.white, () { setSheet(() => _subtitleTextColor = Colors.white); setState(() => _subtitleTextColor = Colors.white); }),
                    _colorChip(const Color(0xFFFDE047), () { setSheet(() => _subtitleTextColor = const Color(0xFFFDE047)); setState(() => _subtitleTextColor = const Color(0xFFFDE047)); }),
                    _colorChip(const Color(0xFF00F0FF), () { setSheet(() => _subtitleTextColor = const Color(0xFF00F0FF)); setState(() => _subtitleTextColor = const Color(0xFF00F0FF)); }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorChip(Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2)),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentPosition();
    _indicatorTimer?.cancel();
    _videoPlayerController?.removeListener(_updateSubsAndProgress);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return GestureDetector(
              onVerticalDragUpdate: _isLocked ? null : (d) => _onVerticalDragUpdate(d, constraints),
              child: Stack(
                children: [
                  Center(
                    child: (_isReady && _chewieController != null)
                        ? Chewie(controller: _chewieController!)
                        : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
                  ),

                  Positioned(
                    top: 16,
                    left: 70,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 4),
                          Text(widget.serverSourceName, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),

                  if (_showVolumeIndicator)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.black87.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.volume_up_rounded, color: Color(0xFF00F0FF), size: 30),
                            const SizedBox(height: 8),
                            Text('${(_volumeIndicator * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (_subtitlesEnabled && _activeSubtitleText.isNotEmpty)
                    Positioned(
                      bottom: _subtitleBottomPadding,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _subtitleBgColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6)],
                          ),
                          child: Text(_activeSubtitleText, style: TextStyle(color: _subtitleTextColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                    ),

                  if (!_isLocked)
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: const Icon(Icons.high_quality_rounded, color: Color(0xFF00F0FF), size: 22),
                                  tooltip: 'الجودة: $_activeQualityName',
                                  onPressed: _showQualitySheet,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: const Icon(Icons.subtitles_rounded, color: Colors.white, size: 20),
                                  tooltip: 'الترجمة',
                                  onPressed: _openSubtitleSettings,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                                  tooltip: 'قفل الشاشة',
                                  onPressed: () => setState(() => _isLocked = true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                                  tooltip: 'إغلاق المشغل',
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (_isLocked)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFFE50914).withOpacity(0.5), blurRadius: 10)],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                          tooltip: 'إلغاء قفل الشاشة',
                          onPressed: () => setState(() => _isLocked = false),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 9. شاشة مدير التنزيلات
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
    await LocalStorageService.removeItem('downloaded_works_list', item['id'].toString());
    _loadCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final active = DownloadManager.instance.activeDownloads.values.toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('📥 مدير التنزيلات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              const Text('⏳ التنزيلات الجارية:', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00F0FF), fontSize: 14)),
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
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
            ],
            const Text('✅ الأعمال الجاهزة للمشاهدة دون إنترنت:', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981), fontSize: 14)),
            const SizedBox(height: 10),
            ..._completed.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 24),
                ),
                title: Text(e.value['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(e.value['size'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), onPressed: () => _deleteCompleted(e.key)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(mediaId: e.value['id'], title: e.value['title'], videoUrl: e.value['path'], qualities: const [], isLocalFile: true))),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 10. شاشة المشاهدة لاحقاً
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
    final p = AppState.instance.currentProfile;
    final list = await LocalStorageService.getList('watch_later_items_$p');
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('🕒 المشاهدة لاحقاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ),
        body: _items.isEmpty
            ? const Center(child: Text('لا توجد عناصر في قائمة المشاهدة لاحقاً'))
            : GridView.builder(
                padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.58),
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _load()),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: poster.isNotEmpty ? Image.network(poster.startsWith('http') ? poster : 'https://image.tmdb.org/t/p/w342$poster', fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 11. شاشة المفضلة
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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('⭐ قائمة المفضلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ),
        body: _favorites.isEmpty
            ? const Center(child: Text('لا توجد عناصر في المفضلة'))
            : GridView.builder(
                padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.58),
                itemCount: _favorites.length,
                itemBuilder: (ctx, i) {
                  final item = _favorites[i];
                  final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${item['poster_path']}' : '';
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: poster.isNotEmpty ? Image.network(poster.startsWith('http') ? poster : 'https://image.tmdb.org/t/p/w342$poster', fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 12. لوحة تحكم المشرف (Admin Dashboard)
// -------------------------------------------------------------
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
    final recent = List<Map<String, dynamic>>.from(_stats['recent_plays'] ?? []);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('👑 لوحة تحكم المشرف (Admin)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard('المستخدمين المتصلين', '${_stats['active_users'] ?? 0}', Icons.wifi_tethering_rounded, const Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      _statCard('إجمالي المشاهدات', '${_stats['total_views'] ?? 0}', Icons.play_circle_filled_rounded, const Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('🔥 الخريطة الحرارية للمشاهدين (Heatmap):', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: heatmap.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 60, child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (e.value / 10).clamp(0.1, 1.0), color: const Color(0xFFE50914), minHeight: 6))),
                            const SizedBox(width: 10),
                            Text('${e.value}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('📺 أحدث المشاهدات الحية:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...recent.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.live_tv_rounded, color: Color(0xFFE50914)),
                      title: Text(r['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      trailing: Text(r['time'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
