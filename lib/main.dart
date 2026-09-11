import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'stream_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class AppColors {
  static const Color primary = Color(0xFFFF2D55);
  static const Color primaryDark = Color(0xFFD81E43);
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceLight = Color(0xFF2C2C2E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF636366);
  static const Color star = Color(0xFFFFCC00);
  static const Color border = Color(0x28FFFFFF);
  static const Color glassFill = Color(0xB3161618);
}

class AppRadius {
  static const double card = 16.0;
  static const double chip = 12.0;
  static const double sheet = 26.0;
  static const double button = 22.0;
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

  static Future<bool> isSubscribed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('subscribed_notifications') ?? [];
    return list.contains(id);
  }

  static Future<void> toggleSubscribed(String id) async {
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
  double subBottomPadding = 80.0;
  bool enableDualSubtitles = false;
  int appFilterMode = 0;
  String appLanguage = 'ar';
  String selectedFont = 'iPhone';
  bool autoSmartDownload = false;
  bool smartNotifications = true;
  bool tvModeEnabled = false;

  String? userName;
  String? userEmail;
  String activeProfile = 'الرئيسي';
  List<String> userProfiles = ['الرئيسي', 'الأطفال', 'عائلي'];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    seekDuration = p.getInt('player_seek_dur') ?? 10;
    skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
    subFontSize = p.getDouble('player_sub_size') ?? 18.0;
    subBottomPadding = p.getDouble('player_sub_bottom') ?? 80.0;
    enableDualSubtitles = p.getBool('player_dual_sub') ?? false;
    appFilterMode = p.getInt('app_filter_mode') ?? 0;
    appLanguage = p.getString('app_lang') ?? 'ar';
    selectedFont = p.getString('app_font') ?? 'iPhone';
    autoSmartDownload = p.getBool('app_smart_dl') ?? false;
    smartNotifications = p.getBool('app_smart_notif') ?? true;
    tvModeEnabled = p.getBool('app_tv_mode') ?? false;
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

  void updateSmartNotifications(bool val) async {
    smartNotifications = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_smart_notif', val);
  }

  void updateTvMode(bool val) async {
    tvModeEnabled = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_tv_mode', val);
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
    subBottomPadding = 80.0;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('player_sub_size', 18.0);
    await p.setDouble('player_sub_bottom', 80.0);
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
      case 'Cairo':
        return GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);
      case 'Tajawal':
        return GoogleFonts.tajawalTextTheme(ThemeData.dark().textTheme);
      case 'Almarai':
        return GoogleFonts.almaraiTextTheme(ThemeData.dark().textTheme);
      default:
        return GoogleFonts.ibmPlexSansArabicTextTheme(ThemeData.dark().textTheme);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ONEBR TV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        cardColor: AppColors.surface,
        textTheme: s.getCustomTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
      ),
      home: const MainNavigationHolder(),
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
    CategoriesScreen(),
    const AdvancedSearchScreen(),
    const LibraryScreen(),
  ];

  Future<bool> _onWillPop() async {
    final shouldExit = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('الخروج من ONEBR TV'),
        content: const Text('هل ترغب حقاً في إغلاق التطبيق؟'),
        actions: [
          CupertinoDialogAction(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('خروج'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.glassFill,
                  border: Border(top: BorderSide(color: Color(0x22FFFFFF), width: 0.5)),
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: AppColors.textMuted,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 10,
                  unselectedFontSize: 10,
                  onTap: (i) {
                    HapticFeedback.lightImpact();
                    setState(() => _currentIndex = i);
                  },
                  items: [
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.home_filled, size: 23)),
                      label: isAr ? 'الرئيسية' : 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.grid_view_rounded, size: 23)),
                      label: isAr ? 'الأقسام' : 'Categories',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.search_rounded, size: 23)),
                      label: isAr ? 'بحث' : 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.person_rounded, size: 23)),
                      label: isAr ? 'الحساب' : 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  CategoriesScreen({super.key});

  final List<Map<String, dynamic>> _allCategories = const [
    {'key': 'horror', 'ar': 'رعب وتشويق', 'icon': Icons.local_fire_department_rounded},
    {'key': 'action', 'ar': 'أكشن وحركة', 'icon': Icons.flash_on_rounded},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'icon': Icons.auto_awesome_rounded},
    {'key': 'comedy', 'ar': 'كوميديا وضحك', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'key': 'sci-fi', 'ar': 'خيال علمي وفضاء', 'icon': Icons.rocket_launch_rounded},
    {'key': 'drama', 'ar': 'دراما وقصص واقعية', 'icon': Icons.movie_rounded},
    {'key': 'romance', 'ar': 'رومانسية وحب', 'icon': Icons.favorite_rounded},
    {'key': 'crime', 'ar': 'جريمة وتحقيق', 'icon': Icons.shield_rounded},
    {'key': 'adventure', 'ar': 'مغامرات واستكشاف', 'icon': Icons.explore_rounded},
    {'key': 'thriller', 'ar': 'إثارة وغموض', 'icon': Icons.remove_red_eye_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('الأقسام والتصنيفات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _allCategories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final cat = _allCategories[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat['icon'], color: AppColors.primary, size: 20),
              ),
              title: Text(cat['ar'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
              trailing: const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted, size: 20),
              onTap: () {
                HapticFeedback.selectionClick();
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
    final isTv = AppSettings.instance.tvModeEnabled;
    final count = isTv ? 6 : (MediaQuery.of(context).size.width > 700 ? 5 : 3);

    return Directionality(
      textDirection: AppSettings.instance.appLanguage == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          leading: IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: GridView.builder(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.58,
          ),
          itemCount: _items.length,
          itemBuilder: (ctx, i) {
            final it = _items[i];
            final poster = StreamService.extractPoster(it);
            final title = it['ar_title'] ?? it['en_title'] ?? '';

            return InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it)));
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          },
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
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 25, level: level),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 25, level: level),
      ]);

      final allMovies = res[0];
      final allSeries = res[1];

      final hero = allMovies.take(5).toList();
      final heroIds = hero.map((e) => (e['nb'] ?? e['id']).toString()).toSet();

      final marvel = allMovies.where((it) {
        final t = (it['ar_title'] ?? it['en_title'] ?? '').toString().toLowerCase();
        final id = (it['nb'] ?? it['id']).toString();
        return !heroIds.contains(id) &&
            (t.contains('iron') || t.contains('thor') || t.contains('avengers') || t.contains('hulk') || t.contains('captain') || t.contains('marvel') || t.contains('war'));
      }).take(10).toList();
      final marvelIds = marvel.map((e) => (e['nb'] ?? e['id']).toString()).toSet();

      final featured = allMovies.where((it) {
        final id = (it['nb'] ?? it['id']).toString();
        return !heroIds.contains(id) && !marvelIds.contains(id);
      }).take(12).toList();
      final featuredIds = featured.map((e) => (e['nb'] ?? e['id']).toString()).toSet();

      final recent = allSeries.where((it) {
        final id = (it['nb'] ?? it['id']).toString();
        return !heroIds.contains(id) && !marvelIds.contains(id) && !featuredIds.contains(id);
      }).take(12).toList();

      final combined = [...allMovies, ...allSeries];
      for (var it in combined) {
        final id = (it['nb'] ?? it['id'])?.toString();
        if (id != null) _uniqueIds.add(id);
      }

      if (mounted) {
        setState(() {
          _heroItems = hero;
          _marvelItems = marvel.isNotEmpty ? marvel : allMovies.skip(5).take(10).toList();
          _featuredItems = featured.isNotEmpty ? featured : allMovies.skip(15).take(10).toList();
          _recentItems = recent;
          _infiniteList = List.from(combined);
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
    HapticFeedback.lightImpact();
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

  void _spinMovieRoulette() {
    HapticFeedback.heavyImpact();
    if (_infiniteList.isEmpty) return;
    final randomItem = _infiniteList[(DateTime.now().millisecondsSinceEpoch) % _infiniteList.length];
    
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('اقترحنا لك هذا العمل! 🎬'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(randomItem['ar_title'] ?? randomItem['en_title'] ?? 'عمل رائع', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          CupertinoDialogAction(child: const Text('إلغاء'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('مشاهدة التفاصيل'),
            onPressed: () {
              Navigator.pop(ctx);
              _openDetails(randomItem);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = AppSettings.instance.tvModeEnabled;
    final gridCount = isTv ? 6 : (screenWidth > 700 ? 5 : 3);
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tv_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'ONEBR TV',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'وضع التلفاز',
              icon: Icon(isTv ? Icons.tv_rounded : Icons.phone_android_rounded, color: isTv ? AppColors.primary : Colors.white70, size: 20),
              onPressed: () {
                HapticFeedback.selectionClick();
                AppSettings.instance.updateTvMode(!isTv);
              },
            ),
            IconButton(
              tooltip: 'شنو نباوع اليوم؟',
              icon: const Icon(Icons.casino_rounded, color: AppColors.star, size: 22),
              onPressed: _spinMovieRoulette,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadFeed,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isAr ? 'استكشف المزيد من الأعمال' : 'Explore More Titles', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const Icon(Icons.movie_filter_rounded, color: AppColors.primary, size: 18),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridCount,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.58,
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
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      border: Border.all(color: AppColors.border, width: 0.5),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                                    const SizedBox(width: 3),
                                    Text(score, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
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
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCinemaFilterButtons(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _openSectionView(isAr ? 'الأفلام السينمائية' : 'Movies', false);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(isAr ? 'الأفلام' : 'Movies', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _openSectionView(isAr ? 'المسلسلات والأنمي' : 'TV Series', true);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tv_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Text(isAr ? 'المسلسلات' : 'Series', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
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
            height: 220,
            viewportFraction: 0.92,
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
                        colors: [Colors.transparent, Color(0x77000000), Color(0xF2000000)],
                        stops: [0.3, 0.7, 1.0],
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
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              const Text('4K Ultra HD', style: TextStyle(color: AppColors.star, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minSize: 0,
                          onPressed: () => _openDetails(item),
                          child: Text(
                            AppSettings.instance.appLanguage == 'ar' ? 'شاهد الآن' : 'Watch',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _heroItems.asMap().entries.map((entry) {
            final isSel = entry.key == _currentHeroIdx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSel ? 18 : 6,
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isAr ? 'متابعة المشاهدة' : 'Continue Watching', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await LocalStorageService.setList('resume_playback_list', []);
                  setState(() => _resumeList = []);
                },
                child: Text(isAr ? 'إزالة الكل' : 'Clear All', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 115,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _resumeList.length,
            itemBuilder: (ctx, i) {
              final it = _resumeList[i];
              final progress = (it['position'] / it['duration']).clamp(0.0, 1.0);

              return Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            mediaId: it['id'],
                            title: it['title'] ?? '',
                            videoUrl: '',
                            qualities: const [],
                            poster: it['poster'] ?? '',
                          ),
                        ),
                      );
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
                          const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 34)),
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
                  ),
                  Positioned(
                    top: 4, right: 14,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await LocalStorageService.removeItem('resume_playback_list', it['id'].toString(), idField: 'id');
                        final l = await LocalStorageService.getList('resume_playback_list');
                        setState(() => _resumeList = l);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onMore();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(AppSettings.instance.appLanguage == 'ar' ? 'المزيد' : 'More', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final it = items[i];
              final poster = StreamService.extractPoster(it);
              final t = it['ar_title'] ?? it['en_title'] ?? '';
              final score = (it['stars'] ?? '7.0').toString();

              return Container(
                width: 105,
                margin: const EdgeInsets.only(left: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () => _openDetails(it),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: AppColors.surface),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                          const SizedBox(width: 3),
                          Text(score, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
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

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _movieResults = [];
  List<dynamic> _seriesResults = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _isSearching = false;

  String _filterType = 'all';
  String _selectedCategory = 'الكل';
  double _minScore = 0.0;
  int _fromYear = 1900;
  int _toYear = 2026;

  final List<String> _categories = [
    'الكل', 'أكشن', 'رعب', 'كوميديا', 'دراما', 'أنمي ورسوم متحركة', 'خيال علمي', 'مغامرات', 'إثارة'
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
    if (q.isEmpty) {
      setState(() {
        _movieResults.clear();
        _seriesResults.clear();
      });
      return;
    }

    setState(() => _isSearching = true);
    final level = AppSettings.instance.appFilterMode;
    final results = await StreamService.searchContent(q, level: level);

    final List<dynamic> movies = [];
    final List<dynamic> series = [];

    for (var it in results) {
      final isSeries = (it['is_series_fixed'] == true) || (it['season'] != null && it['season'].toString() != '0');
      final score = double.tryParse((it['stars'] ?? '0').toString()) ?? 0.0;
      final year = int.tryParse((it['year'] ?? '0').toString()) ?? 2024;

      if (score < _minScore) continue;
      if (year < _fromYear || year > _toYear) continue;

      if (isSeries) {
        series.add(it);
      } else {
        movies.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _movieResults = movies;
        _seriesResults = series;
        _isSearching = false;
      });
    }
  }

  void _openFilterDialog() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: AppColors.glassFill,
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setMState(() {
                            _selectedCategory = 'الكل';
                            _minScore = 0.0;
                            _fromYear = 1900;
                            _toYear = 2026;
                          });
                        },
                        child: const Text('مسح الكل', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const Text('تصفية النتائج', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Align(alignment: Alignment.centerRight, child: Text('السنة', style: TextStyle(color: Colors.white70, fontSize: 12))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: Text('$_toYear', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('إلى', style: TextStyle(color: Colors.white54))),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: Text('$_fromYear', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Align(alignment: Alignment.centerRight, child: Text('القسم', style: TextStyle(color: Colors.white70, fontSize: 12))),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
                      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                      onChanged: (v) {
                        if (v != null) setMState(() => _selectedCategory = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('تقييم IMDb: ${_minScore.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _minScore,
                      min: 0.0,
                      max: 9.5,
                      onChanged: (v) => setMState(() => _minScore = v),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context);
                        _search();
                      },
                      child: const Text('إظهار النتائج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppSettings.instance.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _openFilterDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border, width: 0.5)),
                        child: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)),
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'ابحث عن أفلام، مسلسلات، ممثلين...',
                            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) {
                            HapticFeedback.lightImpact();
                            _search();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_searchCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildQuickFilterTab('الكل', _filterType == 'all', () => setState(() => _filterType = 'all')),
                      const SizedBox(width: 8),
                      _buildQuickFilterTab('أفلام', _filterType == 'movie', () => setState(() => _filterType = 'movie')),
                      const SizedBox(width: 8),
                      _buildQuickFilterTab('مسلسلات', _filterType == 'series', () => setState(() => _filterType = 'series')),
                    ],
                  ),
                ),

              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : (_movieResults.isNotEmpty || _seriesResults.isNotEmpty)
                        ? _buildCategorizedResults()
                        : _buildRecentSearches(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilterTab(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5C9) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : AppColors.border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCategorizedResults() {
    final showSeries = _filterType == 'all' || _filterType == 'series';
    final showMovies = _filterType == 'all' || _filterType == 'movie';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (showSeries && _seriesResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('مسلسلات', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._seriesResults.take(4).map((it) => _buildMediaSearchRow(it)),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FullCategoryView(title: 'نتائج المسلسلات', isSeriesOnly: true))),
              child: const Text('عرض الكل', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const Divider(color: Color(0x1AFFFFFF), height: 24),
        ],
        if (showMovies && _movieResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('أفلام', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._movieResults.take(4).map((it) => _buildMediaSearchRow(it)),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullCategoryView(title: 'نتائج الأفلام', isSeriesOnly: false))),
              child: const Text('عرض الكل', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaSearchRow(dynamic it) {
    final poster = StreamService.extractPoster(it);
    final title = it['en_title'] ?? it['ar_title'] ?? '';
    final year = it['year']?.toString() ?? '2024';
    final score = (it['stars'] ?? '7.5').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.lightImpact();
        LocalStorageService.appendItem('recent_search_history', it, maxLength: 20);
        _loadRecents();
        Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('$year,دراما', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border, width: 0.8), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('IMDb', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Text(score, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: poster.isNotEmpty ? Image.network(poster, width: 54, height: 78, fit: BoxFit.cover) : Container(width: 54, height: 78, color: AppColors.surface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return const Center(child: Text('ابحث عن أفلامك المفضلة وسجل البحث سيظهر هنا', style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('عمليات البحث الأخيرة', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await LocalStorageService.setList('recent_search_history', []);
                _loadRecents();
              },
              child: const Text('مسح السجل', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._recentSearches.map((it) => _buildMediaSearchRow(it)),
      ],
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
    final sub = await LocalStorageService.isSubscribed(id);
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

    final Map<int, List<dynamic>> rawSeasons = {};
    for (var ep in eps) {
      final sNum = int.tryParse(ep['season']?.toString() ?? '1') ?? 1;
      rawSeasons.putIfAbsent(sNum, () => []).add(ep);
    }

    final sortedKeys = rawSeasons.keys.toList()..sort((a, b) => a.compareTo(b));
    final Map<int, List<dynamic>> sortedSeasons = {};
    for (var k in sortedKeys) {
      final epList = rawSeasons[k]!;
      epList.sort((a, b) {
        final aNum = int.tryParse((a['episode_number'] ?? a['episode'] ?? '0').toString()) ?? 0;
        final bNum = int.tryParse((b['episode_number'] ?? b['episode'] ?? '0').toString()) ?? 0;
        return aNum.compareTo(bNum);
      });
      sortedSeasons[k] = epList;
    }

    if (mounted) {
      setState(() {
        _seasonsMap = sortedSeasons.isNotEmpty ? sortedSeasons : {1: eps};
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

  // الدخول الفوري واللحظي بدون انتظار الشبكة
  void _playEpisode(dynamic ep, int idx) {
    final targetId = (ep['nb'] ?? ep['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = StreamService.extractPoster(widget.media);

    LocalStorageService.markEpisodeWatched(targetId);
    _loadState();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: targetId,
          title: title,
          subtitleTextHeader: 'الموسم $_selectedSeason - الحلقة $idx',
          videoUrl: '',
          qualities: const [],
          episodes: _seasonsMap[_selectedSeason] ?? [],
          currentEpIndex: idx,
          poster: poster,
          onEpisodeChanged: (newId) {
            LocalStorageService.markEpisodeWatched(newId);
            _loadState();
          },
        ),
      ),
    );
  }

  // تشغيل الفيلم فوراً
  void _playMovie() {
    final targetId = (widget.media['nb'] ?? widget.media['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = StreamService.extractPoster(widget.media);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: targetId,
          title: title,
          videoUrl: '',
          qualities: const [],
          poster: poster,
        ),
      ),
    );
  }

  void _showDownloadQualityPicker(String targetId, String title, String poster) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: AppColors.glassFill,
            child: FutureBuilder<Map<String, dynamic>?>(
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
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('اختر جودة التنزيل', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ...qualities.map((q) {
                        final res = q['resolution'] ?? '720p';
                        final url = q['url'] ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.movie_rounded, color: AppColors.primary),
                            title: Text('دقة $res', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            trailing: const Icon(Icons.arrow_downward_rounded, color: Colors.white70),
                            onTap: () {
                              HapticFeedback.lightImpact();
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
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showActorProfile(String actorName) {
    HapticFeedback.selectionClick();
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text('الممثل: $actorName'),
        message: const Text('استعراض أعمال الممثل والبحث عن عروضه السابقة'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('البحث عن أعماله في المنصة'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedSearchScreen()));
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
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
    final sortedSeasonKeys = _seasonsMap.keys.toList()..sort((a, b) => a.compareTo(b));
    final List<String> dummyActors = ['روبرت داوني', 'سكارليت جوهانسون', 'كريس هيمسوورث', 'توم هولاند'];

    return Directionality(
      textDirection: AppSettings.instance.appLanguage == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 460,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: _shareMedia),
                if (_isSeries)
                  IconButton(
                    icon: Icon(_isSubscribed ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: _isSubscribed ? AppColors.primary : Colors.white),
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      await LocalStorageService.toggleSubscribed(id);
                      _loadState();
                    },
                  ),
                IconButton(
                  icon: Icon(_isWatchlist ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _isWatchlist ? AppColors.primary : Colors.white),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
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
                          colors: [Colors.black54, Colors.transparent, Color(0xD9000000), AppColors.background],
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                                  HapticFeedback.selectionClick();
                                  await LocalStorageService.toggleWatchlist(widget.media);
                                  _loadState();
                                },
                                child: Column(
                                  children: [
                                    Icon(_isWatchlist ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
                                    const SizedBox(height: 4),
                                    const Text('المشاهدة لاحقاً', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              CupertinoButton(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppRadius.button),
                                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                                minSize: 0,
                                onPressed: () => _isSeries && currentEpisodes.isNotEmpty ? _playEpisode(currentEpisodes.first, 1) : _playMovie(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 4),
                                    Text('شاهد الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              InkWell(
                                onTap: () => _showDownloadQualityPicker(id, title, poster),
                                child: const Column(
                                  children: [
                                    Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 24),
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
                            backgroundColor: AppColors.surface,
                            side: const BorderSide(color: AppColors.border, width: 0.5),
                            label: Text(name.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 14),

                    const Text('طاقم التمثيل', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: dummyActors.length,
                        itemBuilder: (ctx, i) {
                          final actor = dummyActors[i];
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ActionChip(
                              backgroundColor: AppColors.surface,
                              side: const BorderSide(color: AppColors.border, width: 0.5),
                              label: Text(actor, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              onPressed: () => _showActorProfile(actor),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: InkWell(
                        onTap: _playTrailer,
                        child: Row(
                          children: const [
                            Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 22),
                            SizedBox(width: 8),
                            Text('مشاهدة الإعلان الرسمي', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            Spacer(),
                            Text('تشغيل', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (story.isNotEmpty)
                      Text(story, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_rounded, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        Text(rateCount, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(width: 16),
                        const Icon(Icons.thumb_down_rounded, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        const Text('84', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 32),

                    if (_isSeries && _seasonsMap.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الحلقات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (sortedSeasonKeys.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border, width: 0.5),
                              ),
                              child: DropdownButton<int>(
                                dropdownColor: AppColors.surface,
                                value: _selectedSeason,
                                underline: const SizedBox(),
                                items: sortedSeasonKeys.map((s) => DropdownMenuItem(value: s, child: Text('الموسم $s', style: const TextStyle(color: Colors.white, fontSize: 12)))).toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _selectedSeason = v);
                                },
                              ),
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
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: InkWell(
                            onTap: () => _playEpisode(ep, idx),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded, color: Colors.white54, size: 20),
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
                          physics: const BouncingScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          itemCount: _similarMedia.length,
                          itemBuilder: (ctx, i) {
                            final it = _similarMedia[i];
                            final simPoster = StreamService.extractPoster(it);
                            final simTitle = it['ar_title'] ?? it['en_title'] ?? '';

                            return Container(
                              width: 105,
                              margin: const EdgeInsets.only(left: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.card),
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
                                    const SizedBox(height: 6),
                                    Text(simTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
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

  String _activeQuality = '360p';
  BoxFit _videoFit = BoxFit.contain;
  bool _isLandscape = true;
  List<Map<String, dynamic>> _currentQualities = [];

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
  IconData _indicatorIcon = Icons.volume_up_rounded;

  bool _showAutoNext = false;
  int _autoNextCountdown = 5;
  Timer? _autoNextTimer;

  bool get _showSmartSkip => _controller != null && _controller!.value.isInitialized && _controller!.value.position.inSeconds < 90;

  @override
  void initState() {
    super.initState();
    _activeEpIndex = widget.currentEpIndex;
    _activeMediaId = widget.mediaId;
    _activeHeader = widget.subtitleTextHeader;
    _currentQualities = widget.qualities;
    _loadWatchedState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    // إذا كان الرابط فارغاً، يتم جلبه فوراً من داخل المشغل
    if (widget.videoUrl.isEmpty) {
      _loadAndPlayMedia(_activeMediaId);
    } else {
      _initPlayer(widget.videoUrl);
      _loadSubtitlesDelayed(widget.subtitleUrl, widget.secondarySubtitleUrl);
    }
  }

  void _loadWatchedState() async {
    final w = await LocalStorageService.getWatchedEpisodes();
    if (mounted) setState(() => _watchedSet = w);
  }

  void _loadAndPlayMedia(String id) async {
    final futures = await Future.wait([
      StreamService.getVideoSource(id),
      StreamService.getVideoExtendedInfo(id),
    ]);

    final source = futures[0];
    final subInfo = futures[1];

    if (source != null && mounted) {
      setState(() {
        _currentQualities = List<Map<String, dynamic>>.from(source['qualities'] ?? []);
      });
      _initPlayer(source['video_url']);

      final subAr = subInfo?['arTranslationFilePath']?.toString() ?? '';
      final subEn = subInfo?['enTranslationFilePath']?.toString() ?? '';
      _loadSubtitlesDelayed(subAr, subEn);
    }
  }

  void _loadSubtitlesDelayed(String arUrl, String enUrl) {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        if (arUrl.isNotEmpty) _loadSubs(arUrl, isSecondary: false);
        if (enUrl.isNotEmpty) _loadSubs(enUrl, isSecondary: true);
      }
    });
  }

  void _loadSubs(String url, {required bool isSecondary}) async {
    try {
      final res = await http.get(Uri.parse(url), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        String decodedText;
        try {
          decodedText = utf8.decode(res.bodyBytes);
        } catch (_) {
          decodedText = latin1.decode(res.bodyBytes);
        }
        final parsed = _parseSrt(decodedText);
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
    final pattern = RegExp(
      r'(\d{1,2}:\d{2}:\d{2}[,\.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,\.]\d{1,3})\r?\n([\s\S]*?)(?=\n\r?\n\d+|\n\r?\n$|$)',
      multiLine: true,
    );
    final matches = pattern.allMatches(text);
    int idx = 0;
    for (var m in matches) {
      try {
        final s = _durationFromStr(m.group(1)!);
        final e = _durationFromStr(m.group(2)!);
        final txt = m.group(3)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (txt.isNotEmpty) list.add(Subtitle(index: idx++, start: s, end: e, text: txt));
      } catch (_) {}
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

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: StreamService.stealthHeaders,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );
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

  void _playPreviousEpisode() {
    _autoNextTimer?.cancel();
    setState(() => _showAutoNext = false);
    if (_activeEpIndex > 1) {
      final prevEp = widget.episodes[_activeEpIndex - 2];
      _switchEpisode(prevEp, _activeEpIndex - 1);
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
      setState(() {
        _currentQualities = List<Map<String, dynamic>>.from(source['qualities'] ?? []);
      });
      _initPlayer(source['video_url']);
      final path = sub['arTranslationFilePath']?.toString() ?? '';
      final pathEn = sub['enTranslationFilePath']?.toString() ?? '';
      _loadSubtitlesDelayed(path, pathEn);
    }
  }

  void _toggleScreenOrientation() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  void _showEpisodesDrawer() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: AppColors.glassFill,
            height: 350,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('قائمة الحلقات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.episodes.length,
                    itemBuilder: (ctx, i) {
                      final ep = widget.episodes[i];
                      final idx = i + 1;
                      final isCurrent = idx == _activeEpIndex;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isCurrent ? AppColors.primary.withOpacity(0.3) : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: ListTile(
                          title: Text('الحلقة $idx', style: TextStyle(color: Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                          trailing: isCurrent ? const Icon(Icons.play_arrow_rounded, color: AppColors.primary) : null,
                          onTap: () {
                            Navigator.pop(context);
                            _switchEpisode(ep, idx);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _castToTv() async {
    final videoUrl = _controller?.dataSource ?? widget.videoUrl;
    if (videoUrl.isEmpty) return;

    final uri = Uri.parse(videoUrl);
    final intentUri = Uri.parse("intent:$videoUrl#Intent;type=video/*;package=org.videolan.vlc;end");

    if (await canLaunchUrl(intentUri)) {
      await launchUrl(intentUri);
    } else if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قم بتثبيت مشغل يدعم البث مثل VLC أو Web Video Caster')),
        );
      }
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
        _indicatorIcon = _volumeLevel == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded;
        _indicatorText = '${(_volumeLevel * 100).toInt()}%';
      } else {
        _brightnessLevel = (_brightnessLevel + delta).clamp(0.1, 1.0);
        _indicatorIcon = Icons.brightness_6_rounded;
        _indicatorText = '${(_brightnessLevel * 100).toInt()}%';
      }
    });

    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  void _openSettingsBottomSheet() {
    final settings = AppSettings.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: AppColors.glassFill,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.subtitles_rounded, color: Colors.white70),
                      title: const Text('الترجمة المزدوجة (عربي + إنجليزي)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.enableDualSubtitles,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateDualSubtitles(v)),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_rounded, color: Colors.white70),
                      title: const Text('إزالة اللقطات الحساسة تلقائياً', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.skipSensitiveScenes,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateSkipScenes(v)),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings_rounded, color: Colors.white70),
                      title: const Text('دقة الفيديو', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_activeQuality, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showQualityPicker();
                      },
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.fast_forward_rounded, color: Colors.white70),
                      title: const Text('فترة تمرير الفيديو', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text('${settings.seekDuration} ثوانٍ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSeekPicker();
                      },
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.closed_caption_rounded, color: Colors.white70),
                      title: const Text('إعدادات ومكان الترجمة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_left_rounded, color: Colors.white24, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()));
                      },
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70),
                      title: const Text('أبعاد الشاشة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_videoFit == BoxFit.cover ? 'ملء الشاشة' : 'طبيعي', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          _videoFit = _videoFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSeekPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('فترة التقديم والتأخير'),
        actions: [5, 10, 15, 30].map((s) => CupertinoActionSheetAction(
          child: Text('$s ثوانٍ'),
          onPressed: () {
            AppSettings.instance.updateSeek(s);
            Navigator.pop(context);
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ),
    );
  }

  void _showQualityPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('اختر جودة العرض'),
        actions: _currentQualities.map((q) {
          final res = q['resolution'] ?? '360p';
          final url = q['url'] ?? '';
          return CupertinoActionSheetAction(
            child: Text(res),
            onPressed: () {
              Navigator.pop(context);
              setState(() => _activeQuality = res);
              _initPlayer(url);
            },
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ),
    );
  }

  void _takeSceneClip() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ لقطة الشاشة والمقطع القصير في استوديو الهاتف! 📸')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final hasPrev = widget.episodes.isNotEmpty && _activeEpIndex > 1;
    final hasNext = widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length;

    // حساب رفع الترجمة ديناميكياً لتصعد في الوضع العمودي فوق الحواف وعناصر التحكم
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveBottomPadding = isPortrait
        ? (settings.subBottomPadding + 95.0)
        : (settings.subBottomPadding + 10.0);

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

                  // الترجمة المرفوعة للأعلى ومتكيفة مع اتجاه الشاشة
                  if (_currentSubText.isNotEmpty)
                    Positioned(
                      bottom: effectiveBottomPadding,
                      left: 20,
                      right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _currentSubText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: settings.subColor,
                              fontSize: isPortrait ? 15.0 : settings.subFontSize,
                              fontWeight: FontWeight.bold,
                              shadows: settings.subHasShadow ? [const Shadow(blurRadius: 10, color: Colors.black)] : null,
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_showSmartSkip)
                    Positioned(
                      bottom: 85, left: 20,
                      child: CupertinoButton(
                        color: AppColors.surface.withOpacity(0.9),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minSize: 0,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          final target = _controller!.value.position + const Duration(seconds: 85);
                          _controller!.seekTo(target > _controller!.value.duration ? _controller!.value.duration : target);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('تخطي المقدمة', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (_showAutoNext && hasNext)
                    Positioned(
                      bottom: 85, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.95), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border, width: 0.5)),
                        child: Row(
                          children: [
                            Text('الحلقة التالية خلال $_autoNextCountdown ث', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              color: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minSize: 0,
                              onPressed: _playNextEpisode,
                              child: const Text('تشغيل الآن', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                                if (widget.episodes.isNotEmpty)
                                  IconButton(
                                    tooltip: 'قائمة الحلقات',
                                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 24),
                                    onPressed: _showEpisodesDrawer,
                                  ),
                                IconButton(
                                  tooltip: 'قلب الشاشة',
                                  icon: Icon(_isLandscape ? Icons.screen_rotation_rounded : Icons.screen_lock_rotation_rounded, color: Colors.white),
                                  onPressed: _toggleScreenOrientation,
                                ),
                                IconButton(
                                  tooltip: 'صانع اللقطات',
                                  icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
                                  onPressed: _takeSceneClip,
                                ),
                                IconButton(icon: const Icon(Icons.tv_rounded, color: Colors.white), onPressed: _castToTv),
                                IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white), onPressed: _openSettingsBottomSheet),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.episodes.isNotEmpty)
                            IconButton(
                              iconSize: 32,
                              icon: Icon(Icons.skip_previous_rounded, color: hasPrev ? Colors.white : Colors.white24),
                              onPressed: hasPrev ? _playPreviousEpisode : null,
                            ),
                          const SizedBox(width: 10),
                          IconButton(
                            iconSize: 32,
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                            onPressed: () {
                              final p = _controller!.value.position - Duration(seconds: settings.seekDuration);
                              _controller!.seekTo(p < Duration.zero ? Duration.zero : p);
                            },
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 54,
                            icon: Icon(_controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                            onPressed: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 32,
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                            onPressed: () {
                              final p = _controller!.value.position + Duration(seconds: settings.seekDuration);
                              _controller!.seekTo(p);
                            },
                          ),
                          const SizedBox(width: 10),
                          if (widget.episodes.isNotEmpty)
                            IconButton(
                              iconSize: 32,
                              icon: Icon(Icons.skip_next_rounded, color: hasNext ? Colors.white : Colors.white24),
                              onPressed: hasNext ? _playNextEpisode : null,
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
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                thumbColor: AppColors.primary,
                                activeTrackColor: AppColors.primary,
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
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatTime(_controller!.value.position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  Text(_formatTime(_controller!.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
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

class SubtitleSettingsScreen extends StatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  State<SubtitleSettingsScreen> createState() => _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState extends State<SubtitleSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إعدادات الترجمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: (s.subBottomPadding / 140) * 90,
                    left: 20, right: 20,
                    child: Center(
                      child: Text(
                        'معاينة موقع ولون الترجمة المباشر\nLive Subtitle Preview',
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
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('موقع الترجمة من الأسفل', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Slider(
                      value: s.subBottomPadding,
                      min: 30.0,
                      max: 140.0,
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white24,
                      onChanged: (v) => setState(() => s.updateSubStyle(bottomPadding: v)),
                    ),
                    trailing: Text('${s.subBottomPadding.toInt()} dp', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    title: const Text('حجم خط الترجمة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: DropdownButton<double>(
                      dropdownColor: AppColors.surface,
                      value: s.subFontSize,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 14.0, child: Text('صغير', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 18.0, child: Text('متوسط', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 24.0, child: Text('كبير', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (v) => setState(() => s.updateSubStyle(size: v)),
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    title: const Text('لون الخط', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _colorBubble(Colors.white, s.subColor == Colors.white, () => setState(() => s.updateSubStyle(color: Colors.white))),
                        _colorBubble(Colors.yellow, s.subColor == Colors.yellow, () => setState(() => s.updateSubStyle(color: Colors.yellow))),
                        _colorBubble(const Color(0xFF00F0FF), s.subColor == const Color(0xFF00F0FF), () => setState(() => s.updateSubStyle(color: const Color(0xFF00F0FF)))),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    title: const Text('ظل حواف الخط', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: CupertinoSwitch(
                      value: s.subHasShadow,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => s.updateSubStyle(shadow: v)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              onPressed: () => setState(() => s.resetSubtitles()),
              child: const Text('إعادة ضبط الترجمة الافتراضية', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
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
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: AppColors.primary, width: 2.5) : null,
        ),
      ),
    );
  }
}

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
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('إضافة بروفايل جديد'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: 'اسم الملف الشخصي',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          CupertinoDialogAction(
            isDefaultAction: true,
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
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('تسجيل الحساب والمزامنة'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              CupertinoTextField(
                controller: _nameCtrl,
                placeholder: 'الاسم المستعار',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _emailCtrl,
                placeholder: 'البريد الإلكتروني',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (_nameCtrl.text.isNotEmpty) {
                AppSettings.instance.login(_nameCtrl.text, _emailCtrl.text);
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 3;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAr ? 'الحساب والمكتبة' : 'Profile & Library', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'تفريغ الكاش',
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
            onPressed: _cleanCache,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
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
              ? Center(child: Text(isAr ? 'لا توجد تنزيلات حالياً' : 'No downloads yet', style: const TextStyle(color: AppColors.textSecondary)))
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...DownloadManager.instance.activeDownloads.values.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)),
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
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: d.progress, backgroundColor: Colors.white24, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${d.speedKbs.toStringAsFixed(1)} KB/s', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18), onPressed: () => DownloadManager.instance.cancelDownload(d.id)),
                            ],
                          ),
                        ],
                      ),
                    )),
                    ..._completed.map((it) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)),
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                        title: Text(it['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(it['size'] ?? '', style: const TextStyle(color: Colors.white54)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38), onPressed: () async {
                          await LocalStorageService.removeItem('downloaded_works_list', it['nb']?.toString() ?? '', idField: 'nb');
                          _loadData();
                        }),
                      ),
                    )),
                  ],
                ),

          _watchlist.isEmpty
              ? Center(child: Text(isAr ? 'لم تقم بحفظ أي عمل بعد' : 'Watchlist is empty', style: const TextStyle(color: AppColors.textSecondary)))
              : GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, childAspectRatio: 0.58, crossAxisSpacing: 10, mainAxisSpacing: 12),
                  itemCount: _watchlist.length,
                  itemBuilder: (ctx, i) {
                    final item = _watchlist[i];
                    final poster = StreamService.extractPoster(item);
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _loadData()),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: AppColors.surface),
                      ),
                    );
                  },
                ),

          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 40),
                    const SizedBox(height: 10),
                    Text(isAr ? 'إحصائيات الملف: ${s.activeProfile}' : 'Stats for: ${s.activeProfile}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(color: AppColors.border, height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('$_statMinutes', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(isAr ? 'دقيقة مشاهدة' : 'Minutes Watched', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('$_statEpisodes', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
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
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 24, backgroundColor: AppColors.primary, child: Icon(Icons.person_rounded, color: Colors.white)),
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
                    CupertinoButton(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minSize: 0,
                      onPressed: s.userName == null ? _showAuthDialog : () => setState(() => s.logout()),
                      child: Text(s.userName == null ? (isAr ? 'تسجيل' : 'Login') : (isAr ? 'خروج' : 'Logout'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              const Text('إدارة الملفات الشخصية', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ...s.userProfiles.map((p) => ChoiceChip(
                    label: Text(p),
                    selected: s.activeProfile == p,
                    selectedColor: AppColors.primary,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        s.switchProfile(p);
                        _loadData();
                      });
                    },
                  )),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('إضافة بروفايل'),
                    onPressed: _showAddProfileDialog,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
                      title: const Text('التنبيه الذكي للمسلسلات', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('إرسال إشعارات لحظية عند نزول حلقات جديدة', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      trailing: CupertinoSwitch(
                        value: s.smartNotifications,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => s.updateSmartNotifications(v)),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                      title: const Text('التنزيل الذكي للحلقات', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('تنزيل الحلقة التالية ومسح المنتهية تلقائياً', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      trailing: CupertinoSwitch(
                        value: s.autoSmartDownload,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => s.updateSmartDownload(v)),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                      title: Text(isAr ? 'لغة التطبيق' : 'App Language', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: DropdownButton<String>(
                        dropdownColor: AppColors.surface,
                        value: s.appLanguage,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'ar', child: Text('العربية', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateLanguage(v));
                        },
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(Icons.text_fields_rounded, color: AppColors.primary),
                      title: Text(isAr ? 'خط التطبيق' : 'App Font', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: DropdownButton<String>(
                        dropdownColor: AppColors.surface,
                        value: s.selectedFont,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'iPhone', child: Text('iPhone (أبل الرسمي)', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Cairo', child: Text('Cairo', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Tajawal', child: Text('Tajawal', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Almarai', child: Text('Almarai', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFont(v));
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              const Text('وضع المحتوى', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)),
                child: Column(
                  children: [
                    RadioListTile<int>(
                      title: Text(isAr ? 'الافتراضي (الكل)' : 'Default', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      value: 0,
                      groupValue: s.appFilterMode,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        if (v != null) setState(() => s.updateFilterMode(v));
                      },
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    RadioListTile<int>(
                      title: Text(isAr ? 'الوضع العائلي' : 'Family Mode', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      value: 1,
                      groupValue: s.appFilterMode,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        if (v != null) setState(() => s.updateFilterMode(v));
                      },
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    RadioListTile<int>(
                      title: Text(isAr ? 'وضع الأطفال' : 'Kids Mode', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      value: 2,
                      groupValue: s.appFilterMode,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        if (v != null) setState(() => s.updateFilterMode(v));
                      },
                    ),
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
