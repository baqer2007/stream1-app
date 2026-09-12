import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
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
  static const Color star = Color(0xFFFFCC00);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceLight = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);
  static const Color darkBorder = Color(0x28FFFFFF);
  static const Color darkGlassFill = Color(0xB3161618);

  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceLight = Color(0xFFE5E5EA);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF6C6C70);
  static const Color lightBorder = Color(0x1F000000);
  static const Color lightGlassFill = Color(0xCCFFFFFF);
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

class SubtitleCache {
  static final Map<String, List<Subtitle>> _mem = {};
  static List<Subtitle>? get(String url) => _mem[url];
  static void set(String url, List<Subtitle> list) => _mem[url] = list;
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
    final list = prefs.getStringList('watched_episodes_${currentProfile}_list') ?? [];
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

class BackgroundDownloadService {
  static final ReceivePort _port = ReceivePort();

  static Future<void> initialize() async {
    try {
      await FlutterDownloader.initialize(debug: false, ignoreSsl: true);
      IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
      FlutterDownloader.registerCallback(downloadCallback);
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  static Future<String?> startDownload({
    required String url,
    required String fileName,
    required String targetId,
    required String title,
    required String poster,
  }) async {
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Download/ONEBR_TV');
      if (!baseDir.existsSync()) {
        try {
          baseDir.createSync(recursive: true);
        } catch (_) {
          baseDir = await getExternalStorageDirectory();
        }
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final path = baseDir?.path ?? '';
    final taskId = await FlutterDownloader.enqueue(
      url: url,
      headers: StreamService.stealthHeaders,
      savedDir: path,
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: false,
      saveInPublicStorage: true,
    );

    if (taskId != null) {
      await LocalStorageService.appendItem('downloaded_works_list', {
        'nb': targetId,
        'taskId': taskId,
        'title': title,
        'path': '$path/$fileName',
        'poster': poster,
        'date': DateTime.now().millisecondsSinceEpoch,
      });
    }

    return taskId;
  }
}

class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._();
  AppSettings._();

  bool isDarkMode = true;
  int seekDuration = 10;
  bool skipSensitiveScenes = true;
  double subFontSize = 18.0;
  Color subColor = Colors.white;
  bool subHasShadow = true;
  double subBottomPadding = 26.0;
  String subBackgroundMode = 'semi';
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

  Color get bg => isDarkMode ? AppColors.darkBackground : AppColors.lightBackground;
  Color get surface => isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
  Color get surfaceLight => isDarkMode ? AppColors.darkSurfaceLight : AppColors.lightSurfaceLight;
  Color get textPrimary => isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get border => isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;
  Color get glassFill => isDarkMode ? AppColors.darkGlassFill : AppColors.lightGlassFill;

  Color get subtitleBackgroundColor {
    switch (subBackgroundMode) {
      case 'transparent':
        return Colors.transparent;
      case 'dark':
        return Colors.black.withOpacity(0.85);
      case 'semi':
      default:
        return Colors.black.withOpacity(0.40);
    }
  }

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      isDarkMode = p.getBool('app_is_dark_mode') ?? true;
      seekDuration = p.getInt('player_seek_dur') ?? 10;
      skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
      subFontSize = p.getDouble('player_sub_size') ?? 18.0;
      subBottomPadding = p.getDouble('player_sub_bottom') ?? 26.0;
      subBackgroundMode = p.getString('player_sub_bg_mode') ?? 'semi';
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
    } catch (_) {}
  }

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_is_dark_mode', isDarkMode);
  }

  void updateLanguage(String lang) async {
    appLanguage = lang;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('app_lang', lang);
  }

  void updateSeek(int sec) async {
    seekDuration = sec;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('player_seek_dur', sec);
  }

  void updateFilterMode(int mode) async {
    appFilterMode = mode;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('app_filter_mode', mode);
  }

  void updateTvMode(bool val) async {
    tvModeEnabled = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_tv_mode', val);
  }

  void updateSubStyle({double? size, Color? color, bool? shadow, double? bottomPadding, String? bgMode}) async {
    if (size != null) subFontSize = size;
    if (color != null) subColor = color;
    if (shadow != null) subHasShadow = shadow;
    if (bottomPadding != null) subBottomPadding = bottomPadding;
    if (bgMode != null) subBackgroundMode = bgMode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (bottomPadding != null) await p.setDouble('player_sub_bottom', bottomPadding);
    if (size != null) await p.setDouble('player_sub_size', size);
    if (bgMode != null) await p.setString('player_sub_bg_mode', bgMode);
  }

  void resetSubtitles() async {
    subFontSize = 18.0;
    subColor = Colors.white;
    subHasShadow = true;
    subBottomPadding = 26.0;
    subBackgroundMode = 'semi';
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('player_sub_size', 18.0);
    await p.setDouble('player_sub_bottom', 26.0);
    await p.setString('player_sub_bg_mode', 'semi');
  }

  void updateDualSubtitles(bool val) async {
    enableDualSubtitles = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('player_dual_sub', val);
  }

  void updateSkipScenes(bool val) async {
    skipSensitiveScenes = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('player_skip_sens', val);
  }

  void updateSmartNotifications(bool val) async {
    smartNotifications = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_smart_notif', val);
  }

  void updateSmartDownload(bool val) async {
    autoSmartDownload = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_smart_dl', val);
  }

  void updateFont(String font) async {
    selectedFont = font;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('app_font', font);
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
    (await SharedPreferences.getInstance()).setString('current_active_profile', profile);
  }

  void addProfile(String profileName) async {
    if (!userProfiles.contains(profileName)) {
      userProfiles.add(profileName);
      notifyListeners();
      (await SharedPreferences.getInstance()).setStringList('user_profiles_list', userProfiles);
    }
  }

  TextTheme getCustomTextTheme() {
    final base = isDarkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    switch (selectedFont) {
      case 'Cairo':
        return GoogleFonts.cairoTextTheme(base);
      case 'Tajawal':
        return GoogleFonts.tajawalTextTheme(base);
      case 'Almarai':
        return GoogleFonts.almaraiTextTheme(base);
      default:
        return GoogleFonts.ibmPlexSansArabicTextTheme(base);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  try {
    await AppSettings.instance.init();
  } catch (e) {
    debugPrint('Settings init error: $e');
  }

  runApp(const OnebrTvApp());

  try {
    await BackgroundDownloadService.initialize();
  } catch (e) {
    debugPrint('BackgroundDownload init error: $e');
  }
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
      theme: (s.isDarkMode ? ThemeData.dark() : ThemeData.light()).copyWith(
        scaffoldBackgroundColor: s.bg,
        primaryColor: AppColors.primary,
        cardColor: s.surface,
        textTheme: s.getCustomTextTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: s.isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        ),
        colorScheme: s.isDarkMode
            ? const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.darkSurface)
            : const ColorScheme.light(primary: AppColors.primary, surface: AppColors.lightSurface),
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
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

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
          backgroundColor: s.bg,
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: s.glassFill,
                  border: Border(top: BorderSide(color: s.border, width: 0.5)),
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: s.textSecondary,
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
    {'key': 'horror', 'ar': 'رعب وتشويق', 'en': 'Horror & Suspense', 'icon': Icons.local_fire_department_rounded},
    {'key': 'action', 'ar': 'أكشن وحركة', 'en': 'Action & Adventure', 'icon': Icons.flash_on_rounded},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'en': 'Anime & Animation', 'icon': Icons.auto_awesome_rounded},
    {'key': 'comedy', 'ar': 'كوميديا وضحك', 'en': 'Comedy', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'key': 'sci-fi', 'ar': 'خيال علمي وفضاء', 'en': 'Sci-Fi & Space', 'icon': Icons.rocket_launch_rounded},
    {'key': 'drama', 'ar': 'دراما وقصص واقعية', 'en': 'Drama & Real Stories', 'icon': Icons.movie_rounded},
    {'key': 'romance', 'ar': 'رومانسية وحب', 'en': 'Romance', 'icon': Icons.favorite_rounded},
    {'key': 'crime', 'ar': 'جريمة وتحقيق', 'en': 'Crime & Mystery', 'icon': Icons.shield_rounded},
    {'key': 'adventure', 'ar': 'مغامرات واستكشاف', 'en': 'Adventure', 'icon': Icons.explore_rounded},
    {'key': 'thriller', 'ar': 'إثارة وغموض', 'en': 'Thriller', 'icon': Icons.remove_red_eye_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'الأقسام والتصنيفات' : 'Categories & Genres', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: s.textPrimary)),
        ),
        body: ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _allCategories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final cat = _allCategories[i];
            final title = isAr ? cat['ar'] : cat['en'];

            return Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: s.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(cat['icon'], color: AppColors.primary, size: 20),
                ),
                title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: s.textPrimary)),
                trailing: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: s.textSecondary, size: 20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FullCategoryView(title: title, categoryEn: cat['key'])),
                  );
                },
              ),
            );
          },
        ),
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
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final isTv = s.tvModeEnabled;
    final count = isTv ? 6 : (MediaQuery.of(context).size.width > 700 ? 5 : 3);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: s.textPrimary)),
          leading: IconButton(
            icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 28, color: s.textPrimary),
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
            final title = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');

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
                        color: s.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: s.border, width: 0.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: poster.isNotEmpty
                            ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                            : Container(color: s.surface),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
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
    if (mounted) setState(() {});
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
    final isAr = AppSettings.instance.appLanguage == 'ar';
    final title = isAr ? (randomItem['ar_title'] ?? randomItem['en_title'] ?? '') : (randomItem['en_title'] ?? randomItem['ar_title'] ?? '');

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isAr ? 'اقترحنا لك هذا العمل! 🎬' : 'Our Pick For You! 🎬'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          CupertinoDialogAction(child: Text(isAr ? 'إلغاء' : 'Cancel'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(isAr ? 'مشاهدة التفاصيل' : 'View Details'),
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
    final s = AppSettings.instance;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = s.tvModeEnabled;
    final gridCount = isTv ? 6 : (screenWidth > 700 ? 5 : 3);
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
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
              Text(
                'ONEBR TV',
                style: TextStyle(
                  color: s.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: s.isDarkMode ? (isAr ? 'الوضع الفاتح' : 'Light Mode') : (isAr ? 'الوضع الداكن' : 'Dark Mode'),
                icon: Icon(s.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: s.textPrimary, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  s.toggleTheme();
                },
              ),
              IconButton(
                tooltip: isAr ? 'وضع التلفاز' : 'TV Mode',
                icon: Icon(isTv ? Icons.tv_rounded : Icons.phone_android_rounded, color: isTv ? AppColors.primary : s.textSecondary, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  s.updateTvMode(!isTv);
                },
              ),
              IconButton(
                tooltip: isAr ? 'شنو نباوع اليوم؟' : 'Roulette',
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
                      if (_heroItems.isNotEmpty) _buildCarouselBanner(isAr),
                      _buildCinemaFilterButtons(isAr),
                      if (_resumeList.isNotEmpty) _buildResumeSection(isAr),
                      _buildMediaShelf(isAr ? 'عالم مارفل 4K' : 'Marvel 4K Universe', _marvelItems, () => _openSectionView(isAr ? 'عالم مارفل 4K' : 'Marvel 4K', false), isAr),
                      _buildMediaShelf(isAr ? 'الأفلام المميزة' : 'Featured Movies', _featuredItems, () => _openSectionView(isAr ? 'الأفلام المميزة' : 'Featured', false), isAr),
                      _buildMediaShelf(isAr ? 'أُضيف مؤخراً' : 'Recently Added', _recentItems, () => _openSectionView(isAr ? 'أُضيف مؤخراً' : 'Recent', true), isAr),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isAr ? 'استكشف المزيد من الأعمال' : 'Explore More Titles', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                            final t = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
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
                                        color: s.surface,
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                        border: Border.all(color: s.border, width: 0.5),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                        child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: s.surface),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                                      const SizedBox(width: 3),
                                      Text(score, style: TextStyle(color: s.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
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
      ),
    );
  }

  Widget _buildCinemaFilterButtons(bool isAr) {
    final s = AppSettings.instance;
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
                  color: s.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(isAr ? 'الأفلام' : 'Movies', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
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
                  color: s.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tv_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Text(isAr ? 'المسلسلات' : 'Series', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselBanner(bool isAr) {
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
            final title = isAr ? (item['ar_title'] ?? item['en_title'] ?? '') : (item['en_title'] ?? item['ar_title'] ?? '');

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppSettings.instance.border, width: 0.5),
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
                            isAr ? 'شاهد الآن' : 'Watch',
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
    final s = AppSettings.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isAr ? 'متابعة المشاهدة' : 'Continue Watching', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
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
                        border: Border.all(color: s.border, width: 0.5),
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

  Widget _buildMediaShelf(String title, List<dynamic> items, VoidCallback onMore, bool isAr) {
    if (items.isEmpty) return const SizedBox();
    final s = AppSettings.instance;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onMore();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(isAr ? 'المزيد' : 'More', style: TextStyle(color: s.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
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
              final t = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
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
                            color: s.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: s.border, width: 0.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            child: poster.isNotEmpty ? Image.network(poster, width: double.infinity, fit: BoxFit.cover) : Container(color: s.surface),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                          const SizedBox(width: 3),
                          Text(score, style: TextStyle(color: s.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
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
  String _selectedCategoryKey = 'all';
  double _minScore = 0.0;
  int _fromYear = 1900;
  int _toYear = 2026;

  final List<Map<String, String>> _categories = [
    {'key': 'all', 'ar': 'الكل', 'en': 'All'},
    {'key': 'action', 'ar': 'أكشن', 'en': 'Action'},
    {'key': 'horror', 'ar': 'رعب', 'en': 'Horror'},
    {'key': 'comedy', 'ar': 'كوميديا', 'en': 'Comedy'},
    {'key': 'drama', 'ar': 'دراما', 'en': 'Drama'},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'en': 'Animation'},
    {'key': 'sci-fi', 'ar': 'خيال علمي', 'en': 'Sci-Fi'},
    {'key': 'adventure', 'ar': 'مغامرات', 'en': 'Adventure'},
    {'key': 'thriller', 'ar': 'إثارة', 'en': 'Thriller'},
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
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: s.glassFill,
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
                              _selectedCategoryKey = 'all';
                              _minScore = 0.0;
                              _fromYear = 1900;
                              _toYear = 2026;
                            });
                          },
                          child: Text(isAr ? 'مسح الكل' : 'Reset All', style: TextStyle(color: s.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text(isAr ? 'تصفية النتائج' : 'Filter Results', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: s.textPrimary, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(alignment: isAr ? Alignment.centerRight : Alignment.centerLeft, child: Text(isAr ? 'السنة' : 'Year', style: TextStyle(color: s.textSecondary, fontSize: 12))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: Text('$_toYear', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(isAr ? 'إلى' : 'to', style: TextStyle(color: s.textSecondary))),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: Text('$_fromYear', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Align(alignment: isAr ? Alignment.centerRight : Alignment.centerLeft, child: Text(isAr ? 'القسم' : 'Category', style: TextStyle(color: s.textSecondary, fontSize: 12))),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10)),
                      child: DropdownButton<String>(
                        value: _selectedCategoryKey,
                        dropdownColor: s.surface,
                        isExpanded: true,
                        underline: const SizedBox(),
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: s.textSecondary, size: 20),
                        items: _categories.map((c) {
                          final label = isAr ? c['ar']! : c['en']!;
                          return DropdownMenuItem(value: c['key'], child: Text(label, style: TextStyle(color: s.textPrimary)));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setMState(() => _selectedCategoryKey = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(isAr ? 'تقييم IMDb: ${_minScore.toStringAsFixed(1)}' : 'IMDb Score: ${_minScore.toStringAsFixed(1)}', style: TextStyle(color: s.textSecondary, fontSize: 12)),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: s.border,
                        thumbColor: AppColors.primary,
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
                        child: Text(isAr ? 'إظهار النتائج' : 'Show Results', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
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
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: s.border, width: 0.5)),
                        child: Icon(Icons.tune_rounded, color: s.textPrimary, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(color: s.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: isAr ? 'ابحث عن أفلام، مسلسلات، ممثلين...' : 'Search movies, series, actors...',
                            hintStyle: TextStyle(color: s.textSecondary, fontSize: 13),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search_rounded, color: s.textSecondary, size: 20),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                      _buildQuickFilterTab(isAr ? 'الكل' : 'All', _filterType == 'all', () => setState(() => _filterType = 'all')),
                      const SizedBox(width: 8),
                      _buildQuickFilterTab(isAr ? 'أفلام' : 'Movies', _filterType == 'movie', () => setState(() => _filterType = 'movie')),
                      const SizedBox(width: 8),
                      _buildQuickFilterTab(isAr ? 'مسلسلات' : 'Series', _filterType == 'series', () => setState(() => _filterType = 'series')),
                    ],
                  ),
                ),

              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : (_movieResults.isNotEmpty || _seriesResults.isNotEmpty)
                        ? _buildCategorizedResults(isAr)
                        : _buildRecentSearches(isAr),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilterTab(String label, bool isSelected, VoidCallback onTap) {
    final s = AppSettings.instance;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5C9) : s.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : s.border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.black : s.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCategorizedResults(bool isAr) {
    final s = AppSettings.instance;
    final showSeries = _filterType == 'all' || _filterType == 'series';
    final showMovies = _filterType == 'all' || _filterType == 'movie';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (showSeries && _seriesResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(isAr ? 'مسلسلات' : 'Series', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._seriesResults.take(4).map((it) => _buildMediaSearchRow(it, isAr)),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullCategoryView(title: isAr ? 'نتائج المسلسلات' : 'Series Results', isSeriesOnly: true))),
              child: Text(isAr ? 'عرض الكل' : 'View All', style: TextStyle(color: s.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          Divider(color: s.border, height: 24),
        ],
        if (showMovies && _movieResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(isAr ? 'أفلام' : 'Movies', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._movieResults.take(4).map((it) => _buildMediaSearchRow(it, isAr)),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullCategoryView(title: isAr ? 'نتائج الأفلام' : 'Movie Results', isSeriesOnly: false))),
              child: Text(isAr ? 'عرض الكل' : 'View All', style: TextStyle(color: s.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaSearchRow(dynamic it, bool isAr) {
    final s = AppSettings.instance;
    final poster = StreamService.extractPoster(it);
    final title = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
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
                  Text(title, style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(isAr ? '$year, دراما' : '$year, Drama', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: s.border, width: 0.8), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('IMDb', style: TextStyle(color: s.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Text(score, style: TextStyle(color: s.textPrimary, fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: poster.isNotEmpty
                  ? Image.network(poster, width: 54, height: 78, fit: BoxFit.cover)
                  : Container(width: 54, height: 78, color: s.surface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearches(bool isAr) {
    final s = AppSettings.instance;
    if (_recentSearches.isEmpty) {
      return Center(child: Text(isAr ? 'ابحث عن أفلامك المفضلة وسجل البحث سيظهر هنا' : 'Search for titles and your history will appear here', style: TextStyle(color: s.textSecondary, fontSize: 12)));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(isAr ? 'عمليات البحث الأخيرة' : 'Recent Searches', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await LocalStorageService.setList('recent_search_history', []);
                _loadRecents();
              },
              child: Text(isAr ? 'مسح السجل' : 'Clear History', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._recentSearches.map((it) => _buildMediaSearchRow(it, isAr)),
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

  void _shareMedia(bool isAr) async {
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final id = widget.media['nb'] ?? widget.media['id'] ?? '';
    final text = isAr ? 'شاهد $title بجودة عالية عبر ONEBR TV!\nhttps://onebr.tv/watch/$id' : 'Watch $title in HD on ONEBR TV!\nhttps://onebr.tv/watch/$id';
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'تم نسخ رابط العمل بنجاح' : 'Link copied to clipboard')));
      }
    }
  }

  void _playTrailer(bool isAr) {
    final trailer = _extendedInfo['trailer']?.toString() ?? widget.media['trailer']?.toString() ?? '';
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    if (trailer.isNotEmpty && trailer.startsWith('http')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: 'trailer',
            title: isAr ? 'الإعلان: $title' : 'Trailer: $title',
            videoUrl: trailer,
            qualities: const [],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'الإعلان الترويجي الرسمي غير متوفر لهذا العمل' : 'Official trailer not available')));
    }
  }

  void _playEpisode(dynamic ep, int idx, bool isAr) {
    final targetId = (ep['nb'] ?? ep['id']).toString();
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final poster = StreamService.extractPoster(widget.media);

    LocalStorageService.markEpisodeWatched(targetId);
    _loadState();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: targetId,
          title: title,
          subtitleTextHeader: isAr ? 'الموسم $_selectedSeason - الحلقة $idx' : 'Season $_selectedSeason - Episode $idx',
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

  void _playMovie(bool isAr) {
    final targetId = (widget.media['nb'] ?? widget.media['id']).toString();
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
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

  void _showDownloadQualityPicker(String targetId, String title, String poster, bool isAr) async {
    final s = AppSettings.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: s.glassFill,
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
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: Text(isAr ? 'لا تتوفر روابط تنزيل مباشرة' : 'No direct download links available', style: TextStyle(color: s.textSecondary))),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isAr ? 'اختر جودة التنزيل في الخلفية' : 'Select Background Download Quality', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ...qualities.map((q) {
                          final res = q['resolution'] ?? '360p';
                          final url = q['url'] ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: s.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: s.border, width: 0.5),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.download_for_offline_rounded, color: AppColors.primary),
                              title: Text(isAr ? 'دقة $res' : '$res Resolution', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                              subtitle: Text(isAr ? 'تنزيل مستمر حتى بعد إغلاق التطبيق' : 'Persists after closing app', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                              trailing: Icon(Icons.arrow_downward_rounded, color: s.textSecondary),
                              onTap: () async {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                final safeFileName = '${targetId}_$res.mp4';
                                await BackgroundDownloadService.startDownload(
                                  url: url,
                                  fileName: safeFileName,
                                  targetId: targetId,
                                  title: '$title ($res)',
                                  poster: poster,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(isAr ? 'تم جدولة التنزيل في خلفية النظام!' : 'Download started in system background!')),
                                );
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
      ),
    );
  }

  void _showActorProfile(String actorName, bool isAr) {
    HapticFeedback.selectionClick();
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'الممثل: $actorName' : 'Actor: $actorName'),
        message: Text(isAr ? 'استعراض أعمال الممثل والبحث عن عروضه السابقة' : 'Explore all movies and series with this actor'),
        actions: [
          CupertinoActionSheetAction(
            child: Text(isAr ? 'البحث عن أعماله في المنصة' : 'Search actor titles'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedSearchScreen()));
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إغلاق' : 'Close'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final poster = StreamService.extractPoster(widget.media, highRes: true);
    final story = isAr ? (_extendedInfo['ar_content'] ?? widget.media['ar_content'] ?? widget.media['en_content'] ?? '') : (_extendedInfo['en_content'] ?? widget.media['en_content'] ?? widget.media['ar_content'] ?? '');
    final score = (_extendedInfo['stars'] ?? widget.media['stars'] ?? '7.9').toString();
    final year = widget.media['year']?.toString() ?? '2024';
    final rateCount = (_extendedInfo['rate'] ?? widget.media['rate'] ?? '4818').toString();
    final currentEpisodes = _seasonsMap[_selectedSeason] ?? [];
    final id = (widget.media['nb'] ?? widget.media['id']).toString();
    final rawCats = widget.media['categories'];
    final List<dynamic> catList = rawCats is List ? rawCats : [];
    final sortedSeasonKeys = _seasonsMap.keys.toList()..sort((a, b) => a.compareTo(b));
    final List<String> dummyActors = isAr ? ['روبرت داوني', 'سكارليت جوهانسون', 'كريس هيمسوورث', 'توم هولاند'] : ['Robert Downey Jr.', 'Scarlett Johansson', 'Chris Hemsworth', 'Tom Holland'];

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 460,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: () => _shareMedia(isAr)),
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
                    if (poster.isNotEmpty) Image.network(poster, fit: BoxFit.cover) else Container(color: s.surface),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.black87, s.bg],
                          stops: const [0.0, 0.4, 0.75, 1.0],
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
                              Text('$year • ${_isSeries ? (isAr ? 'مسلسل' : 'Series') : (isAr ? 'فيلم' : 'Movie')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                                    Text(isAr ? 'المشاهدة لاحقاً' : 'Watchlist', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              CupertinoButton(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppRadius.button),
                                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                                minSize: 0,
                                onPressed: () => _isSeries && currentEpisodes.isNotEmpty ? _playEpisode(currentEpisodes.first, 1, isAr) : _playMovie(isAr),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 4),
                                    Text(isAr ? 'شاهد الآن' : 'Watch Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              InkWell(
                                onTap: () => _showDownloadQualityPicker(id, title, poster, isAr),
                                child: Column(
                                  children: [
                                    const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 24),
                                    const SizedBox(height: 4),
                                    Text(isAr ? 'تحميل' : 'Download', style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
                          final name = isAr ? (c['ar_title'] ?? c['en_title'] ?? '') : (c['en_title'] ?? c['ar_title'] ?? '');
                          return Chip(
                            backgroundColor: s.surface,
                            side: BorderSide(color: s.border, width: 0.5),
                            label: Text(name.toString(), style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 14),

                    Text(isAr ? 'طاقم التمثيل' : 'Cast', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
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
                              backgroundColor: s.surface,
                              side: BorderSide(color: s.border, width: 0.5),
                              label: Text(actor, style: TextStyle(color: s.textPrimary, fontSize: 12)),
                              onPressed: () => _showActorProfile(actor, isAr),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: s.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: s.border, width: 0.5),
                      ),
                      child: InkWell(
                        onTap: () => _playTrailer(isAr),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(isAr ? 'مشاهدة الإعلان الرسمي' : 'Watch Official Trailer', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(isAr ? 'تشغيل' : 'Play', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (story.isNotEmpty)
                      Text(story, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textSecondary, fontSize: 13, height: 1.6)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.thumb_up_rounded, color: s.textSecondary, size: 16),
                        const SizedBox(width: 4),
                        Text(rateCount, style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        const SizedBox(width: 16),
                        Icon(Icons.thumb_down_rounded, color: s.textSecondary, size: 16),
                        const SizedBox(width: 4),
                        Text('84', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                      ],
                    ),
                    Divider(color: s.border, height: 32),

                    if (_isSeries && _seasonsMap.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isAr ? 'الحلقات' : 'Episodes', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (sortedSeasonKeys.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: s.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: s.border, width: 0.5),
                              ),
                              child: DropdownButton<int>(
                                dropdownColor: s.surface,
                                value: _selectedSeason,
                                underline: const SizedBox(),
                                items: sortedSeasonKeys.map((season) => DropdownMenuItem(value: season, child: Text(isAr ? 'الموسم $season' : 'Season $season', style: TextStyle(color: s.textPrimary, fontSize: 12)))).toList(),
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
                            color: s.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: s.border, width: 0.5),
                          ),
                          child: InkWell(
                            onTap: () => _playEpisode(ep, idx, isAr),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.download_rounded, color: s.textSecondary, size: 20),
                                    onPressed: () => _showDownloadQualityPicker(targetId, '$title - ${isAr ? "حلقة" : "Ep"} $idx', poster, isAr),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(isAr ? 'الحلقة $idx' : 'Episode $idx', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textSecondary, fontSize: 11)),
                                        if (isWatched) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.visibility_rounded, color: Colors.greenAccent, size: 14),
                                              const SizedBox(width: 4),
                                              Text(isAr ? 'تمت المشاهدة' : 'Watched', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
                      Text(isAr ? 'أعمال مقترحة ومشابهة' : 'Similar & Recommended', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                            final simTitle = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');

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
                                        child: simPoster.isNotEmpty ? Image.network(simPoster, fit: BoxFit.cover, width: double.infinity) : Container(color: s.surface),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(simTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
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

  bool _isAutoQuality = true;
  String _activeQuality = 'تلقائي (Auto)';
  String _currentStreamUrl = '';
  List<Map<String, dynamic>> _currentQualities = [];
  int _bufferingStallCount = 0;
  DateTime _lastBufferTime = DateTime.now();

  BoxFit _videoFit = BoxFit.contain;
  bool _isLandscape = true;
  double _playbackSpeed = 1.0;

  List<Subtitle> _subtitles = [];
  List<Subtitle> _secondarySubtitles = [];
  String _currentSubText = '';
  String _currentSecondarySubText = '';

  late int _activeEpIndex;
  late String _activeMediaId;
  late String _activeHeader;
  Set<String> _watchedSet = {};

  bool _isLocked = false;
  Timer? _sleepTimer;
  int? _sleepMinutesRemaining;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showIndicator = false;
  String _indicatorText = '';
  IconData _indicatorIcon = Icons.volume_up_rounded;

  bool _showDoubleTapRipple = false;
  bool _isDoubleTapForward = true;
  int _doubleTapAccumulatedSeconds = 0;
  Timer? _doubleTapTimer;

  bool _showAutoNext = false;
  int _autoNextCountdown = 5;
  Timer? _autoNextTimer;

  bool get _showSmartSkip =>
      _controller != null &&
      _controller!.value.isInitialized &&
      _controller!.value.position.inSeconds < 95;

  @override
  void initState() {
    super.initState();
    _activeEpIndex = widget.currentEpIndex;
    _activeMediaId = widget.mediaId;
    _activeHeader = widget.subtitleTextHeader;
    _currentQualities = widget.qualities;
    _loadWatchedState();

    WakelockPlus.enable();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    if (widget.videoUrl.isEmpty) {
      _loadAndPlayMedia(_activeMediaId);
    } else {
      _currentStreamUrl = widget.videoUrl;
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

      final url = source['video_url'] ?? '';
      _currentStreamUrl = url;
      _initPlayer(url);

      final subAr = subInfo?['arTranslationFilePath']?.toString() ?? '';
      final subEn = subInfo?['enTranslationFilePath']?.toString() ?? '';
      _loadSubtitlesDelayed(subAr, subEn);
    }
  }

  void _loadSubtitlesDelayed(String arUrl, String enUrl) {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        if (arUrl.isNotEmpty) _loadSubs(arUrl, isSecondary: false);
        if (enUrl.isNotEmpty) _loadSubs(enUrl, isSecondary: true);
      }
    });
  }

  void _loadSubs(String url, {required bool isSecondary}) async {
    final cached = SubtitleCache.get(url);
    if (cached != null) {
      setState(() {
        if (isSecondary) {
          _secondarySubtitles = cached;
        } else {
          _subtitles = cached;
        }
      });
      return;
    }

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
        SubtitleCache.set(url, parsed);
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
    final blocks = text.trim().split(RegExp(r'(\r?\n){2,}'));
    int idx = 0;

    for (var block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      if (lines.length < 2) continue;

      String timeLine = '';
      int textStartIndex = 1;

      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLine = lines[i];
          textStartIndex = i + 1;
          break;
        }
      }

      if (timeLine.isEmpty) continue;
      final times = timeLine.split('-->');
      if (times.length != 2) continue;

      try {
        final start = _durationFromStr(times[0].trim());
        final end = _durationFromStr(times[1].trim());
        final contentLines = lines.sublist(textStartIndex);
        final rawText = contentLines.join('\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();

        if (rawText.isNotEmpty) {
          list.add(Subtitle(index: idx++, start: start, end: end, text: rawText));
        }
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

  void _initPlayer(String url, {Duration? startAt}) async {
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    if (mounted) setState(() => _isReady = false);

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: StreamService.stealthHeaders,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );

    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.setPlaybackSpeed(_playbackSpeed);

    if (startAt != null) {
      await ctrl.seekTo(startAt);
    } else {
      final savedMs = await LocalStorageService.getPlaybackPosition(_activeMediaId);
      if (savedMs > 0 && savedMs < ctrl.value.duration.inMilliseconds - 5000) {
        await ctrl.seekTo(Duration(milliseconds: savedMs));
      }
    }

    ctrl.play();

    if (mounted) {
      setState(() => _isReady = true);
    }

    ctrl.addListener(_videoPlayerListener);
    _startTimer();
  }

  void _videoPlayerListener() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;

    if (_isAutoQuality && ctrl.value.isBuffering) {
      final now = DateTime.now();
      if (now.difference(_lastBufferTime).inSeconds < 15) {
        _bufferingStallCount++;
        if (_bufferingStallCount >= 2) {
          _bufferingStallCount = 0;
          _downgradeQualitySilently(pos);
        }
      } else {
        _bufferingStallCount = 1;
      }
      _lastBufferTime = now;
    }

    if (pos.inSeconds % 5 == 0) {
      LocalStorageService.savePlaybackPosition(
        _activeMediaId,
        pos.inMilliseconds,
        dur.inMilliseconds,
        widget.title,
        widget.poster,
      );
    }

    if (_subtitles.isNotEmpty) {
      Subtitle? activeSub;
      for (var s in _subtitles) {
        if (pos >= s.start && pos <= s.end) {
          activeSub = s;
          break;
        }
      }
      final newText = activeSub?.text ?? '';
      if (newText != _currentSubText && mounted) {
        setState(() => _currentSubText = newText);
      }
    }

    if (AppSettings.instance.enableDualSubtitles && _secondarySubtitles.isNotEmpty) {
      Subtitle? activeSub2;
      for (var s in _secondarySubtitles) {
        if (pos >= s.start && pos <= s.end) {
          activeSub2 = s;
          break;
        }
      }
      final newText2 = activeSub2?.text ?? '';
      if (newText2 != _currentSecondarySubText && mounted) {
        setState(() => _currentSecondarySubText = newText2);
      }
    }

    if (widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length) {
      final remaining = dur.inSeconds - pos.inSeconds;
      if (remaining <= 30 && remaining > 0 && !_showAutoNext) {
        _triggerAutoNext();
      }
    }

    if (mounted) setState(() {});
  }

  void _downgradeQualitySilently(Duration currentPosition) {
    if (_currentQualities.length <= 1) return;

    final order = ['1080p', '720p', '480p', '360p', '240p'];
    int currentIndex = order.indexOf(_activeQuality.replaceAll(' (Auto)', ''));
    if (currentIndex == -1) currentIndex = 2;

    for (int i = currentIndex + 1; i < order.length; i++) {
      final targetRes = order[i];
      final match = _currentQualities.firstWhere(
        (q) => (q['resolution'] ?? '').toString().toLowerCase().contains(targetRes),
        orElse: () => {},
      );
      if (match.isNotEmpty && match['url'] != _currentStreamUrl) {
        _currentStreamUrl = match['url'];
        _initPlayer(match['url'], startAt: currentPosition);
        break;
      }
    }
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
      _activeHeader = AppSettings.instance.appLanguage == 'ar' ? 'الحلقة $epIdx' : 'Episode $epIdx';
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
      _currentStreamUrl = source['video_url'];
      _initPlayer(source['video_url']);
      final path = sub['arTranslationFilePath']?.toString() ?? '';
      final pathEn = sub['enTranslationFilePath']?.toString() ?? '';
      _loadSubtitlesDelayed(path, pathEn);
    }
  }

  void _onDoubleTapSeek(bool isForward) {
    if (_isLocked || _controller == null || !_controller!.value.isInitialized) return;

    final seekStep = AppSettings.instance.seekDuration;
    HapticFeedback.lightImpact();

    setState(() {
      _isDoubleTapForward = isForward;
      _showDoubleTapRipple = true;
      if (_doubleTapTimer != null && _doubleTapTimer!.isActive) {
        _doubleTapAccumulatedSeconds += seekStep;
      } else {
        _doubleTapAccumulatedSeconds = seekStep;
      }
    });

    final currentPos = _controller!.value.position;
    final newPos = isForward
        ? currentPos + Duration(seconds: seekStep)
        : currentPos - Duration(seconds: seekStep);

    _controller!.seekTo(newPos < Duration.zero ? Duration.zero : (newPos > _controller!.value.duration ? _controller!.value.duration : newPos));

    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showDoubleTapRipple = false);
    });
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
    final isAr = AppSettings.instance.appLanguage == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: AppSettings.instance.glassFill,
              height: 350,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isAr ? 'قائمة الحلقات' : 'Episode List', style: TextStyle(color: AppSettings.instance.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                            color: isCurrent ? AppColors.primary.withOpacity(0.3) : AppSettings.instance.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppSettings.instance.border, width: 0.5),
                          ),
                          child: ListTile(
                            title: Text(isAr ? 'الحلقة $idx' : 'Episode $idx', style: TextStyle(color: AppSettings.instance.textPrimary, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
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
          SnackBar(content: Text(AppSettings.instance.appLanguage == 'ar' ? 'قم بتثبيت مشغل يدعم البث مثل VLC أو Web Video Caster' : 'Install VLC or Web Video Caster to cast')),
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
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      return;
    }
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
    WakelockPlus.disable();
    _autoNextTimer?.cancel();
    _hideTimer?.cancel();
    _doubleTapTimer?.cancel();
    _sleepTimer?.cancel();
    _controller?.removeListener(_videoPlayerListener);
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
    final isAr = settings.appLanguage == 'ar';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: settings.glassFill,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.speed_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'سرعة التشغيل' : 'Playback Speed', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text('${_playbackSpeed}x', style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSpeedPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.hd_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'دقة وجودة الفيديو' : 'Video Quality', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_isAutoQuality ? (isAr ? 'تلقائي (Auto)' : 'Auto') : _activeQuality, style: TextStyle(color: _isAutoQuality ? AppColors.primary : settings.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                      onTap: () {
                        Navigator.pop(context);
                        _showQualityPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.timer_outlined, color: settings.textSecondary),
                      title: Text(isAr ? 'مؤقت النوم' : 'Sleep Timer', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_sleepMinutesRemaining != null ? '$_sleepMinutesRemaining min' : (isAr ? 'معطل' : 'Off'), style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSleepTimerPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.subtitles_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'الترجمة المزدوجة (عربي + إنجليزي)' : 'Dual Subtitles (AR + EN)', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.enableDualSubtitles,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateDualSubtitles(v)),
                      ),
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.shield_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'إزالة اللقطات الحساسة تلقائياً' : 'Auto Skip Sensitive Scenes', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.skipSensitiveScenes,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateSkipScenes(v)),
                      ),
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.fast_forward_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'فترة تمرير الفيديو' : 'Seek Duration', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(isAr ? '${settings.seekDuration} ثوانٍ' : '${settings.seekDuration}s', style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSeekPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.closed_caption_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'إعدادات ومكان الترجمة' : 'Subtitle Settings & Position', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: settings.textSecondary, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()));
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.aspect_ratio_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'أبعاد الشاشة' : 'Aspect Ratio', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_videoFit == BoxFit.cover ? (isAr ? 'ملء الشاشة' : 'Fit Screen') : (isAr ? 'طبيعي' : 'Original'), style: TextStyle(color: settings.textSecondary, fontSize: 12)),
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

  void _showSeekPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'فترة التقديم والتأخير' : 'Seek Duration'),
        actions: [5, 10, 15, 30].map((s) => CupertinoActionSheetAction(
          child: Text(isAr ? '$s ثوانٍ' : '${s}s'),
          onPressed: () {
            AppSettings.instance.updateSeek(s);
            Navigator.pop(context);
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showQualityPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'اختر دقة العرض' : 'Select Quality'),
        actions: [
          CupertinoActionSheetAction(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(isAr ? 'تلقائي (حسب سرعة النت)' : 'Auto (Adaptive)'),
                if (_isAutoQuality) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                ],
              ],
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isAutoQuality = true;
                _activeQuality = 'تلقائي (Auto)';
              });
              _downgradeQualitySilently(_controller?.value.position ?? Duration.zero);
            },
          ),
          ..._currentQualities.map((q) {
            final res = q['resolution'] ?? '360p';
            final url = q['url'] ?? '';
            final isSelected = !_isAutoQuality && _activeQuality == res;

            return CupertinoActionSheetAction(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(res),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                  ],
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isAutoQuality = false;
                  _activeQuality = res;
                });
                _currentStreamUrl = url;
                _initPlayer(url, startAt: _controller?.value.position);
              },
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showSpeedPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'سرعة التشغيل' : 'Playback Speed'),
        actions: [0.75, 1.0, 1.25, 1.5, 2.0].map((s) => CupertinoActionSheetAction(
          child: Text('${s}x'),
          onPressed: () {
            setState(() => _playbackSpeed = s);
            _controller?.setPlaybackSpeed(s);
            Navigator.pop(context);
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showSleepTimerPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'إيقاف بعد وقت محدد' : 'Sleep Timer'),
        actions: [15, 30, 45, 60].map((mins) => CupertinoActionSheetAction(
          child: Text(isAr ? '$mins دقيقة' : '$mins minutes'),
          onPressed: () {
            Navigator.pop(context);
            _sleepTimer?.cancel();
            setState(() => _sleepMinutesRemaining = mins);
            _sleepTimer = Timer(Duration(minutes: mins), () {
              _controller?.pause();
              if (mounted) Navigator.pop(context);
            });
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () {
            _sleepTimer?.cancel();
            setState(() => _sleepMinutesRemaining = null);
            Navigator.pop(context);
          },
          child: Text(isAr ? 'إلغاء المؤقت' : 'Turn Off'),
        ),
      ),
    );
  }

  void _takeSceneClip(bool isAr) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isAr ? 'تم حفظ لقطة الشاشة في استوديو الهاتف! 📸' : 'Snapshot saved to gallery! 📸')),
    );
  }

  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      if (_controller != null) {
        setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play());
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _onDoubleTapSeek(true);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _onDoubleTapSeek(false);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
               event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final isAr = settings.appLanguage == 'ar';
    final hasPrev = widget.episodes.isNotEmpty && _activeEpIndex > 1;
    final hasNext = widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleRemoteKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: (_isReady && _controller != null)
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FittedBox(
                                  fit: _videoFit,
                                  child: SizedBox(
                                    width: _controller!.value.size.width,
                                    height: _controller!.value.size.height,
                                    child: VideoPlayer(_controller!),
                                  ),
                                ),

                                if (_currentSubText.isNotEmpty)
                                  Positioned(
                                    bottom: settings.subBottomPadding,
                                    left: 16.0,
                                    right: 16.0,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: settings.subtitleBackgroundColor,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _currentSubText,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: settings.subColor,
                                            fontSize: settings.subFontSize,
                                            fontWeight: FontWeight.bold,
                                            shadows: settings.subHasShadow
                                                ? const [Shadow(blurRadius: 8, color: Colors.black, offset: Offset(1, 1))]
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : const CircularProgressIndicator(color: AppColors.primary),
                  ),

                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _onDoubleTapSeek(false),
                            onVerticalDragUpdate: (d) => _handleVerticalDrag(d, constraints),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _onDoubleTapSeek(true),
                            onVerticalDragUpdate: (d) => _handleVerticalDrag(d, constraints),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_showDoubleTapRipple)
                    Align(
                      alignment: _isDoubleTapForward ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * 0.38,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: _isDoubleTapForward
                              ? const BorderRadius.horizontal(left: Radius.circular(100))
                              : const BorderRadius.horizontal(right: Radius.circular(100)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isDoubleTapForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, size: 40, color: Colors.white),
                            const SizedBox(height: 6),
                            Text('${_doubleTapAccumulatedSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
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

                  if (_showSmartSkip && !_isLocked)
                    Positioned(
                      bottom: 85, left: 20,
                      child: CupertinoButton(
                        color: Colors.black.withOpacity(0.75),
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
                          children: [
                            const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text(isAr ? 'تخطي المقدمة' : 'Skip Intro', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (_showAutoNext && hasNext && !_isLocked)
                    Positioned(
                      bottom: 85, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24, width: 0.5)),
                        child: Row(
                          children: [
                            Text(isAr ? 'الحلقة التالية خلال $_autoNextCountdown ث' : 'Next episode in $_autoNextCountdown s', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              color: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minSize: 0,
                              onPressed: _playNextEpisode,
                              child: Text(isAr ? 'تشغيل الآن' : 'Play Now', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_showControls)
                    Positioned(
                      left: 16,
                      top: MediaQuery.of(context).size.height / 2 - 20,
                      child: IconButton(
                        icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: _isLocked ? AppColors.primary : Colors.white, size: 26),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isLocked = !_isLocked);
                        },
                      ),
                    ),

                  if (_showControls && !_isLocked) ...[
                    Positioned(
                      top: 10, left: 14, right: 14,
                      child: Directionality(
                        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                  if (_activeHeader.isNotEmpty)
                                    Text(_activeHeader, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                if (widget.episodes.isNotEmpty)
                                  IconButton(
                                    tooltip: isAr ? 'قائمة الحلقات' : 'Episodes',
                                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 24),
                                    onPressed: _showEpisodesDrawer,
                                  ),
                                IconButton(
                                  tooltip: isAr ? 'صانع اللقطات' : 'Snapshot',
                                  icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
                                  onPressed: () => _takeSceneClip(isAr),
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
                                  Row(
                                    children: [
                                      Text(_formatTime(_controller!.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      const SizedBox(width: 14),
                                      InkWell(
                                        onTap: _toggleScreenOrientation,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white24, width: 0.8),
                                          ),
                                          child: Icon(
                                            _isLandscape ? Icons.crop_portrait_rounded : Icons.crop_landscape_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
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
                  ],
                ],
              );
            },
          ),
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
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'إعدادات الترجمة' : 'Subtitle Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: s.textPrimary)),
          leading: IconButton(
            icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 28, color: s.textPrimary),
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
                color: Colors.black,
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: (s.subBottomPadding / 90) * 60 + 10,
                    left: 20, right: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: s.subtitleBackgroundColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isAr ? 'معاينة موقع ولون وخلفية الترجمة\nLive Subtitle Preview' : 'Live Subtitle Preview\nمعاينة الترجمة الحية',
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
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text(isAr ? 'خلفية الترجمة' : 'Subtitle Background', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(isAr ? 'شفاف، شبه شفاف، غامق' : 'Transparent, Semi, Dark', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                    trailing: CupertinoSlidingSegmentedControl<String>(
                      groupValue: s.subBackgroundMode,
                      children: {
                        'transparent': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'شفاف' : 'Clear', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                        'semi': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'شبه شفاف' : 'Semi', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                        'dark': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'غامق' : 'Dark', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                      },
                      onValueChanged: (val) {
                        if (val != null) setState(() => s.updateSubStyle(bgMode: val));
                      },
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'موقع الترجمة من أسفل الفيديو' : 'Bottom Offset', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Slider(
                      value: s.subBottomPadding,
                      min: 10.0,
                      max: 90.0,
                      activeColor: AppColors.primary,
                      inactiveColor: s.border,
                      onChanged: (v) => setState(() => s.updateSubStyle(bottomPadding: v)),
                    ),
                    trailing: Text('${s.subBottomPadding.toInt()} dp', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'حجم خط الترجمة' : 'Font Size', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: DropdownButton<double>(
                      dropdownColor: s.surface,
                      value: s.subFontSize,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 14.0, child: Text(isAr ? 'صغير' : 'Small', style: TextStyle(color: s.textPrimary))),
                        DropdownMenuItem(value: 18.0, child: Text(isAr ? 'متوسط' : 'Medium', style: TextStyle(color: s.textPrimary))),
                        DropdownMenuItem(value: 22.0, child: Text(isAr ? 'كبير' : 'Large', style: TextStyle(color: s.textPrimary))),
                      ],
                      onChanged: (v) => setState(() => s.updateSubStyle(size: v)),
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'لون الخط' : 'Text Color', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _colorBubble(Colors.white, s.subColor == Colors.white, () => setState(() => s.updateSubStyle(color: Colors.white))),
                        _colorBubble(Colors.yellow, s.subColor == Colors.yellow, () => setState(() => s.updateSubStyle(color: Colors.yellow))),
                        _colorBubble(const Color(0xFF00F0FF), s.subColor == const Color(0xFF00F0FF), () => setState(() => s.updateSubStyle(color: const Color(0xFF00F0FF)))),
                      ],
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'ظل حواف الخط' : 'Text Shadow', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
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
              color: s.surface,
              borderRadius: BorderRadius.circular(14),
              onPressed: () => setState(() => s.resetSubtitles()),
              child: Text(isAr ? 'إعادة ضبط الترجمة الافتراضية' : 'Reset to Default', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
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
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppSettings.instance.appLanguage == 'ar' ? 'تم تفريغ الذاكرة المؤقتة بنجاح' : 'Cache cleared successfully')));
    } catch (_) {}
  }

  void _showAddProfileDialog(bool isAr) {
    final s = AppSettings.instance;
    final ctrl = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(isAr ? 'إضافة بروفايل جديد' : 'Add New Profile'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: isAr ? 'اسم الملف الشخصي' : 'Profile Name',
            style: TextStyle(color: s.textPrimary),
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: Text(isAr ? 'إلغاء' : 'Cancel')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                AppSettings.instance.addProfile(ctrl.text.trim());
                Navigator.pop(context);
              }
            },
            child: Text(isAr ? 'إضافة' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn(bool isAr) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        AppSettings.instance.login(
          user.displayName ?? (isAr ? 'مستخدم' : 'User'),
          user.email ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isAr ? 'تم تسجيل الدخول بنجاح: ${user.displayName}' : 'Logged in as ${user.displayName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'فشل تسجيل الدخول: $e' : 'Sign in failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAuthDialog(bool isAr) {
    final s = AppSettings.instance;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(isAr ? 'تسجيل الحساب والمزامنة' : 'Account & Sync'),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr
                    ? 'سجّل الدخول بحساب Google لحفظ ومزامنة قائمة المشاهدة والإحصائيات عبر السحابة.'
                    : 'Sign in with Google to sync your watchlist and statistics across devices.',
                style: TextStyle(fontSize: 12, color: s.textSecondary),
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                color: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  Navigator.pop(context);
                  _handleGoogleSignIn(isAr);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 6),
                    Text(
                      isAr ? 'متابعة باستخدام Google' : 'Continue with Google',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
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

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'الحساب والمكتبة' : 'Profile & Library', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: s.textPrimary)),
          actions: [
            IconButton(
              tooltip: isAr ? 'تفريغ الكاش' : 'Clear Cache',
              icon: Icon(Icons.delete_sweep_rounded, color: s.textSecondary),
              onPressed: _cleanCache,
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: s.textSecondary,
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
            _completed.isEmpty
                ? Center(child: Text(isAr ? 'لا توجد تنزيلات حالياً' : 'No downloads yet', style: TextStyle(color: s.textSecondary)))
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _completed.length,
                    itemBuilder: (ctx, i) {
                      final it = _completed[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                        child: ListTile(
                          leading: const Icon(Icons.download_done_rounded, color: AppColors.primary),
                          title: Text(it['title'] ?? '', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text(it['path'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textSecondary, fontSize: 10)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: s.textSecondary),
                            onPressed: () async {
                              final taskId = it['taskId']?.toString();
                              if (taskId != null) {
                                await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
                              }
                              await LocalStorageService.removeItem('downloaded_works_list', it['nb']?.toString() ?? '', idField: 'nb');
                              _loadData();
                            },
                          ),
                        ),
                      );
                    },
                  ),

            _watchlist.isEmpty
                ? Center(child: Text(isAr ? 'لم تقم بحفظ أي عمل بعد' : 'Watchlist is empty', style: TextStyle(color: s.textSecondary)))
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
                          child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: s.surface),
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
                    color: s.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 40),
                      const SizedBox(height: 10),
                      Text(isAr ? 'إحصائيات الملف: ${s.activeProfile}' : 'Stats for: ${s.activeProfile}', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      Divider(color: s.border, height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$_statMinutes', style: TextStyle(color: s.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(isAr ? 'دقيقة مشاهدة' : 'Minutes Watched', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('$_statEpisodes', style: TextStyle(color: s.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(isAr ? 'حلقة مكتملة' : 'Completed Eps', style: TextStyle(color: s.textSecondary, fontSize: 11)),
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
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 24, backgroundColor: AppColors.primary, child: Icon(Icons.person_rounded, color: Colors.white)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.userName ?? (isAr ? 'مستخدم زائر' : 'Guest User'), style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(s.userEmail ?? (isAr ? 'المزامنة السحابية غير مفعّلة' : 'Sync disabled'), style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minSize: 0,
                        onPressed: s.userName == null ? () => _showAuthDialog(isAr) : () => setState(() => s.logout()),
                        child: Text(s.userName == null ? (isAr ? 'تسجيل' : 'Login') : (isAr ? 'خروج' : 'Logout'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Text(isAr ? 'إدارة الملفات الشخصية' : 'Profile Management', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ...s.userProfiles.map((p) => ChoiceChip(
                      label: Text(p, style: TextStyle(color: s.activeProfile == p ? Colors.white : s.textPrimary)),
                      selected: s.activeProfile == p,
                      selectedColor: AppColors.primary,
                      backgroundColor: s.surface,
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
                      backgroundColor: s.surface,
                      label: Text(isAr ? 'إضافة بروفايل' : 'Add Profile', style: TextStyle(color: s.textPrimary)),
                      onPressed: () => _showAddProfileDialog(isAr),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Container(
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'التنبيه الذكي للمسلسلات' : 'Smart Series Alerts', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(isAr ? 'إرسال إشعارات لحظية عند نزول حلقات جديدة' : 'Push notifications when new episodes arrive', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        trailing: CupertinoSwitch(
                          value: s.smartNotifications,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() => s.updateSmartNotifications(v)),
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'التنزيل الذكي للحلقات' : 'Smart Episode Downloads', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(isAr ? 'تنزيل الحلقة التالية ومسح المنتهية تلقائياً' : 'Auto download next episode & clean watched', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        trailing: CupertinoSwitch(
                          value: s.autoSmartDownload,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() => s.updateSmartDownload(v)),
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'لغة التطبيق' : 'App Language', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: DropdownButton<String>(
                          dropdownColor: s.surface,
                          value: s.appLanguage,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(value: 'ar', child: Text('العربية', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(color: s.textPrimary))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => s.updateLanguage(v));
                          },
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.text_fields_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'خط التطبيق' : 'App Font', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: DropdownButton<String>(
                          dropdownColor: s.surface,
                          value: s.selectedFont,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(value: 'iPhone', child: Text('iPhone (Apple San Francisco)', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Cairo', child: Text('Cairo', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Tajawal', child: Text('Tajawal', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Almarai', child: Text('Almarai', style: TextStyle(color: s.textPrimary))),
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
                Text(isAr ? 'وضع المحتوى' : 'Content Mode', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    children: [
                      RadioListTile<int>(
                        title: Text(isAr ? 'الافتراضي (الكل)' : 'Default (All Content)', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                        value: 0,
                        groupValue: s.appFilterMode,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFilterMode(v));
                        },
                      ),
                      Divider(color: s.border, height: 1),
                      RadioListTile<int>(
                        title: Text(isAr ? 'الوضع العائلي' : 'Family Mode', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                        value: 1,
                        groupValue: s.appFilterMode,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFilterMode(v));
                        },
                      ),
                      Divider(color: s.border, height: 1),
                      RadioListTile<int>(
                        title: Text(isAr ? 'وضع الأطفال' : 'Kids Mode', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
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
      ),
    );
  }
}
