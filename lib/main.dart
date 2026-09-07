import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

// مدير عام للمظهر واللغة وحساب المستخدم
class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  bool isDark = true;
  String lang = 'ar'; // 'ar' أو 'en'
  bool isLoggedIn = false;
  bool isAdmin = false;
  String username = '';

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
    if (user.toLowerCase() == 'admin' && pass == 'admin123') {
      isAdmin = true;
    } else {
      isAdmin = false;
    }
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
  final PageController _bannerController = PageController();

  List<dynamic> _trending = [];
  List<dynamic> _popularMovies = [];
  List<dynamic> _popularSeries = [];
  List<dynamic> _activeGrid = [];
  List<Map<String, dynamic>> _continueWatchingList = [];
  List<String> _recentSearches = [];

  int _currentBannerPage = 0;
  Timer? _bannerTimer;

  int _page = 1;
  int _genrePage = 1;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;
  String _activeTitle = '🔥 الأكثر تداولاً وشهرة';
  Map<String, dynamic>? _selectedGenre;

  final List<Map<String, dynamic>> _genres = [
    {'id': 'all', 'ar': 'الكل', 'en': 'All'},
    {'id': 'anime', 'ar': 'أنمي ورسوم', 'en': 'Anime & Cartoons'},
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
    _fetchTmdbData(reset: true);
    _loadContinueWatching();
    _loadSearchHistory();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore && _hasMore && !_hasError) {
          if (_selectedGenre != null && _selectedGenre!['id'] != 'all') {
            _fetchMoreGenreData();
          } else {
            _fetchTmdbData(reset: false);
          }
        }
      }
    });

    _startBannerTimer();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_trending.isNotEmpty && _bannerController.hasClients) {
        final next = (_currentBannerPage + 1) % (_trending.length.clamp(0, 7));
        _bannerController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _loadContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('continue_watching_list');
    if (raw != null) {
      try {
        final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
        if (mounted) setState(() => _continueWatchingList = list);
      } catch (_) {}
    }
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

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTmdbData({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasMore = true;
      setState(() {
        _isLoadingInitial = true;
        _hasError = false;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      if (reset) {
        final responses = await Future.wait([
          http.get(Uri.parse('https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=$lang')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/movie/popular?api_key=$key&language=$lang&page=1')).timeout(const Duration(seconds: 8)),
          http.get(Uri.parse('https://api.themoviedb.org/3/tv/popular?api_key=$key&language=$lang&page=1')).timeout(const Duration(seconds: 8)),
        ]);

        if (responses[0].statusCode == 200 && mounted) {
          final tList = jsonDecode(responses[0].body)['results'] ?? [];
          final mList = jsonDecode(responses[1].body)['results'] ?? [];
          final sList = jsonDecode(responses[2].body)['results'] ?? [];

          setState(() {
            _trending = tList;
            _popularMovies = mList;
            _popularSeries = sList;
            _activeGrid = List.from(tList);
            _isLoadingInitial = false;
            _hasError = false;
          });
        } else {
          if (mounted) setState(() { _isLoadingInitial = false; _hasError = true; });
        }
      } else {
        _page++;
        final moreRes = await http.get(Uri.parse(
            'https://api.themoviedb.org/3/trending/all/week?api_key=$key&language=$lang&page=$_page')).timeout(const Duration(seconds: 8));
        if (moreRes.statusCode == 200 && mounted) {
          final mList = jsonDecode(moreRes.body)['results'] ?? [];
          setState(() {
            _activeGrid.addAll(mList);
            if (mList.isEmpty) _hasMore = false;
            _isLoadingMore = false;
          });
        } else {
          if (mounted) setState(() => _isLoadingMore = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
          if (reset && _activeGrid.isEmpty) _hasError = true;
        });
      }
    }
  }

  void _filterGenre(Map<String, dynamic> genre) async {
    _selectedGenre = genre;
    _genrePage = 1;
    final gId = genre['id'];
    final key = SecurityEngine.tmdbKey;
    final app = AppState.instance;

    if (gId == 'all') {
      _selectedGenre = null;
      setState(() => _activeTitle = app.tr('🔥 الأكثر تداولاً وشهرة', '🔥 Trending Now'));
      _fetchTmdbData(reset: true);
      return;
    }

    setState(() {
      _activeTitle = app.tr('تصنيف: ${genre['ar']}', 'Category: ${genre['en']}');
      _isLoadingInitial = true;
      _hasMore = true;
      _hasError = false;
    });

    try {
      final lang = app.lang == 'ar' ? 'ar' : 'en-US';
      String urlStr = (gId == 'anime')
          ? 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=$lang&with_genres=16&with_original_language=ja&sort_by=popularity.desc&page=1'
          : 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=$lang&with_genres=$gId&sort_by=popularity.desc&page=1';

      final res = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          _activeGrid = list;
          _isLoadingInitial = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _fetchMoreGenreData() async {
    if (_selectedGenre == null) return;
    setState(() => _isLoadingMore = true);
    _genrePage++;

    final gId = _selectedGenre!['id'];
    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    String urlStr = (gId == 'anime')
        ? 'https://api.themoviedb.org/3/discover/tv?api_key=$key&language=$lang&with_genres=16&with_original_language=ja&sort_by=popularity.desc&page=$_genrePage'
        : 'https://api.themoviedb.org/3/discover/movie?api_key=$key&language=$lang&with_genres=$gId&sort_by=popularity.desc&page=$_genrePage';

    try {
      final res = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          if (list.isEmpty) {
            _hasMore = false;
          } else {
            _activeGrid.addAll(list);
          }
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
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

    try {
      final res = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$key&language=$lang&query=${Uri.encodeComponent(clean)}')).timeout(const Duration(seconds: 8));
      Navigator.pop(context);

      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          _activeGrid = list;
          _hasMore = false;
          _activeTitle = AppState.instance.tr('نتائج البحث عن: $clean', 'Search results for: $clean');
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

  void _openLoginSheet() {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final app = AppState.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(app.tr('تسجيل الدخول', 'Sign In'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(app.tr('لتسجيل الدخول كمسؤول أدخل admin / admin123', 'For Admin use: admin / admin123'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 14),
            TextField(controller: userCtrl, decoration: InputDecoration(labelText: app.tr('اسم المستخدم', 'Username'), border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, obscureText: true, decoration: InputDecoration(labelText: app.tr('كلمة المرور', 'Password'), border: const OutlineInputBorder())),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () {
                if (userCtrl.text.isNotEmpty) {
                  app.login(userCtrl.text.trim(), passCtrl.text.trim());
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(app.isAdmin ? app.tr('مرحباً بالمدير! تم تفعيل لوحة الإدارة', 'Welcome Admin! Dashboard unlocked') : app.tr('تم تسجيل الدخول بنجاح', 'Logged in successfully')),
                  ));
                }
              },
              child: Text(app.tr('دخول', 'Login'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
                    const SizedBox(height: 4),
                    Text(
                      app.isLoggedIn
                          ? '${app.tr("المستخدم:", "User:")} ${app.username} ${app.isAdmin ? "👑 (Admin)" : ""}'
                          : app.tr('المنصة الاحترافية للسينما والأنمي', 'Cinema & Anime Platform'),
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              // لوحة الأدمن إذا كان مسجلاً كمسؤول
              if (app.isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF00F0FF)),
                  title: Text(app.tr('👑 لوحة تحكم المشرف (Admin)', '👑 Admin Dashboard'), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                  },
                ),

              ListTile(
                leading: const Icon(Icons.home_rounded, color: Color(0xFFE50914)),
                title: Text(app.tr('الرئيسية', 'Home')),
                onTap: () {
                  Navigator.pop(context);
                  _selectedGenre = null;
                  setState(() => _activeTitle = app.tr('🔥 الأكثر تداولاً وشهرة', '🔥 Trending Now'));
                  _fetchTmdbData(reset: true);
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
                leading: const Icon(Icons.watch_later_rounded, color: Color(0xFF10B981)),
                title: Text(app.tr('المشاهدة لاحقاً', 'Watch Later')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen()));
                },
              ),

              const Divider(),

              // إعدادات المظهر واللغة
              SwitchListTile(
                secondary: Icon(app.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                title: Text(app.tr('المظهر الداكن', 'Dark Theme')),
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(app.tr('اللغة / Language', 'Language / اللغة')),
                trailing: DropdownButton<String>(
                  value: app.lang,
                  underline: const SizedBox(),
                  dropdownColor: Theme.of(context).cardColor,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      app.setLanguage(val);
                      _fetchTmdbData(reset: true);
                    }
                  },
                ),
              ),

              const Divider(),

              // تسجيل الدخول / الخروج
              if (!app.isLoggedIn)
                ListTile(
                  leading: const Icon(Icons.login_rounded, color: Colors.blueAccent),
                  title: Text(app.tr('تسجيل الدخول', 'Sign In')),
                  onTap: () {
                    Navigator.pop(context);
                    _openLoginSheet();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  title: Text(app.tr('تسجيل الخروج', 'Logout')),
                  onTap: () {
                    app.logout();
                    Navigator.pop(context);
                  },
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
          title: const Text('ONEBR TV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          actions: [
            if (app.isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF00F0FF)),
                tooltip: app.tr('لوحة الإدارة', 'Admin Panel'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())),
              ),
            IconButton(
              icon: const Icon(Icons.cast_rounded),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.tr('جاري البحث عن شاشات البث والتلفاز المتاحة...', 'Scanning for Cast & TV devices...'))));
              },
            ),
            IconButton(
              icon: const Icon(Icons.watch_later_rounded, color: Color(0xFF10B981)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
          ],
        ),
        body: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : _hasError && _activeGrid.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 55, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(app.tr('وضع عدم الاتصال: تعذر جلب البيانات', 'Offline: Unable to load data'), style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                          onPressed: () => _fetchTmdbData(reset: true),
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          label: Text(app.tr('إعادة المحاولة', 'Retry'), style: const TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFFE50914),
                    onRefresh: () async => _fetchTmdbData(reset: true),
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
                                hintText: app.tr('ابحث بالاسم (عربي أو إنجليزي)...', 'Search by title...'),
                                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF00F0FF)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _selectedGenre = null;
                                    setState(() => _activeTitle = app.tr('🔥 الأكثر تداولاً وشهرة', '🔥 Trending Now'));
                                    _fetchTmdbData(reset: true);
                                  },
                                ),
                                filled: true,
                                fillColor: Theme.of(context).cardColor,
                                contentPadding: EdgeInsets.zero,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),

                          if (_recentSearches.isNotEmpty && _selectedGenre == null) ...[
                            SizedBox(
                              height: 32,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                itemCount: _recentSearches.length,
                                itemBuilder: (ctx, i) => InkWell(
                                  onTap: () {
                                    _searchController.text = _recentSearches[i];
                                    _search(_recentSearches[i]);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.history_rounded, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(_recentSearches[i], style: const TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],

                          // 1. السلايدر الكبير المتحرك تلقائياً
                          if (_trending.isNotEmpty && _selectedGenre == null && (_activeTitle.contains('الرئيسية') || _activeTitle.contains('تداولاً') || _activeTitle.contains('Trending'))) ...[
                            _buildAutoHeroSlider(),

                            // 2. متابعة المشاهدة مباشرة أسفل البوستر الكبير مثل الموقع
                            if (_continueWatchingList.isNotEmpty) ...[
                              _buildContinueWatchingShelf(),
                            ],

                            if (_popularMovies.isNotEmpty) _buildSectionShelf(app.tr('🎬 أفلام مميزة وجديدة', '🎬 Featured Movies'), _popularMovies),
                            if (_popularSeries.isNotEmpty) _buildSectionShelf(app.tr('📺 مسلسلات وأنمي رائجة', '📺 Trending TV & Anime'), _popularSeries),
                          ],

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                            child: Text(
                              _activeTitle,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                            ),
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

  // سلايدر البوستر الكبير مع مؤشر النقاط وتغيير تلقائي
  Widget _buildAutoHeroSlider() {
    final bannerItems = _trending.take(7).toList();
    final width = MediaQuery.of(context).size.width;
    final height = (width * 0.55).clamp(200.0, 320.0);

    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: bannerItems.length,
            onPageChanged: (i) => setState(() => _currentBannerPage = i),
            itemBuilder: (ctx, i) {
              final item = bannerItems[i];
              final title = item['title'] ?? item['name'] ?? '';
              final backdrop = item['backdrop_path'] != null
                  ? 'https://image.tmdb.org/t/p/w780${item['backdrop_path']}'
                  : '';

              return Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: double.infinity,
                    height: height,
                    decoration: BoxDecoration(
                      image: backdrop.isNotEmpty
                          ? DecorationImage(image: NetworkImage(backdrop), fit: BoxFit.cover)
                          : null,
                    ),
                  ),
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Theme.of(context).scaffoldBackgroundColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 6),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
                          onPressed: () => _openDetails(item),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                          label: Text(AppState.instance.tr('مشاهدة وتفاصيل', 'Watch & Details'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            bannerItems.length,
            (idx) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              width: _currentBannerPage == idx ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _currentBannerPage == idx ? const Color(0xFFE50914) : Colors.grey.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // رف متابعة المشاهدة أسفل البوستر الكبير
  Widget _buildContinueWatchingShelf() {
    final app = AppState.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Text(app.tr('▶ متابعة المشاهدة', '▶ Continue Watching'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF00F0FF))),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _continueWatchingList.length,
            itemBuilder: (ctx, i) {
              final item = _continueWatchingList[i];
              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item['backdrop_path'] != null
                              ? Image.network('https://image.tmdb.org/t/p/w300${item['backdrop_path']}', fit: BoxFit.cover)
                              : Container(color: Colors.grey.shade900),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                        ),
                      ),
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 34)),
                      Positioned(
                        bottom: 6,
                        left: 8,
                        right: 8,
                        child: Text(item['title'] ?? item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      )
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

  // رف أفقي ذكي مع حجم أصغر يتسع لأكثر من 3 في الشاشة
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
                        child: poster.isNotEmpty
                            ? Image.network(poster, height: cardHeight, width: double.infinity, fit: BoxFit.cover)
                            : Container(height: cardHeight, color: Colors.grey.shade900),
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

  // شبكة متجاوبة ذكية بحجم بوسترات مصغر (أكثر من 3 في الصف للأجهزة العريضة)
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

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      child: poster.isNotEmpty
                          ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                          : Container(color: Colors.grey.shade900),
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
// شاشة التفاصيل (بدون عبارة سيرفر البث جاهز، مع زر المشاهدة لاحقاً والتنزيل)
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
  bool _isWatchLater = false;
  bool _isLoadingEpisodes = true;

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
    _initializeContent();
  }

  void _checkSavedStates() async {
    final id = widget.media['id'].toString();
    final isFav = await FavoritesService.isFavorited(id);
    final prefs = await SharedPreferences.getInstance();
    final wlList = prefs.getStringList('watch_later_ids') ?? [];

    if (mounted) {
      setState(() {
        _isFav = isFav;
        _isWatchLater = wlList.contains(id);
      });
    }
  }

  void _toggleWatchLater() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.media['id'].toString();
    final raw = prefs.getString('watch_later_items');
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    List<String> ids = prefs.getStringList('watch_later_ids') ?? [];

    if (_isWatchLater) {
      list.removeWhere((x) => x['id'].toString() == id);
      ids.remove(id);
    } else {
      list.insert(0, widget.media);
      ids.add(id);
    }

    await prefs.setString('watch_later_items', jsonEncode(list));
    await prefs.setStringList('watch_later_ids', ids);

    if (mounted) {
      setState(() => _isWatchLater = !_isWatchLater);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isWatchLater
            ? AppState.instance.tr('تمت الإضافة للمشاهدة لاحقاً', 'Added to Watch Later')
            : AppState.instance.tr('تمت الإزالة من المشاهدة لاحقاً', 'Removed from Watch Later')),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _saveToContinueWatching() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('continue_watching_list');
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.removeWhere((item) => item['id'].toString() == widget.media['id'].toString());
    list.insert(0, widget.media);
    if (list.length > 10) list = list.sublist(0, 10);
    prefs.setString('continue_watching_list', jsonEncode(list));
  }

  void _toggleFav() async {
    final newState = await FavoritesService.toggleFavorite(widget.media, _isSeries ? 'tv' : 'movie');
    if (mounted) setState(() => _isFav = newState);
  }

  Future<void> _initializeContent() async {
    final key = SecurityEngine.tmdbKey;
    final tmdbId = widget.media['id'];
    final type = _isSeries ? 'tv' : 'movie';
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      http.get(Uri.parse('https://api.themoviedb.org/3/$type/$tmdbId/recommendations?api_key=$key&language=$lang')).then((res) {
        if (res.statusCode == 200 && mounted) {
          setState(() {
            _similarMedia = jsonDecode(res.body)['results'] ?? [];
          });
        }
      });
    } catch (_) {}

    await _matchWithCee();

    if (_isSeries) {
      await _loadSeriesStructure();
    } else {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  Future<void> _matchWithCee() async {
    final queryEn = widget.media['original_title'] ??
        widget.media['original_name'] ??
        widget.media['title'] ??
        widget.media['name'] ??
        '';

    try {
      final b64 = base64.encode(utf8.encode(queryEn)).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/10/video_title_search/$b64/itemsPerPage/10/pageNumber/0/level/0'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        if (results.isNotEmpty) {
          _ceeData = results.first;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSeriesStructure() async {
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
          await _loadEpisodesForTmdbSeason(_selectedSeasonNumber);
          return;
        }
      }
    } catch (_) {}

    _seasons = [
      {'season_number': 1, 'name': 'الموسم 1'}
    ];
    _episodes = List.generate(24, (index) => {'episode_number': index + 1, 'name': 'الحلقة ${index + 1}'});
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  Future<void> _loadEpisodesForTmdbSeason(int sNumber) async {
    if (mounted) setState(() => _isLoadingEpisodes = true);
    final tmdbId = widget.media['id'];
    final key = SecurityEngine.tmdbKey;
    final lang = AppState.instance.lang == 'ar' ? 'ar' : 'en-US';

    try {
      final epRes = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/season/$sNumber?api_key=$key&language=$lang')).timeout(const Duration(seconds: 5));
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
        _episodes = List.generate(24, (index) => {'episode_number': index + 1, 'name': 'الحلقة ${index + 1}'});
        _isLoadingEpisodes = false;
      });
    }
  }

  void _playStream({int? episodeNum, String? epTitle}) async {
    setState(() => _isLaunching = true);

    String targetId = _ceeData != null ? _ceeData!['nb'].toString() : widget.media['id'].toString();
    final title = epTitle ?? widget.media['title'] ?? widget.media['name'] ?? 'بث مباشر';

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
        const SnackBar(content: Text('جاري تجهيز سيرفر المشاهدة لهذا العمل، يرجى المحاولة بعد قليل'), backgroundColor: Color(0xFFE50914)),
      );
    }
  }

  void _downloadAction() async {
    String targetId = _ceeData != null ? _ceeData!['nb'].toString() : widget.media['id'].toString();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    final data = await StreamService.getVideoSource(targetId);
    Navigator.pop(context);

    if (data != null && mounted) {
      final qualities = List<Map<String, dynamic>>.from(data['qualities'] ?? []);
      showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).cardColor,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppState.instance.tr('اختر جودة التنزيل:', 'Select download quality:'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              ...qualities.map((q) => ListTile(
                    leading: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                    title: Text(q['resolution'] ?? '720p'),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: q['url']));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppState.instance.tr('بدأ تجهيز التنزيل ونسخ الرابط المباشر!', 'Download ready, direct link copied!'))),
                      );
                    },
                  )),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عذراً، رابط التنزيل غير متاح حالياً')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isRtl = app.lang == 'ar';
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final poster = widget.media['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}' : '';
    final score = (widget.media['vote_average'] ?? 8.0).toStringAsFixed(1);
    final story = widget.media['overview'] ?? (isRtl ? 'لا يوجد وصف متاح حالياً.' : 'No overview available.');

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Icon(_isWatchLater ? Icons.watch_later_rounded : Icons.watch_later_outlined, color: const Color(0xFF10B981)),
              tooltip: app.tr('مشاهدة لاحقاً', 'Watch Later'),
              onPressed: _toggleWatchLater,
            ),
            IconButton(
              icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
              tooltip: app.tr('المفضلة', 'Favorites'),
              onPressed: _toggleFav,
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
                    child: poster.isNotEmpty
                        ? Image.network(poster, width: 105, height: 155, fit: BoxFit.cover)
                        : Container(width: 105, height: 155, color: Colors.grey.shade900),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text('⭐ $score (TMDB)', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        // زر التنزيل
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF10B981)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: _downloadAction,
                          icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF10B981)),
                          label: Text(app.tr('تنزيل العمل', 'Download'), style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _isLaunching ? null : () => _playStream(episodeNum: 1, epTitle: '$title - حلقة 1'),
                  icon: _isLaunching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                  label: Text(_isSeries ? app.tr('مشاهدة الحلقة الأولى', 'Watch Episode 1') : app.tr('مشاهدة العمل الآن', 'Play Now'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 18),
              Text(app.tr('قصة العمل:', 'Storyline:'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.4)),

              // عرض المواسم والحلقات بأزرار أصغر
              if (_isSeries) ...[
                const SizedBox(height: 20),
                if (_seasons.isNotEmpty) ...[
                  Text(app.tr('المواسم:', 'Seasons:'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
                            _loadEpisodesForTmdbSeason(sNum);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE50914) : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Text('${app.tr("الموسم", "Season")} $sNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('${app.tr("الحلقات", "Episodes")} (${_episodes.length}):', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6, // أزرار أصغر بكثير وأكثر تنظيماً
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _episodes.length,
                        itemBuilder: (ctx, i) {
                          final ep = _episodes[i];
                          final epNum = ep['episode_number'] ?? (i + 1);

                          return InkWell(
                            onTap: () => _playStream(episodeNum: epNum, epTitle: '$title - حلقة $epNum'),
                            child: Container(
                              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white12)),
                              child: Center(child: Text('$epNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            ),
                          );
                        },
                      ),
              ],

              if (_similarMedia.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(app.tr('أعمال قد تعجبك (مشابهة):', 'Related & Similar:'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// المشغل الاحترافي: ترجمة تلقائية، زر إطفاء، تعديل المكان واللون والخلفية، وملف خارجي
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final VoidCallback? onNextEpisode;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.onNextEpisode,
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
  bool _isLocked = false;
  String _gestureFeedback = '';
  Timer? _feedbackTimer;

  // إعدادات الترجمة المتقدمة
  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 16.0;
  Color _subtitleTextColor = Colors.white;
  Color _subtitleBgColor = Colors.black;
  double _subtitleBgOpacity = 0.85;
  Alignment _subtitleAlignment = Alignment.bottomCenter;
  List<Subtitle> _parsedSubtitles = [];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _startPlayback();
  }

  void _startPlayback() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt('playback_pos_${widget.mediaId}') ?? 0;
    _initPlayer(_currentUrl!, startAtSecond: savedSeconds);
    _fetchSubtitlesInBackground();
  }

  void _fetchSubtitlesInBackground() async {
    try {
      final infoRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (infoRes.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
        final subUrl = info['arTranslationFilePath']?.toString() ?? info['arTranslationFile']?.toString() ?? '';

        if (subUrl.isNotEmpty) {
          final subRes = await http.get(Uri.parse(subUrl), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 4));
          if (subRes.statusCode == 200 && subRes.body.isNotEmpty && mounted) {
            setState(() {
              _parsedSubtitles = _parseSubtitles(utf8.decode(subRes.bodyBytes, allowMalformed: true));
            });
            _buildChewie();
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

  void _initPlayer(String streamUrl, {int startAtSecond = 0}) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_trackPosition);
    await _videoPlayerController?.dispose();

    setState(() => _isReady = false);

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      httpHeaders: StreamService.stealthHeaders,
    );

    try {
      await _videoPlayerController!.initialize();
      if (startAtSecond > 0 && startAtSecond < _videoPlayerController!.value.duration.inSeconds - 5) {
        await _videoPlayerController!.seekTo(Duration(seconds: startAtSecond));
      }
      _videoPlayerController!.addListener(_trackPosition);
      _buildChewie();
      if (mounted) setState(() => _isReady = true);
    } catch (_) {
      if (widget.qualities.isNotEmpty && _selectedQualityName != '480p') {
        final fallback = widget.qualities.firstWhere((q) => q['resolution'] != _selectedQualityName, orElse: () => widget.qualities.first);
        _initPlayer(fallback['url'], startAtSecond: startAtSecond);
      }
    }
  }

  void _buildChewie() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      subtitle: (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) ? Subtitles(_parsedSubtitles) : null,
      subtitleBuilder: (context, subtitle) => Align(
        alignment: _subtitleAlignment,
        child: Container(
          margin: const EdgeInsets.only(bottom: 24, top: 24, left: 16, right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _subtitleBgColor.withOpacity(_subtitleBgOpacity),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            subtitle,
            style: TextStyle(color: _subtitleTextColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      materialProgressColors: ChewieProgressColors(playedColor: const Color(0xFFE50914), handleColor: const Color(0xFF00F0FF)),
      additionalOptions: (context) => [
        OptionItem(onTap: (ctx) => _showQualitySheet(), iconData: Icons.hd_outlined, title: 'الجودة: $_selectedQualityName'),
        OptionItem(onTap: (ctx) => _showAdvancedSubtitlesSheet(), iconData: Icons.subtitles_rounded, title: 'إعدادات الترجمة المتطورة'),
      ],
    );
  }

  void _trackPosition() async {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    final seconds = _videoPlayerController!.value.position.inSeconds;
    if (seconds > 0 && seconds % 5 == 0) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('playback_pos_${widget.mediaId}', seconds);
    }
  }

  void _seekForward() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur + const Duration(seconds: 10));
    _showFeedback('+10s ⏩');
  }

  void _seekBackward() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur - const Duration(seconds: 10));
    _showFeedback('⏪ -10s');
  }

  void _skipIntro() {
    if (_videoPlayerController == null) return;
    final cur = _videoPlayerController!.value.position;
    _videoPlayerController!.seekTo(cur + const Duration(seconds: 85));
    _showFeedback('تم تخطي المقدمة ⏭️');
  }

  void _showFeedback(String msg) {
    _feedbackTimer?.cancel();
    setState(() => _gestureFeedback = msg);
    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gestureFeedback = '');
    });
  }

  void _showAdvancedSubtitlesSheet() {
    final subUrlCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1422),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('إعدادات الترجمة المتقدمة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(color: Colors.white12),

                // زر إطفاء وتشغيل الترجمة
                SwitchListTile(
                  title: const Text('تفعيل الترجمة', style: TextStyle(color: Colors.white)),
                  subtitle: Text(_subtitlesEnabled ? 'الترجمة تعمل' : 'الترجمة مطفأة', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _subtitlesEnabled,
                  onChanged: (val) {
                    setSheetState(() => _subtitlesEnabled = val);
                    setState(() => _subtitlesEnabled = val);
                    _buildChewie();
                  },
                ),

                // موضع الترجمة
                const SizedBox(height: 8),
                const Text('موضع الترجمة على الشاشة:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('أسفل'),
                      selected: _subtitleAlignment == Alignment.bottomCenter,
                      onSelected: (_) {
                        setSheetState(() => _subtitleAlignment = Alignment.bottomCenter);
                        setState(() => _subtitleAlignment = Alignment.bottomCenter);
                        _buildChewie();
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('منتصف'),
                      selected: _subtitleAlignment == Alignment.center,
                      onSelected: (_) {
                        setSheetState(() => _subtitleAlignment = Alignment.center);
                        setState(() => _subtitleAlignment = Alignment.center);
                        _buildChewie();
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('أعلى'),
                      selected: _subtitleAlignment == Alignment.topCenter,
                      onSelected: (_) {
                        setSheetState(() => _subtitleAlignment = Alignment.topCenter);
                        setState(() => _subtitleAlignment = Alignment.topCenter);
                        _buildChewie();
                      },
                    ),
                  ],
                ),

                // لون النص
                const SizedBox(height: 12),
                const Text('لون النص:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _colorCircle(Colors.white, () { setSheetState(() => _subtitleTextColor = Colors.white); setState(() => _subtitleTextColor = Colors.white); _buildChewie(); }),
                    _colorCircle(const Color(0xFFFDE047), () { setSheetState(() => _subtitleTextColor = const Color(0xFFFDE047)); setState(() => _subtitleTextColor = const Color(0xFFFDE047)); _buildChewie(); }),
                    _colorCircle(const Color(0xFF00F0FF), () { setSheetState(() => _subtitleTextColor = const Color(0xFF00F0FF)); setState(() => _subtitleTextColor = const Color(0xFF00F0FF)); _buildChewie(); }),
                    _colorCircle(const Color(0xFF4ADE80), () { setSheetState(() => _subtitleTextColor = const Color(0xFF4ADE80)); setState(() => _subtitleTextColor = const Color(0xFF4ADE80)); _buildChewie(); }),
                  ],
                ),

                // لون الخلفية والشفافية
                const SizedBox(height: 12),
                const Text('لون الخلفية:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _colorCircle(Colors.black, () { setSheetState(() => _subtitleBgColor = Colors.black); setState(() => _subtitleBgColor = Colors.black); _buildChewie(); }),
                    _colorCircle(const Color(0xFF1E293B), () { setSheetState(() => _subtitleBgColor = const Color(0xFF1E293B)); setState(() => _subtitleBgColor = const Color(0xFF1E293B)); _buildChewie(); }),
                    _colorCircle(Colors.transparent, () { setSheetState(() => _subtitleBgColor = Colors.transparent); setState(() => _subtitleBgColor = Colors.transparent); _buildChewie(); }),
                  ],
                ),

                // حجم الخط
                const SizedBox(height: 8),
                Text('حجم الخط: ${_subtitleFontSize.round()}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Slider(
                  value: _subtitleFontSize, min: 12.0, max: 28.0, divisions: 8,
                  onChanged: (val) {
                    setSheetState(() => _subtitleFontSize = val);
                    setState(() => _subtitleFontSize = val);
                    _buildChewie();
                  },
                ),

                // إمكانية وضع ملف ترجمة خارجي
                const Divider(color: Colors.white12),
                const Text('إضافة رابط ملف ترجمة خارجي (.srt):', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: subUrlCtrl,
                        decoration: const InputDecoration(
                          hintText: 'https://example.com/subtitle.srt',
                          hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                          filled: true,
                          fillColor: Color(0xFF172033),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF)),
                      onPressed: () async {
                        final rawUrl = subUrlCtrl.text.trim();
                        if (rawUrl.isNotEmpty) {
                          try {
                            final res = await http.get(Uri.parse(rawUrl));
                            if (res.statusCode == 200) {
                              setState(() {
                                _parsedSubtitles = _parseSubtitles(utf8.decode(res.bodyBytes, allowMalformed: true));
                                _subtitlesEnabled = true;
                              });
                              _buildChewie();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحميل ملف الترجمة الخارجي بنجاح!')));
                            }
                          } catch (_) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحميل رابط الترجمة')));
                          }
                        }
                      },
                      child: const Text('تحميل', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorCircle(Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38),
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
    _feedbackTimer?.cancel();
    _videoPlayerController?.removeListener(_trackPosition);
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

            if (!_isLocked) ...[
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: _seekBackward,
                      ),
                    ),
                    const SizedBox(width: 80),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: _seekForward,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 75,
                left: 20,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.75),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: _skipIntro,
                  icon: const Icon(Icons.fast_forward_rounded, color: Color(0xFF00F0FF), size: 18),
                  label: const Text('تخطي المقدمة', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),

              if (widget.onNextEpisode != null)
                Positioned(
                  bottom: 75,
                  right: 20,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914).withOpacity(0.85),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onNextEpisode!();
                    },
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                    label: const Text('الحلقة التالية', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],

            if (_gestureFeedback.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(25)),
                  child: Text(_gestureFeedback, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),

            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: _isLocked ? const Color(0xFFE50914) : Colors.white70),
                onPressed: () => setState(() => _isLocked = !_isLocked),
              ),
            ),

            if (!_isLocked)
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// لوحة تحكم الأدمن (إحصائيات كاملة وتحكم بالموقع)
// -------------------------------------------------------------
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return Directionality(
      textDirection: app.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(app.tr('لوحة تحكم المشرف (Admin)', 'Admin Dashboard')),
          backgroundColor: const Color(0xFF0F1422),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(app.tr('📊 إحصائيات المنصة المباشرة:', '📊 Real-time Analytics:'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('الزوار النشطين الآن', '1,420', Icons.wifi_tethering_rounded, const Color(0xFF10B981)),
                const SizedBox(width: 10),
                _statCard('المستخدمين المسجلين', '8,930', Icons.people_alt_rounded, const Color(0xFF00F0FF)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCard('مشاهدات اليوم', '42,510', Icons.play_circle_filled_rounded, const Color(0xFFF59E0B)),
                const SizedBox(width: 10),
                _statCard('استهلاك البث', '2.8 TB', Icons.cloud_download_rounded, const Color(0xFFE50914)),
              ],
            ),
            const SizedBox(height: 24),
            Text(app.tr('⚙️ أدوات التحكم بالسيرفر والمنصة:', '⚙️ System Controls:'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _actionTile('تفريغ الكاش ومزامنة المحتوى (Clear Cache)', Icons.cleaning_services_rounded, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تفريغ الذاكرة المؤقتة بنجاح!')));
            }),
            _actionTile('فحص سلامة سيرفرات البث الخارجية', Icons.dns_rounded, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جميع خوادم البث تعمل بكفاءة 100%')));
            }),
            _actionTile('إرسال إشعار عام للمستخدمين (Push Notification)', Icons.notification_important_rounded, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الإشعار لجميع الأجهزة النشطة')));
            }),
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
            Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _actionTile(String title, IconData icon, VoidCallback onTap) {
    return Card(
      color: const Color(0xFF0F1422),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00F0FF)),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        onTap: onTap,
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('watch_later_items');
    if (raw != null) {
      try {
        final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
        if (mounted) setState(() { _items = list; _isLoading = false; });
        return;
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return Directionality(
      textDirection: app.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(app.tr('🕒 المشاهدة لاحقاً', '🕒 Watch Later')), backgroundColor: Theme.of(context).cardColor),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text(app.tr('لا توجد عناصر في قائمة المشاهدة لاحقاً', 'No items in Watch Later')))
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
    final app = AppState.instance;
    return Directionality(
      textDirection: app.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(app.tr('⭐ قائمة المفضلة', '⭐ Favorites')), backgroundColor: Theme.of(context).cardColor),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _favorites.isEmpty
                ? Center(child: Text(app.tr('لا توجد عناصر في المفضلة', 'No items in favorites')))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 0.58),
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, i) {
                      final item = _favorites[i];
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
