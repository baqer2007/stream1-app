import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'stream_service.dart';

class AppColors {
  static const Color primary = Color(0xFFE50914);
  static const Color primaryDark = Color(0xFFB91C1C);
  static const Color background = Color(0xFF070A10);
  static const Color surface = Color(0xFF101726);
  static const Color surfaceLight = Color(0xFF182234);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white54;
  static const Color textMuted = Colors.white38;
  static const Color star = Color(0xFFFFB800);
  static const Color border = Color(0x1AFFFFFF);
}

class AppRadius {
  static const double card = 16.0;
  static const double chip = 14.0;
  static const double sheet = 24.0;
  static const double button = 24.0;
}

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
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final raw = prefs.getString('${currentProfile}_$key') ?? prefs.getString(key);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<void> setList(String key, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    await prefs.setString('${currentProfile}_$key', jsonEncode(list));
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

  static Future<void> savePlaybackPosition(String id, int positionMs, int durationMs, String title, String poster) async {
    if (durationMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    await prefs.setInt('pos_${currentProfile}_$id', positionMs);

    int totalMinutes = prefs.getInt('stats_minutes_$currentProfile') ?? 0;
    await prefs.setInt('stats_minutes_$currentProfile', totalMinutes + (positionMs > 60000 ? 1 : 0));

    final resumeList = await getList('resume_playback_list');
    resumeList.removeWhere((x) => x['id'] == id);
    if (positionMs < (durationMs - 15000)) {
      resumeList.insert(0, {
        'id': id,
        'position': positionMs,
        'duration': durationMs,
        'title': title,
        'poster': poster,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      if (resumeList.length > 20) resumeList.removeLast();
    }
    await setList('resume_playback_list', resumeList);
  }

  static Future<int> getPlaybackPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    return prefs.getInt('pos_${currentProfile}_$id') ?? prefs.getInt('pos_$id') ?? 0;
  }

  static Future<Set<String>> getWatchedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final list = prefs.getStringList('watched_episodes_${currentProfile}_list') ?? prefs.getStringList('watched_episodes_list') ?? [];
    return list.toSet();
  }

  static Future<void> markEpisodeWatched(String epId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final list = prefs.getStringList('watched_episodes_${currentProfile}_list') ?? [];
    if (!list.contains(epId)) {
      list.add(epId);
      await prefs.setStringList('watched_episodes_${currentProfile}_list', list);
      
      int epCount = prefs.getInt('stats_episodes_$currentProfile') ?? 0;
      await prefs.setInt('stats_episodes_$currentProfile', epCount + 1);
    }
  }

  static Future<bool> isWatchlist(String id) async {
    final list = await getList('user_watchlist');
    return list.any((x) => (x['nb'] ?? x['id'])?.toString() == id);
  }

  static Future<void> toggleWatchlist(Map<String, dynamic> media) async {
    final list = await getList('user_watchlist');
    final id = (media['nb'] ?? media['id'])?.toString();
    final exists = list.any((x) => (x['nb'] ?? x['id'])?.toString() == id);
    if (exists) {
      list.removeWhere((x) => (x['nb'] ?? x['id'])?.toString() == id);
    } else {
      list.insert(0, media);
    }
    await setList('user_watchlist', list);
  }

  static Future<bool> isSubscribedToNotifications(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('subscribed_notifications') ?? [];
    return list.contains(id);
  }

  static Future<void> toggleNotificationSubscription(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('subscribed_notifications') ?? [];
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await prefs.setStringList('subscribed_notifications', list);
  }
}

class ActiveDownload {
  final String id;
  final String title;
  final String url;
  final String poster;
  final String quality;
  double progress;
  int downloadedBytes;
  int totalBytes;
  double speedKbs;
  http.Client? client;
  bool isCancelled = false;

  ActiveDownload({
    required this.id,
    required this.title,
    required this.url,
    required this.poster,
    required this.quality,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedKbs = 0.0,
  });
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final Map<String, ActiveDownload> activeDownloads = {};

  Future<String> getAppStoragePath() async {
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
    required String quality,
  }) async {
    if (activeDownloads.containsKey(targetId)) return;

    final download = ActiveDownload(
      id: targetId,
      title: title,
      url: url,
      poster: poster,
      quality: quality,
    );
    activeDownloads[targetId] = download;
    notifyListeners();

    try {
      final basePath = await getAppStoragePath();
      final safeName = '${targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$quality.mp4';
      final filePath = '$basePath/$safeName';
      final file = File(filePath);

      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = file.lengthSync();
      }

      await LocalStorageService.appendItem('downloaded_works_list', {
        'nb': targetId,
        'title': '$title ($quality)',
        'path': filePath,
        'size': 'قيد التنزيل...',
        'poster': poster,
      });
      notifyListeners();

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
      int lastTimestamp = DateTime.now().millisecondsSinceEpoch;
      int bytesSinceLast = 0;

      await response.stream.listen((chunk) {
        if (download.isCancelled) {
          sink.close();
          return;
        }
        downloadedBytes += chunk.length;
        bytesSinceLast += chunk.length;
        download.downloadedBytes = downloadedBytes;
        sink.add(chunk);

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastTimestamp >= 1000) {
          download.speedKbs = (bytesSinceLast / 1024) / ((now - lastTimestamp) / 1000);
          lastTimestamp = now;
          bytesSinceLast = 0;
        }

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
          'title': '$title ($quality)',
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

class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._();
  AppSettings._();

  int seekDuration = 10;
  bool skipSensitiveScenes = true;
  double subFontSize = 18.0;
  Color subColor = Colors.white;
  bool subHasShadow = true;
  double subBottomPadding = 60.0;
  bool enableDualSubtitles = false;
  int appFilterMode = 0;
  String appLanguage = 'ar';
  String selectedFont = 'Cairo';
  bool autoSmartDownload = false;

  String? userName;
  String? userEmail;
  String activeProfile = 'الرئيسي';
  List<String> userProfiles = ['الرئيسي', 'الأطفال', 'عائلي'];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    seekDuration = p.getInt('player_seek_dur') ?? 10;
    skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
    subFontSize = p.getDouble('player_sub_size') ?? 18.0;
    subBottomPadding = p.getDouble('player_sub_bottom') ?? 60.0;
    enableDualSubtitles = p.getBool('player_dual_sub') ?? false;
    appFilterMode = p.getInt('app_filter_mode') ?? 0;
    appLanguage = p.getString('app_lang') ?? 'ar';
    selectedFont = p.getString('app_font') ?? 'Cairo';
    autoSmartDownload = p.getBool('app_smart_dl') ?? false;
    userName = p.getString('auth_user_name');
    userEmail = p.getString('auth_user_email');
    activeProfile = p.getString('current_active_profile') ?? 'الرئيسي';
    final rawP = p.getStringList('user_profiles_list');
    if (rawP != null) userProfiles = rawP;
  }

  void updateSeek(int sec) async {
    seekDuration = sec;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('player_seek_dur', sec);
  }

  void updateFilterMode(int mode) async {
    appFilterMode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('app_filter_mode', mode);
  }

  void updateLanguage(String lang) async {
    appLanguage = lang;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('app_lang', lang);
  }

  void updateFont(String font) async {
    selectedFont = font;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('app_font', font);
  }

  void updateDualSubtitles(bool val) async {
    enableDualSubtitles = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('player_dual_sub', val);
  }

  void updateSmartDownload(bool val) async {
    autoSmartDownload = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_smart_dl', val);
  }

  void updateSkipScenes(bool val) async {
    skipSensitiveScenes = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('player_skip_sens', val);
  }

  void updateSubStyle({double? size, Color? color, bool? shadow, double? bottomPadding}) async {
    if (size != null) subFontSize = size;
    if (color != null) subColor = color;
    if (shadow != null) subHasShadow = shadow;
    if (bottomPadding != null) subBottomPadding = bottomPadding;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (bottomPadding != null) await p.setDouble('player_sub_bottom', bottomPadding);
    if (size != null) await p.setDouble('player_sub_size', size);
  }

  void resetSubtitles() async {
    subFontSize = 18.0;
    subColor = Colors.white;
    subHasShadow = true;
    subBottomPadding = 60.0;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('player_sub_size', 18.0);
    await p.setDouble('player_sub_bottom', 60.0);
  }

  void login(String name, String email) async {
    userName = name;
    userEmail = email;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('auth_user_name', name);
    await p.setString('auth_user_email', email);
  }

  void logout() async {
    userName = null;
    userEmail = null;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove('auth_user_name');
    await p.remove('auth_user_email');
  }

  void switchProfile(String profile) async {
    activeProfile = profile;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('current_active_profile', profile);
  }

  void addProfile(String profileName) async {
    if (!userProfiles.contains(profileName)) {
      userProfiles.add(profileName);
      notifyListeners();
      final p = await SharedPreferences.getInstance();
      await p.setStringList('user_profiles_list', userProfiles);
    }
  }

  TextTheme getCustomTextTheme() {
    switch (selectedFont) {
      case 'Tajawal':
        return GoogleFonts.tajawalTextTheme(ThemeData.dark().textTheme);
      case 'Almarai':
        return GoogleFonts.almaraiTextTheme(ThemeData.dark().textTheme);
      case 'Changa':
        return GoogleFonts.changaTextTheme(ThemeData.dark().textTheme);
      default:
        return GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
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
    AppSettings.instance.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ONEBR TV',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.background,
          primaryColor: AppColors.primary,
          cardColor: AppColors.surface,
          textTheme: s.getCustomTextTheme(),
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
          ),
        ),
        home: const MainNavigationHolder(),
      ),
    );
  }
}

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreenContent(),
    const CategoriesScreen(),
    const AdvancedSearchScreen(),
    const LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF090D15),
            border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textMuted,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            onTap: (i) => setState(() => _currentIndex = i),
            items: [
              BottomNavigationBarItem(icon: const Icon(Icons.home_filled), label: isAr ? 'الرئيسية' : 'Home'),
              BottomNavigationBarItem(icon: const Icon(Icons.grid_view_rounded), label: isAr ? 'الأقسام' : 'Categories'),
              BottomNavigationBarItem(icon: const Icon(Icons.search_rounded), label: isAr ? 'بحث وفلترة' : 'Search'),
              BottomNavigationBarItem(icon: const Icon(Icons.person_rounded), label: isAr ? 'الحساب والمكتبة' : 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _heroItems = [];
  List<dynamic> _marvelItems = [];
  List<dynamic> _featuredItems = [];
  List<dynamic> _recentItems = [];
  List<dynamic> _infiniteList = [];
  List<Map<String, dynamic>> _resumeList = [];
  final Set<String> _uniqueIds = {};
  int _currentHeroIdx = 0;
  int _page = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    AppSettings.instance.addListener(_onSettingsChanged);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore) {
          _fetchMore();
        }
      }
    });
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);
    _resumeList = await LocalStorageService.getList('resume_playback_list');
    _uniqueIds.clear();

    final level = AppSettings.instance.appFilterMode;

    try {
      final res = await Future.wait([
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 20, level: level),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 20, level: level),
      ]);

      final all = [...res[0], ...res[1]];
      for (var it in all) {
        final id = (it['nb'] ?? it['id'])?.toString();
        if (id != null) _uniqueIds.add(id);
      }

      if (mounted) {
        setState(() {
          _heroItems = all.take(6).toList();
          _marvelItems = all.where((it) {
            final t = (it['ar_title'] ?? it['en_title'] ?? '').toString().toLowerCase();
            return t.contains('iron') || t.contains('thor') || t.contains('avengers') || t.contains('hulk') || t.contains('captain') || t.contains('marvel');
          }).toList();
          if (_marvelItems.isEmpty && all.isNotEmpty) {
            _marvelItems = all.sublist(0, all.length > 8 ? 8 : all.length);
          }

          _featuredItems = all.reversed.take(12).toList();
          _recentItems = all.skip(4).take(12).toList();
          _infiniteList = List.from(all);
          _page = 1;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMore() async {
    setState(() => _isLoadingMore = true);
    final level = AppSettings.instance.appFilterMode;

    final res = await Future.wait([
      StreamService.fetchFeed(isSeries: false, page: _page, perPage: 16, level: level),
      StreamService.fetchFeed(isSeries: true, page: _page, perPage: 16, level: level),
    ]);

    final fresh = [...res[0], ...res[1]];
    final List<dynamic> deduplicated = [];
    for (var it in fresh) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_uniqueIds.contains(id)) {
        _uniqueIds.add(id);
        deduplicated.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _infiniteList.addAll(deduplicated);
        _page++;
        _isLoadingMore = false;
      });
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: MediaDetailScreen(media: item)),
      ),
    ).then((_) async {
      final l = await LocalStorageService.getList('resume_playback_list');
      if (mounted) setState(() => _resumeList = l);
    });
  }

  void _openSectionView(String title, bool isSeries) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullCategoryView(
          title: title,
          isSeriesOnly: isSeries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridCount = screenWidth > 700 ? 5 : 4;
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Text('سينمانا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            Text(isAr ? 'الملف: ${AppSettings.instance.activeProfile}' : 'Profile: ${AppSettings.instance.activeProfile}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadFeed,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_heroItems.isNotEmpty) _buildCarouselBanner(),
                    _buildCinemaFilterButtons(isAr),
                    if (_resumeList.isNotEmpty) _buildResumeSection(isAr),
                    _buildMediaShelf(isAr ? 'عالم مارفل 4K' : 'Marvel 4K Universe', _marvelItems, () => _openSectionView(isAr ? 'عالم مارفل 4K' : 'Marvel 4K', false)),
                    _buildMediaShelf(isAr ? 'الأفلام المميزة' : 'Featured Movies', _featuredItems, () => _openSectionView(isAr ? 'الأفلام المميزة' : 'Featured', false)),
                    _buildMediaShelf(isAr ? 'أُضيف مؤخراً' : 'Recently Added', _recentItems, () => _openSectionView(isAr ? 'أُضيف مؤخراً' : 'Recent', true)),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isAr ? 'استكشف المزيد من الأعمال' : 'Explore More Titles', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          const Icon(Icons.movie_filter_rounded, color: AppColors.primary, size: 18),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridCount,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.56,
                        ),
                        itemCount: _infiniteList.length,
                        itemBuilder: (ctx, i) {
                          final it = _infiniteList[i];
                          final poster = StreamService.extractPoster(it);
                          final t = it['ar_title'] ?? it['en_title'] ?? '';
                          final score = (it['stars'] ?? '7.0').toString();

                          return InkWell(
                            onTap: () => _openDetails(it),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      border: Border.all(color: AppColors.border, width: 0.5),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: AppColors.star, size: 11),
                                    const SizedBox(width: 2),
                                    Text(score, style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    if (_isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                      ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCinemaFilterButtons(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openSectionView(isAr ? 'الأفلام السينمائية' : 'Movies', false),
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.surfaceLight, AppColors.surface]),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_movies_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(isAr ? 'الأفلام' : 'Movies', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _openSectionView(isAr ? 'المسلسلات والأنمي' : 'TV Series', true),
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.surfaceLight, AppColors.surface]),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tv_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(isAr ? 'المسلسلات' : 'Series', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselBanner() {
    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 235,
            viewportFraction: 0.94,
            enlargeCenterPage: true,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            onPageChanged: (idx, _) => setState(() => _currentHeroIdx = idx),
          ),
          items: _heroItems.map((item) {
            final poster = StreamService.extractPoster(item, highRes: true);
            final title = item['ar_title'] ?? item['en_title'] ?? '';

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border, width: 0.5),
                image: poster.isNotEmpty ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover) : null,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x66000000), Color(0xF0070A10)],
                        stops: [0.2, 0.65, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14, right: 16, left: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              const Text('4K Ultra HD', style: TextStyle(color: AppColors.star, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          onPressed: () => _openDetails(item),
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          label: Text(AppSettings.instance.appLanguage == 'ar' ? 'شاهد الآن' : 'Watch', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _heroItems.asMap().entries.map((entry) {
            final isSel = entry.key == _currentHeroIdx;
            return Container(
              width: isSel ? 16 : 6,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSel ? AppColors.primary : Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildResumeSection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(isAr ? 'متابعة المشاهدة' : 'Continue Watching', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 115,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _resumeList.length,
            itemBuilder: (ctx, i) {
              final it = _resumeList[i];
              final progress = (it['position'] / it['duration']).clamp(0.0, 1.0);

              return GestureDetector(
                onTap: () {
                  StreamService.getVideoSource(it['id']).then((src) {
                    if (src != null && mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            mediaId: it['id'],
                            title: it['title'] ?? '',
                            videoUrl: src['video_url'],
                            qualities: List<Map<String, dynamic>>.from(src['qualities'] ?? []),
                          ),
                        ),
                      );
                    }
                  });
                },
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border, width: 0.5),
                    image: it['poster'].toString().isNotEmpty ? DecorationImage(image: NetworkImage(it['poster']), fit: BoxFit.cover) : null,
                  ),
                  child: Stack(
                    children: [
                      Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), color: Colors.black45)),
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 32)),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                          child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
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

  Widget _buildMediaShelf(String title, List<dynamic> items, VoidCallback onMore) {
    if (items.isEmpty) return const SizedBox();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(AppSettings.instance.appLanguage == 'ar' ? 'المزيد' : 'More', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final it = items[i];
              final poster = StreamService.extractPoster(it);
              final t = it['ar_title'] ?? it['en_title'] ?? '';
              final score = (it['stars'] ?? '7.0').toString();

              return Container(
                width: 105,
                margin: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: () => _openDetails(it),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                          const SizedBox(width: 2),
                          Text(score, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
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
}

// =========================================================================
// شاشة البحث والفلترة المباشرة السلسة
// =========================================================================
class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _results = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _isSearching = false;

  String _filterType = 'all';
  String _filterGenre = 'all';
  double _minScore = 0.0;

  final List<Map<String, String>> _genres = [
    {'key': 'all', 'ar': 'كل التصنيفات'},
    {'key': 'horror', 'ar': 'رعب'},
    {'key': 'action', 'ar': 'أكشن'},
    {'key': 'comedy', 'ar': 'كوميديا'},
    {'key': 'drama', 'ar': 'دراما'},
    {'key': 'animation', 'ar': 'أنمي ورسوم'},
    {'key': 'sci-fi', 'ar': 'خيال علمي'},
  ];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  void _loadRecents() async {
    final list = await LocalStorageService.getList('recent_search_history');
    if (mounted) setState(() => _recentSearches = list);
  }

  void _search() async {
    final q = _searchCtrl.text.trim();
    setState(() => _isSearching = true);
    final level = AppSettings.instance.appFilterMode;

    List<dynamic> baseList = [];
    if (q.isNotEmpty) {
      baseList = await StreamService.searchContent(q, level: level);
    } else if (_filterGenre != 'all') {
      baseList = await StreamService.fetchByCategoryName(_filterGenre, page: 0, level: level);
    } else {
      final res = await Future.wait([
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 25, level: level),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 25, level: level),
      ]);
      baseList = [...res[0], ...res[1]];
    }

    final filtered = baseList.where((item) {
      final isSeries = (item['is_series_fixed'] == true) || (item['season'] != null && item['season'].toString() != '0');
      if (_filterType == 'movie' && isSeries) return false;
      if (_filterType == 'series' && !isSeries) return false;

      final score = double.tryParse((item['stars'] ?? '0').toString()) ?? 0.0;
      if (score < _minScore) return false;

      return true;
    }).toList();

    if (mounted) {
      setState(() {
        _results = filtered;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: isAr ? 'ابحث عن أفلام، مسلسلات...' : 'Search movies, series...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        body: Column(
          children: [
            // شريط الفلاتر المباشر في نفس الشاشة لسهولة الوصول
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppColors.surface,
              child: Column(
                children: [
                  Row(
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(label: const Text('الكل', style: TextStyle(fontSize: 11)), selected: _filterType == 'all', onSelected: (_) { setState(() => _filterType = 'all'); _search(); }),
                          ChoiceChip(label: const Text('أفلام', style: TextStyle(fontSize: 11)), selected: _filterType == 'movie', onSelected: (_) { setState(() => _filterType = 'movie'); _search(); }),
                          ChoiceChip(label: const Text('مسلسلات', style: TextStyle(fontSize: 11)), selected: _filterType == 'series', onSelected: (_) { setState(() => _filterType = 'series'); _search(); }),
                        ],
                      ),
                      const Spacer(),
                      DropdownButton<String>(
                        dropdownColor: AppColors.surfaceLight,
                        value: _filterGenre,
                        underline: const SizedBox(),
                        items: _genres.map((g) => DropdownMenuItem(value: g['key'], child: Text(g['ar']!, style: const TextStyle(color: Colors.white, fontSize: 12)))).toList(),
                        onChanged: (v) {
                          setState(() => _filterGenre = v!);
                          _search();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _results.isNotEmpty
                      ? GridView.builder(
                          padding: const EdgeInsets.all(10),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, childAspectRatio: 0.56, crossAxisSpacing: 8, mainAxisSpacing: 10),
                          itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final item = _results[i];
                            final poster = StreamService.extractPoster(item);
                            return InkWell(
                              onTap: () {
                                LocalStorageService.appendItem('recent_search_history', item, maxLength: 20);
                                _loadRecents();
                                Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)));
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: AppColors.surface),
                              ),
                            );
                          },
                        )
                      : _buildRecentSearchesList(isAr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearchesList(bool isAr) {
    if (_recentSearches.isEmpty) {
      return Center(child: Text(isAr ? 'ابحث عن أفلامك المفضلة وسجل البحث سيظهر هنا' : 'Search for titles to see history here', style: const TextStyle(color: Colors.white38, fontSize: 12)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(isAr ? 'عمليات البحث الأخيرة' : 'Recent Searches', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            InkWell(
              onTap: () async {
                await LocalStorageService.setList('recent_search_history', []);
                _loadRecents();
              },
              child: Text(isAr ? 'مسح السجل' : 'Clear', style: const TextStyle(color: AppColors.primary, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recentSearches.map((item) {
          final poster = StreamService.extractPoster(item);
          final title = item['ar_title'] ?? item['en_title'] ?? '';
          final year = item['year']?.toString() ?? '2024';
          final score = (item['stars'] ?? '7.5').toString();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: poster.isNotEmpty ? Image.network(poster, width: 45, height: 65, fit: BoxFit.cover) : Container(width: 45, height: 65, color: AppColors.surface),
            ),
            title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text('$year • سينما • IMDb $score', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white24, size: 14),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
          );
        }),
      ],
    );
  }
}

// =========================================================================
// شاشة تفاصيل العمل
// =========================================================================
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunching = false;
  Map<int, List<dynamic>> _seasonsMap = {};
  int _selectedSeason = 1;
  Set<String> _watchedEpisodes = {};
  bool _isSeries = false;
  bool _isWatchlist = false;
  bool _isSubscribed = false;
  Map<String, dynamic> _extendedInfo = {};
  List<dynamic> _similarMedia = [];

  @override
  void initState() {
    super.initState();
    _isSeries = (widget.media['is_series_fixed'] == true) || (widget.media['season'] != null && widget.media['season'].toString() != '0');
    _loadState();
    _loadFullData();
    _loadSimilar();
    if (_isSeries) _loadEpisodes();
  }

  void _loadState() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final watched = await LocalStorageService.getWatchedEpisodes();
    final wl = await LocalStorageService.isWatchlist(id);
    final sub = await LocalStorageService.isSubscribedToNotifications(id);
    if (mounted) {
      setState(() {
        _watchedEpisodes = watched;
        _isWatchlist = wl;
        _isSubscribed = sub;
      });
    }
  }

  void _loadFullData() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final info = await StreamService.getVideoExtendedInfo(id);
    if (mounted) setState(() => _extendedInfo = info);
  }

  void _loadSimilar() async {
    final level = AppSettings.instance.appFilterMode;
    final res = await StreamService.fetchFeed(isSeries: _isSeries, page: 0, perPage: 12, level: level);
    final currentId = (widget.media['nb'] ?? widget.media['id'])?.toString();
    if (mounted) {
      setState(() {
        _similarMedia = res.where((it) => (it['nb'] ?? it['id'])?.toString() != currentId).take(8).toList();
      });
    }
  }

  void _loadEpisodes() async {
    final seriesId = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final eps = await StreamService.getSeriesEpisodes(seriesId);

    final Map<int, List<dynamic>> seasons = {};
    for (var ep in eps) {
      final sNum = int.tryParse(ep['season']?.toString() ?? '1') ?? 1;
      seasons.putIfAbsent(sNum, () => []).add(ep);
    }

    if (mounted) {
      setState(() {
        _seasonsMap = seasons.isNotEmpty ? seasons : {1: eps};
        _selectedSeason = _seasonsMap.keys.first;
      });
    }
  }

  void _shareMedia() async {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final id = widget.media['nb'] ?? widget.media['id'] ?? '';
    final text = 'شاهد $title بجودة عالية عبر ONEBR TV!\nhttps://onebr.tv/watch/$id';
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط العمل بنجاح')));
      }
    }
  }

  void _playTrailer() {
    final trailer = _extendedInfo['trailer']?.toString() ?? widget.media['trailer']?.toString() ?? '';
    if (trailer.isNotEmpty && trailer.startsWith('http')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: 'trailer',
            title: 'الإعلان: ${widget.media['ar_title'] ?? ''}',
            videoUrl: trailer,
            qualities: const [],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الإعلان الترويجي الرسمي غير متوفر لهذا العمل')));
    }
  }

  void _playEpisode(dynamic ep, int idx) async {
    setState(() => _isLaunching = true);
    final targetId = (ep['nb'] ?? ep['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final src = await StreamService.getVideoSource(targetId);
    final sub = await StreamService.getVideoExtendedInfo(targetId);

    await LocalStorageService.markEpisodeWatched(targetId);
    _loadState();
    setState(() => _isLaunching = false);

    if (AppSettings.instance.autoSmartDownload && idx < (_seasonsMap[_selectedSeason]?.length ?? 0)) {
      final nextEp = _seasonsMap[_selectedSeason]![idx];
      final nextId = (nextEp['nb'] ?? nextEp['id']).toString();
      StreamService.getVideoSource(nextId).then((nextSrc) {
        if (nextSrc != null) {
          DownloadManager.instance.startDownload(
            targetId: nextId,
            title: '$title - حلقة ${idx + 1}',
            url: nextSrc['video_url'],
            poster: StreamService.extractPoster(widget.media),
            quality: '720p',
          );
        }
      });
    }

    if (src != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: title,
            subtitleTextHeader: 'الموسم $_selectedSeason - الحلقة $idx',
            videoUrl: src['video_url'],
            subtitleUrl: sub['arTranslationFilePath']?.toString() ?? '',
            secondarySubtitleUrl: sub['enTranslationFilePath']?.toString() ?? '',
            qualities: List<Map<String, dynamic>>.from(src['qualities'] ?? []),
            episodes: _seasonsMap[_selectedSeason] ?? [],
            currentEpIndex: idx,
            poster: StreamService.extractPoster(widget.media),
            onEpisodeChanged: (newId) {
              LocalStorageService.markEpisodeWatched(newId);
              _loadState();
            },
          ),
        ),
      );
    }
  }

  void _playMovie() async {
    setState(() => _isLaunching = true);
    final targetId = (widget.media['nb'] ?? widget.media['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final src = await StreamService.getVideoSource(targetId);
    final sub = await StreamService.getVideoExtendedInfo(targetId);
    setState(() => _isLaunching = false);

    if (src != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: title,
            videoUrl: src['video_url'],
            subtitleUrl: sub['arTranslationFilePath']?.toString() ?? '',
            secondarySubtitleUrl: sub['enTranslationFilePath']?.toString() ?? '',
            qualities: List<Map<String, dynamic>>.from(src['qualities'] ?? []),
            poster: StreamService.extractPoster(widget.media),
          ),
        ),
      );
    }
  }

  void _showDownloadQualityPicker(String targetId, String title, String poster) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (_) => FutureBuilder<Map<String, dynamic>?>(
        future: StreamService.getVideoSource(targetId),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }
          final qualities = snap.data?['qualities'] as List? ?? [];
          if (qualities.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('لا تتوفر روابط تنزيل مباشرة', style: TextStyle(color: Colors.white70))),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر جودة التنزيل المتاحة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...qualities.map((q) {
                  final res = q['resolution'] ?? '720p';
                  final url = q['url'] ?? '';
                  return ListTile(
                    leading: const Icon(Icons.video_file_rounded, color: AppColors.primary),
                    title: Text('دقة $res', style: const TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.download_rounded, color: Colors.white70),
                    onTap: () {
                      Navigator.pop(context);
                      DownloadManager.instance.startDownload(
                        targetId: targetId,
                        title: title,
                        url: url,
                        poster: poster,
                        quality: res,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بدأ التنزيل بدقة $res')));
                    },
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = StreamService.extractPoster(widget.media, highRes: true);
    final story = _extendedInfo['ar_content'] ?? widget.media['ar_content'] ?? widget.media['en_content'] ?? '';
    final score = (_extendedInfo['stars'] ?? widget.media['stars'] ?? '7.9').toString();
    final year = widget.media['year']?.toString() ?? '2024';
    final rateCount = (_extendedInfo['rate'] ?? widget.media['rate'] ?? '4818').toString();
    final currentEpisodes = _seasonsMap[_selectedSeason] ?? [];
    final id = (widget.media['nb'] ?? widget.media['id']).toString();
    final rawCats = widget.media['categories'];
    final List<dynamic> catList = rawCats is List ? rawCats : [];

    return Directionality(
      textDirection: AppSettings.instance.appLanguage == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 480,
              pinned: true,
              backgroundColor: AppColors.background,
              leading: IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
              actions: [
                IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: _shareMedia),
                if (_isSeries)
                  IconButton(
                    icon: Icon(_isSubscribed ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: _isSubscribed ? AppColors.primary : Colors.white),
                    onPressed: () async {
                      await LocalStorageService.toggleNotificationSubscription(id);
                      _loadState();
                    },
                  ),
                IconButton(
                  icon: Icon(_isWatchlist ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _isWatchlist ? AppColors.primary : Colors.white),
                  onPressed: () async {
                    await LocalStorageService.toggleWatchlist(widget.media);
                    _loadState();
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster.isNotEmpty) Image.network(poster, fit: BoxFit.cover) else Container(color: AppColors.surface),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black45, Colors.transparent, Color(0xCC070A10), AppColors.background],
                          stops: [0.0, 0.4, 0.75, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12, left: 16, right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(AppRadius.chip)),
                                child: Text('IMDb $score', style: const TextStyle(color: AppColors.star, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Text('$year • ${_isSeries ? 'مسلسل' : 'فيلم'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              InkWell(
                                onTap: () async {
                                  await LocalStorageService.toggleWatchlist(widget.media);
                                  _loadState();
                                },
                                child: Column(
                                  children: [
                                    Icon(_isWatchlist ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 24),
                                    const SizedBox(height: 4),
                                    const Text('المشاهدة لاحقاً', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 34),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                                ),
                                onPressed: _isLaunching ? null : () => _isSeries && currentEpisodes.isNotEmpty ? _playEpisode(currentEpisodes.first, 1) : _playMovie(),
                                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                                label: const Text('شاهد الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                              const SizedBox(width: 34),
                              InkWell(
                                onTap: () => _showDownloadQualityPicker(id, title, poster),
                                child: const Column(
                                  children: [
                                    Icon(Icons.download_rounded, color: Colors.white, size: 24),
                                    SizedBox(height: 4),
                                    Text('تحميل', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (catList.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: catList.map((c) {
                          final name = c['ar_title'] ?? c['en_title'] ?? '';
                          return Chip(
                            backgroundColor: AppColors.surfaceLight,
                            label: Text(name.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 12),

                    InkWell(
                      onTap: _playTrailer,
                      child: Row(
                        children: const [
                          Icon(Icons.play_circle_outline_rounded, color: AppColors.primary, size: 22),
                          SizedBox(width: 6),
                          Text('مشاهدة الإعلان الرسمي', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          Spacer(),
                          Text('تشغيل العرض', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (story.isNotEmpty)
                      Text(story, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_alt_outlined, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        Text(rateCount, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(width: 16),
                        const Icon(Icons.thumb_down_alt_outlined, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        const Text('84', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 30),

                    if (_isSeries && _seasonsMap.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الحلقات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (_seasonsMap.keys.length > 1)
                            DropdownButton<int>(
                              dropdownColor: AppColors.surface,
                              value: _selectedSeason,
                              underline: const SizedBox(),
                              items: _seasonsMap.keys.map((s) => DropdownMenuItem(value: s, child: Text('الموسم $s', style: const TextStyle(color: Colors.white, fontSize: 12)))).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedSeason = v);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...currentEpisodes.asMap().entries.map((e) {
                        final ep = e.value;
                        final idx = e.key + 1;
                        final targetId = (ep['nb'] ?? ep['id']).toString();
                        final isWatched = _watchedEpisodes.contains(targetId);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: InkWell(
                            onTap: () => _playEpisode(ep, idx),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward_rounded, color: Colors.white54, size: 20),
                                    onPressed: () => _showDownloadQualityPicker(targetId, '$title - حلقة $idx', poster),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('الحلقة $idx', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                        if (isWatched) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: const [
                                              Icon(Icons.visibility_rounded, color: Colors.greenAccent, size: 14),
                                              SizedBox(width: 4),
                                              Text('تمت المشاهدة', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(AppRadius.chip),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(width: 110, height: 65, color: Colors.black26, child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : null),
                                        Container(
                                          width: 28, height: 28,
                                          decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
                                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],

                    if (_similarMedia.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text('أعمال مقترحة ومشابهة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 175,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _similarMedia.length,
                          itemBuilder: (ctx, i) {
                            final it = _similarMedia[i];
                            final simPoster = StreamService.extractPoster(it);
                            final simTitle = it['ar_title'] ?? it['en_title'] ?? '';

                            return Container(
                              width: 105,
                              margin: const EdgeInsets.only(left: 8),
                              child: InkWell(
                                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                        child: simPoster.isNotEmpty ? Image.network(simPoster, fit: BoxFit.cover, width: double.infinity) : Container(color: AppColors.surface),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(simTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  ],
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
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// مشغل الفيديو المتكامل
// =========================================================================
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String subtitleTextHeader;
  final String videoUrl;
  final String subtitleUrl;
  final String secondarySubtitleUrl;
  final List<Map<String, dynamic>> qualities;
  final List<dynamic> episodes;
  final int currentEpIndex;
  final String poster;
  final Function(String)? onEpisodeChanged;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    this.subtitleTextHeader = '',
    required this.videoUrl,
    this.subtitleUrl = '',
    this.secondarySubtitleUrl = '',
    required this.qualities,
    this.episodes = const [],
    this.currentEpIndex = 1,
    this.poster = '',
    this.onEpisodeChanged,
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
  List<Subtitle> _secondarySubtitles = [];
  String _currentSubText = '';
  String _currentSecondarySubText = '';

  late int _activeEpIndex;
  late String _activeMediaId;
  late String _activeHeader;
  Set<String> _watchedSet = {};

  bool _isLocked = false;
  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showIndicator = false;
  String _indicatorText = '';
  IconData _indicatorIcon = Icons.volume_up;

  bool _showAutoNext = false;
  int _autoNextCountdown = 5;
  Timer? _autoNextTimer;

  @override
  void initState() {
    super.initState();
    _activeEpIndex = widget.currentEpIndex;
    _activeMediaId = widget.mediaId;
    _activeHeader = widget.subtitleTextHeader;
    _loadWatchedState();
    _initPlayer(widget.videoUrl);
    if (widget.subtitleUrl.isNotEmpty) _loadSubs(widget.subtitleUrl, isSecondary: false);
    if (widget.secondarySubtitleUrl.isNotEmpty) _loadSubs(widget.secondarySubtitleUrl, isSecondary: true);
  }

  void _loadWatchedState() async {
    final w = await LocalStorageService.getWatchedEpisodes();
    if (mounted) setState(() => _watchedSet = w);
  }

  void _loadSubs(String url, {required bool isSecondary}) async {
    try {
      final res = await http.get(Uri.parse(url), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final parsed = _parseSrt(utf8.decode(res.bodyBytes, allowMalformed: true));
        setState(() {
          if (isSecondary) {
            _secondarySubtitles = parsed;
          } else {
            _subtitles = parsed;
          }
        });
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

    final savedMs = await LocalStorageService.getPlaybackPosition(_activeMediaId);
    if (savedMs > 0 && savedMs < _controller!.value.duration.inMilliseconds - 5000) {
      await _controller!.seekTo(Duration(milliseconds: savedMs));
    }

    _controller!.play();

    _controller!.addListener(() {
      if (_controller != null && _controller!.value.isInitialized) {
        final pos = _controller!.value.position;
        final dur = _controller!.value.duration;

        if (pos.inSeconds % 5 == 0) {
          LocalStorageService.savePlaybackPosition(_activeMediaId, pos.inMilliseconds, dur.inMilliseconds, widget.title, widget.poster);
        }

        if (_subtitles.isNotEmpty) {
          final sub = _subtitles.firstWhere((s) => pos >= s.start && pos <= s.end, orElse: () => Subtitle(index: -1, start: Duration.zero, end: Duration.zero, text: ''));
          if (sub.text != _currentSubText && mounted) {
            setState(() => _currentSubText = sub.text);
          }
        }

        if (AppSettings.instance.enableDualSubtitles && _secondarySubtitles.isNotEmpty) {
          final sub2 = _secondarySubtitles.firstWhere((s) => pos >= s.start && pos <= s.end, orElse: () => Subtitle(index: -1, start: Duration.zero, end: Duration.zero, text: ''));
          if (sub2.text != _currentSecondarySubText && mounted) {
            setState(() => _currentSecondarySubText = sub2.text);
          }
        }

        if (widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length) {
          final remaining = dur.inSeconds - pos.inSeconds;
          if (remaining <= 30 && remaining > 0 && !_showAutoNext) {
            _triggerAutoNext();
          }
        }
      }
      if (mounted) setState(() {});
    });

    _startTimer();
    if (mounted) setState(() => _isReady = true);
  }

  void _triggerAutoNext() {
    _showAutoNext = true;
    _autoNextCountdown = 5;
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_autoNextCountdown > 1) {
        if (mounted) setState(() => _autoNextCountdown--);
      } else {
        t.cancel();
        if (mounted && _showAutoNext) {
          _playNextEpisode();
        }
      }
    });
  }

  void _playNextEpisode() {
    _autoNextTimer?.cancel();
    setState(() => _showAutoNext = false);
    if (_activeEpIndex < widget.episodes.length) {
      final nextEp = widget.episodes[_activeEpIndex];
      _switchEpisode(nextEp, _activeEpIndex + 1);
    }
  }

  void _switchEpisode(dynamic epData, int epIdx) async {
    final epId = (epData['nb'] ?? epData['id']).toString();
    setState(() {
      _isReady = false;
      _activeEpIndex = epIdx;
      _activeMediaId = epId;
      _activeHeader = 'الحلقة $epIdx';
      _showAutoNext = false;
    });

    final source = await StreamService.getVideoSource(epId);
    final sub = await StreamService.getVideoExtendedInfo(epId);

    await LocalStorageService.markEpisodeWatched(epId);
    widget.onEpisodeChanged?.call(epId);
    _loadWatchedState();

    if (source != null) {
      _initPlayer(source['video_url']);
      final path = sub['arTranslationFilePath']?.toString() ?? '';
      if (path.isNotEmpty) _loadSubs(path, isSecondary: false);
      final pathEn = sub['enTranslationFilePath']?.toString() ?? '';
      if (pathEn.isNotEmpty) _loadSubs(pathEn, isSecondary: true);
    }
  }

  void _castToTv() async {
    final url = widget.videoUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _startTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && !_isLocked) _startTimer();
  }

  String _formatTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _autoNextTimer?.cancel();
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

  void _handleVerticalDrag(DragUpdateDetails details, BoxConstraints constraints) {
    if (_isLocked) return;
    final isRightSide = details.globalPosition.dx > constraints.maxWidth / 2;
    final delta = -details.primaryDelta! / constraints.maxHeight;

    setState(() {
      _showIndicator = true;
      if (isRightSide) {
        _volumeLevel = (_volumeLevel + delta).clamp(0.0, 1.0);
        _controller?.setVolume(_volumeLevel);
        _indicatorIcon = _volumeLevel == 0 ? Icons.volume_off : Icons.volume_up;
        _indicatorText = '${(_volumeLevel * 100).toInt()}%';
      } else {
        _brightnessLevel = (_brightnessLevel + delta).clamp(0.1, 1.0);
        _indicatorIcon = Icons.brightness_6;
        _indicatorText = '${(_brightnessLevel * 100).toInt()}%';
      }
    });

    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return GestureDetector(
              onTap: _toggleControls,
              onVerticalDragUpdate: (d) => _handleVerticalDrag(d, constraints),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: (_isReady && _controller != null)
                        ? SizedBox.expand(
                            child: FittedBox(
                              fit: _videoFit,
                              child: SizedBox(
                                width: _controller!.value.size.width,
                                height: _controller!.value.size.height,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                          )
                        : const CircularProgressIndicator(color: AppColors.primary),
                  ),

                  if (_showIndicator)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_indicatorIcon, color: Colors.white, size: 28),
                            const SizedBox(width: 10),
                            Text(_indicatorText, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (settings.enableDualSubtitles && _currentSecondarySubText.isNotEmpty)
                    Positioned(
                      top: 70, left: 20, right: 20,
                      child: Center(
                        child: Text(
                          _currentSecondarySubText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                        ),
                      ),
                    ),

                  if (_currentSubText.isNotEmpty)
                    Positioned(
                      bottom: settings.subBottomPadding, left: 20, right: 20,
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

                  if (_showAutoNext && widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length)
                    Positioned(
                      bottom: 85, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Text('الحلقة التالية خلال $_autoNextCountdown ث', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                              onPressed: _playNextEpisode,
                              child: const Text('تشغيل الآن', style: TextStyle(fontSize: 11)),
                            ),
                          ],
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
                                if (_activeHeader.isNotEmpty)
                                  Text(_activeHeader, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(icon: const Icon(Icons.cast_rounded, color: Colors.white), onPressed: _castToTv),
                                IconButton(
                                  icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
                                  onPressed: () => setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: IconButton(
                        iconSize: 52,
                        icon: Icon(_controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                        onPressed: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =========================================================================
// شاشة الأقسام والتصنيفات
// =========================================================================
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  final List<Map<String, dynamic>> _allCategories = const [
    {'key': 'horror', 'ar': 'رعب وتشويق', 'icon': Icons.nights_stay_rounded},
    {'key': 'action', 'ar': 'أكشن وحركة', 'icon': Icons.flash_on_rounded},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'icon': Icons.animation_rounded},
    {'key': 'comedy', 'ar': 'كوميديا وضحك', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'key': 'sci-fi', 'ar': 'خيال علمي وفضاء', 'icon': Icons.rocket_launch_rounded},
    {'key': 'drama', 'ar': 'دراما وقصص واقعية', 'icon': Icons.theater_comedy_rounded},
    {'key': 'romance', 'ar': 'رومانسية وحب', 'icon': Icons.favorite_rounded},
    {'key': 'crime', 'ar': 'جريمة وتحقيق', 'icon': Icons.local_police_rounded},
    {'key': 'adventure', 'ar': 'مغامرات واستكشاف', 'icon': Icons.explore_rounded},
    {'key': 'thriller', 'ar': 'إثارة وغموض', 'icon': Icons.psychology_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('أقسام وتصنيفات المنصة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allCategories.length,
        itemBuilder: (ctx, i) {
          final cat = _allCategories[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: ListTile(
              leading: Icon(cat['icon'], color: AppColors.primary),
              title: Text(cat['ar'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FullCategoryView(title: cat['ar'], categoryEn: cat['key'])),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class FullCategoryView extends StatefulWidget {
  final String title;
  final bool isSeriesOnly;
  final String? categoryEn;

  const FullCategoryView({super.key, required this.title, this.isSeriesOnly = false, this.categoryEn});

  @override
  State<FullCategoryView> createState() => _FullCategoryViewState();
}

class _FullCategoryViewState extends State<FullCategoryView> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<dynamic> _items = [];
  final Set<String> _unique = {};
  int _page = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
        if (!_isLoading) _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    List<dynamic> fresh = [];
    final level = AppSettings.instance.appFilterMode;

    if (widget.categoryEn != null) {
      fresh = await StreamService.fetchByCategoryName(widget.categoryEn!, page: _page, level: level);
    } else {
      fresh = await StreamService.fetchFeed(isSeries: widget.isSeriesOnly, page: _page, perPage: 28, level: level);
    }

    final List<dynamic> deduplicated = [];
    for (var it in fresh) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_unique.contains(id)) {
        _unique.add(id);
        deduplicated.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _items.addAll(deduplicated);
        _page++;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;

    return Directionality(
      textDirection: AppSettings.instance.appLanguage == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: GridView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 10,
            childAspectRatio: 0.56,
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
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =========================================================================
// شاشة الحساب والمكتبة المتكاملة
// =========================================================================
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _completed = [];
  List<Map<String, dynamic>> _watchlist = [];

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  int _statMinutes = 0;
  int _statEpisodes = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadData();
    DownloadManager.instance.addListener(_onDownloadUpdated);
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_onDownloadUpdated);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onDownloadUpdated() {
    _loadData();
  }

  void _loadData() async {
    final downloads = await LocalStorageService.getList('downloaded_works_list');
    final wl = await LocalStorageService.getList('user_watchlist');
    final prefs = await SharedPreferences.getInstance();
    final curP = prefs.getString('current_active_profile') ?? 'default';

    if (mounted) {
      setState(() {
        _completed = downloads;
        _watchlist = wl;
        _statMinutes = prefs.getInt('stats_minutes_$curP') ?? 0;
        _statEpisodes = prefs.getInt('stats_episodes_$curP') ?? 0;
      });
    }
  }

  void _cleanCache() async {
    try {
      final tempDir = Directory.systemTemp;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تفريغ الذاكرة المؤقتة بنجاح')));
    } catch (_) {}
  }

  void _showAddProfileDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('إضافة بروفايل جديد', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'اسم الملف')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                AppSettings.instance.addProfile(ctrl.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تسجيل الحساب والمزامنة السحابية', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الاسم المستعار', labelStyle: TextStyle(color: Colors.white54)),
            ),
            TextField(
              controller: _emailCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              if (_nameCtrl.text.isNotEmpty) {
                AppSettings.instance.login(_nameCtrl.text, _emailCtrl.text);
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ وتسجيل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAr ? 'الحساب والمكتبة' : 'Profile & Library'),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تفريغ الكاش',
            icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white70),
            onPressed: _cleanCache,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: isAr ? 'التنزيلات' : 'Downloads'),
            Tab(text: isAr ? 'المفضلة' : 'Watchlist'),
            Tab(text: isAr ? 'الإحصائيات' : 'Stats'),
            Tab(text: isAr ? 'الإعدادات' : 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _completed.isEmpty && DownloadManager.instance.activeDownloads.isEmpty
              ? Center(child: Text(isAr ? 'لا توجد تنزيلات حالياً' : 'No downloads yet', style: const TextStyle(color: Colors.white54)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...DownloadManager.instance.activeDownloads.values.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                              Text('${(d.progress * 100).toInt()}%', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: d.progress, backgroundColor: Colors.white24, color: AppColors.primary),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${d.speedKbs.toStringAsFixed(1)} KB/s', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18), onPressed: () => DownloadManager.instance.cancelDownload(d.id)),
                            ],
                          ),
                        ],
                      ),
                    )),
                    ..._completed.map((it) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.download_done_rounded, color: AppColors.primary),
                        title: Text(it['title'] ?? '', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(it['size'] ?? '', style: const TextStyle(color: Colors.white54)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white38), onPressed: () async {
                          await LocalStorageService.removeItem('downloaded_works_list', it['nb']?.toString() ?? '', idField: 'nb');
                          _loadData();
                        }),
                      ),
                    )),
                  ],
                ),

          _watchlist.isEmpty
              ? Center(child: Text(isAr ? 'لم تقم بحفظ أي عمل بعد' : 'Watchlist is empty', style: const TextStyle(color: Colors.white54)))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, childAspectRatio: 0.56, crossAxisSpacing: 8, mainAxisSpacing: 10),
                  itemCount: _watchlist.length,
                  itemBuilder: (ctx, i) {
                    final item = _watchlist[i];
                    final poster = StreamService.extractPoster(item);
                    return InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _loadData()),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: AppColors.surface),
                      ),
                    );
                  },
                ),

          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.surfaceLight, AppColors.surface]),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 40),
                    const SizedBox(height: 10),
                    Text(isAr ? 'إحصائيات الملف: ${s.activeProfile}' : 'Stats for: ${s.activeProfile}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(color: AppColors.border, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('$_statMinutes', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text(isAr ? 'دقيقة مشاهدة' : 'Minutes Watched', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('$_statEpisodes', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text(isAr ? 'حلقة مكتملة' : 'Completed Eps', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 24, backgroundColor: AppColors.primary, child: Icon(Icons.person, color: Colors.white)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.userName ?? (isAr ? 'مستخدم زائر' : 'Guest User'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(s.userEmail ?? (isAr ? 'المزامنة السحابية غير مفعّلة' : 'Sync disabled'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: s.userName == null ? _showAuthDialog : () => s.logout(),
                      child: Text(s.userName == null ? (isAr ? 'تسجيل' : 'Login') : (isAr ? 'خروج' : 'Logout'), style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              const Text('إدارة الملفات الشخصية (Profiles)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ...s.userProfiles.map((p) => ChoiceChip(
                    label: Text(p),
                    selected: s.activeProfile == p,
                    selectedColor: AppColors.primary,
                    onSelected: (_) {
                      s.switchProfile(p);
                      _loadData();
                    },
                  )),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('إضافة بروفايل'),
                    onPressed: _showAddProfileDialog,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              SwitchListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                secondary: const Icon(Icons.auto_awesome, color: AppColors.primary),
                title: const Text('التنزيل الذكي للحلقات', style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('تنزيل الحلقة التالية ومسح المنتهية تلقائياً', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: s.autoSmartDownload,
                activeColor: AppColors.primary,
                onChanged: (v) => s.updateSmartDownload(v),
              ),
              const SizedBox(height: 12),

              ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                title: Text(isAr ? 'لغة التطبيق' : 'App Language', style: const TextStyle(color: Colors.white, fontSize: 13)),
                trailing: DropdownButton<String>(
                  dropdownColor: AppColors.surface,
                  value: s.appLanguage,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (v) => s.updateLanguage(v!),
                ),
              ),
              const SizedBox(height: 12),

              ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                leading: const Icon(Icons.font_download_rounded, color: AppColors.primary),
                title: Text(isAr ? 'خط التطبيق' : 'App Font', style: const TextStyle(color: Colors.white, fontSize: 13)),
                trailing: DropdownButton<String>(
                  dropdownColor: AppColors.surface,
                  value: s.selectedFont,
                  items: const [
                    DropdownMenuItem(value: 'Cairo', child: Text('Cairo (سينمانا)', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'Tajawal', child: Text('Tajawal', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'Almarai', child: Text('Almarai', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'Changa', child: Text('Changa', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (v) => s.updateFont(v!),
                ),
              ),
              const SizedBox(height: 16),

              Text(isAr ? 'وضع التطبيق وفلترة المحتوى' : 'Content Filter Mode', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Column(
                  children: [
                    RadioListTile<int>(title: const Text('الافتراضي (الكل)', style: TextStyle(color: Colors.white)), value: 0, groupValue: s.appFilterMode, activeColor: AppColors.primary, onChanged: (v) => s.updateFilterMode(v!)),
                    RadioListTile<int>(title: const Text('الوضع العائلي', style: TextStyle(color: Colors.white)), value: 1, groupValue: s.appFilterMode, activeColor: AppColors.primary, onChanged: (v) => s.updateFilterMode(v!)),
                    RadioListTile<int>(title: const Text('وضع الأطفال', style: TextStyle(color: Colors.white)), value: 2, groupValue: s.appFilterMode, activeColor: AppColors.primary, onChanged: (v) => s.updateFilterMode(v!)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
