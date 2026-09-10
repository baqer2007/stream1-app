import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

class AppRadius {
  static const double card = 12.0;
  static const double chip = 10.0;
  static const double sheet = 20.0;
  static const double button = 12.0;
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

  static Future<void> savePlaybackPosition(String id, int positionMs, int durationMs, String title, String poster) async {
    if (durationMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pos_$id', positionMs);

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
    return prefs.getInt('pos_$id') ?? 0;
  }

  static Future<Set<String>> getWatchedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('watched_episodes_list') ?? [];
    return list.toSet();
  }

  static Future<void> markEpisodeWatched(String epId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('watched_episodes_list') ?? [];
    if (!list.contains(epId)) {
      list.add(epId);
      await prefs.setStringList('watched_episodes_list', list);
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

class PlayerSettings extends ChangeNotifier {
  static final PlayerSettings instance = PlayerSettings._();
  PlayerSettings._();

  int seekDuration = 10;
  bool skipSensitiveScenes = true;
  double subFontSize = 18.0;
  Color subColor = Colors.white;
  bool subHasShadow = true;
  double subBottomPadding = 60.0; // التحكم بمكان الترجمة

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    seekDuration = p.getInt('player_seek_dur') ?? 10;
    skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
    subFontSize = p.getDouble('player_sub_size') ?? 18.0;
    subBottomPadding = p.getDouble('player_sub_bottom') ?? 60.0;
  }

  void updateSeek(int sec) async {
    seekDuration = sec;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('player_seek_dur', sec);
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

  void resetSubtitles() {
    subFontSize = 18.0;
    subColor = Colors.white;
    subHasShadow = true;
    subBottomPadding = 60.0;
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
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        cardColor: AppColors.surface,
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
    const CategoriesScreen(),
    const SearchScreen(),
    const DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B101A),
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
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'الرئيسية'),
              BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'التصنيفات'),
              BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'بحث'),
              BottomNavigationBarItem(icon: Icon(Icons.bookmark_rounded), label: 'المكتبة'),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// الصفحة الرئيسية (بانر غير مقصوص + تصغير البوسترات لأكثر من 3 في السطر)
// =========================================================================
class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _items = [];
  List<dynamic> _heroItems = [];
  List<Map<String, dynamic>> _resumeList = [];
  final Set<String> _uniqueIds = {};

  int _page = 0;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoading && _hasMore) {
          _fetchMore();
        }
      }
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    _resumeList = await LocalStorageService.getList('resume_playback_list');

    try {
      final res = await Future.wait([
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 18),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 18),
      ]);
      final fresh = [...res[0], ...res[1]]..shuffle();

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
          _heroItems = deduplicated.take(5).toList();
          _items = deduplicated;
          _isLoading = false;
          _page = 1;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMore() async {
    setState(() => _isLoading = true);
    final res = await StreamService.fetchFeed(isSeries: _page % 2 == 0, page: _page, perPage: 28);
    final List<dynamic> deduplicated = [];
    for (var it in res) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_uniqueIds.contains(id)) {
        _uniqueIds.add(id);
        deduplicated.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _items.addAll(deduplicated);
        _isLoading = false;
        if (deduplicated.isEmpty) _hasMore = false;
        _page++;
      });
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: MediaDetailScreen(media: item)),
      ),
    ).then((_) => _loadResumeState());
  }

  void _loadResumeState() async {
    final list = await LocalStorageService.getList('resume_playback_list');
    if (mounted) setState(() => _resumeList = list);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // تصغير البوسترات بحيث يعرض 4 بوسترات على الأقل في الهواتف و 5 في التابلت
    final screenWidth = MediaQuery.of(context).size.width;
    final gridCount = screenWidth > 700 ? 5 : 4;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('ONEBR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2)),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('سينما بلس', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          _uniqueIds.clear();
          await _loadInitialData();
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // البانر السينمائي بنسبة عرض متناسقة غير مقصوصة
              if (_heroItems.isNotEmpty) _buildHeroBanner(),

              if (_resumeList.isNotEmpty) _buildResumeSection(),

              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('أحدث الأعمال السينمائية', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                    Icon(Icons.auto_awesome, color: AppColors.primary, size: 16),
                  ],
                ),
              ),

              _buildDynamicGrid(gridCount),

              if (_isLoading && _items.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    final item = _heroItems.first;
    final poster = StreamService.extractPoster(item);
    final title = item['ar_title'] ?? item['en_title'] ?? '';

    return AspectRatio(
      aspectRatio: 16 / 9, // حل مشكلة قص البانر نهائياً
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(color: AppColors.border, width: 0.5),
          image: poster.isNotEmpty ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover) : null,
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card + 4),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99000000), Color(0xF0070A10)],
                  stops: [0.3, 0.7, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: 12, right: 14, left: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _openDetails(item),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    label: const Text('مشاهدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Text('متابعة المشاهدة', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: _resumeList.length,
            itemBuilder: (ctx, i) {
              final item = _resumeList[i];
              final progress = (item['position'] / item['duration']).clamp(0.0, 1.0);
              return GestureDetector(
                onTap: () {
                  StreamService.getVideoSource(item['id']).then((source) {
                    if (source != null && mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            mediaId: item['id'],
                            title: item['title'] ?? '',
                            videoUrl: source['video_url'],
                            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
                          ),
                        ),
                      ).then((_) => _loadResumeState());
                    }
                  });
                },
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border, width: 0.5),
                    image: item['poster'].toString().isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(item['poster']),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.45), BlendMode.darken),
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 34)),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                              child: Text(item['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: 3,
                              ),
                            ),
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

  Widget _buildDynamicGrid(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
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
          final title = it['ar_title'] ?? it['en_title'] ?? it['title'] ?? '';
          final score = (it['stars'] ?? '7.0').toString();
          final id = (it['nb'] ?? it['id']).toString();

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
                      child: Hero(
                        tag: 'poster_$id',
                        child: poster.isNotEmpty
                            ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                            : Container(color: AppColors.surface),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.star, size: 11),
                    const SizedBox(width: 2),
                    Text(score, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// شاشة تفاصيل العمل المطابقة للصور (1000018711 و 1000018712)
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

  @override
  void initState() {
    super.initState();
    _isSeries = (widget.media['is_series_fixed'] == true) || (widget.media['season'] != null && widget.media['season'].toString() != '0');
    _loadState();
    if (_isSeries) _loadEpisodes();
  }

  void _loadState() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final watched = await LocalStorageService.getWatchedEpisodes();
    final wl = await LocalStorageService.isWatchlist(id);
    if (mounted) {
      setState(() {
        _watchedEpisodes = watched;
        _isWatchlist = wl;
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

  void _playEpisode(dynamic episodeData, int epIndex) async {
    setState(() => _isLaunching = true);

    final targetId = (episodeData['nb'] ?? episodeData['id']).toString();
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final source = await StreamService.getVideoSource(targetId);
    final subUrl = await StreamService.getArabicSubtitleUrl(targetId);

    await LocalStorageService.markEpisodeWatched(targetId);
    _loadState();

    setState(() => _isLaunching = false);

    if (source != null && mounted) {
      final currentSeasonEpisodes = _seasonsMap[_selectedSeason] ?? [];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: targetId,
            title: title,
            subtitleTextHeader: 'الموسم $_selectedSeason - الحلقة $epIndex',
            videoUrl: source['video_url'],
            subtitleUrl: subUrl,
            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
            episodes: currentSeasonEpisodes,
            currentEpIndex: epIndex,
            poster: StreamService.extractPoster(widget.media),
            onEpisodeChanged: (newEpId) {
              LocalStorageService.markEpisodeWatched(newEpId);
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
            subtitleTextHeader: '',
            videoUrl: source['video_url'],
            subtitleUrl: subUrl,
            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
            poster: StreamService.extractPoster(widget.media),
          ),
        ),
      );
    }
  }

  void _showDownloadQualitySheet(String targetId, String title, String poster) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: StreamService.getVideoSource(targetId),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                );
              }
              final source = snap.data;
              final List qualities = source?['qualities'] ?? [];

              return Directionality(
                textDirection: TextDirection.rtl,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        child: Text('اختر جودة التنزيل', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      ...qualities.map((q) {
                        final res = q['resolution'] ?? '240p';
                        final url = q['url'] ?? '';
                        return ListTile(
                          leading: const Icon(Icons.video_file_outlined, color: AppColors.primary),
                          title: Text('جودة $res', style: const TextStyle(color: Colors.white)),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('بدأ تنزيل $title بدقة $res')),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final poster = StreamService.extractPoster(widget.media);
    final story = widget.media['ar_content'] ?? widget.media['en_content'] ?? '';
    final score = (widget.media['stars'] ?? '7.9').toString();
    final year = widget.media['year']?.toString() ?? '2024';
    final currentEpisodes = _seasonsMap[_selectedSeason] ?? [];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            // الجزء العلوي مع البوستر الممتد والأزرار السينمائية (مطابق لـ 1000018711)
            SliverAppBar(
              expandedHeight: 480,
              pinned: true,
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(_isWatchlist ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _isWatchlist ? AppColors.primary : Colors.white),
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
                    if (poster.isNotEmpty)
                      Image.network(poster, fit: BoxFit.cover)
                    else
                      Container(color: AppColors.surface),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black45,
                            Colors.transparent,
                            Color(0xCC070A10),
                            AppColors.background,
                          ],
                          stops: [0.0, 0.4, 0.75, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12, left: 16, right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                                child: Text('IMDb $score', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Text('$year • ${_isSeries ? 'مسلسل' : 'فيلم'} • أكشن', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // أزرار التحكم الثلاثية المركزية (مشاهدة لاحقاً - شاهد الآن - تحميل)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // زر المشاهدة لاحقاً
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
                              const SizedBox(width: 32),
                              // زر شاهد الآن البيضاوي
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                ),
                                onPressed: _isLaunching
                                    ? null
                                    : () {
                                        if (_isSeries && currentEpisodes.isNotEmpty) {
                                          _playEpisode(currentEpisodes.first, 1);
                                        } else {
                                          _playMovie();
                                        }
                                      },
                                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                                label: const Text('شاهد الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                              const SizedBox(width: 32),
                              // زر التحميل
                              InkWell(
                                onTap: () => _showDownloadQualitySheet((widget.media['nb'] ?? widget.media['id']).toString(), title, poster),
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

            // محتوى الصفحة (الوصف والحلقات مع البوسترات العريضة)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // زر مشاهدة الإعلان الترويجي
                    Row(
                      children: [
                        const Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 20),
                        const SizedBox(width: 6),
                        const Text('مشاهدة الإعلان', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
                          child: const Text('PG-13', style: TextStyle(color: Colors.white54, fontSize: 10)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (story.isNotEmpty)
                      Text(story, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
                    const SizedBox(height: 14),
                    // أزرار التفاعل والإعجاب
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_alt_outlined, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        const Text('6278', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(width: 16),
                        const Icon(Icons.thumb_down_alt_outlined, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        const Text('193', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 30),

                    // تبويب الحلقات والمواسم
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

                      // بطاقات الحلقات مع الصورة العريضة ومؤشر المشاهدة بالعين الخضراء (مطابقة للصور 1000018712 و 1000018713)
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
                                  // زر التنزيل
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward_rounded, color: Colors.white54, size: 20),
                                    onPressed: () => _showDownloadQualitySheet(targetId, '$title - حلقة $idx', poster),
                                  ),
                                  const SizedBox(width: 8),
                                  // تفاصيل الحلقة وحالة المشاهدة
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
                                  // البوستر العريض للحلقة
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 110,
                                          height: 65,
                                          color: Colors.black26,
                                          child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : null,
                                        ),
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
// مشغل الفيديو والتحكم بمكان الترجمة
// =========================================================================
class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String subtitleTextHeader;
  final String videoUrl;
  final String subtitleUrl;
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
  BoxFit _videoFit = BoxFit.cover;

  List<Subtitle> _subtitles = [];
  String _currentSubText = '';

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
    if (widget.subtitleUrl.isNotEmpty) _loadSubs(widget.subtitleUrl);
  }

  void _loadWatchedState() async {
    final w = await LocalStorageService.getWatchedEpisodes();
    if (mounted) setState(() => _watchedSet = w);
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
    final subUrl = await StreamService.getArabicSubtitleUrl(epId);

    await LocalStorageService.markEpisodeWatched(epId);
    widget.onEpisodeChanged?.call(epId);
    _loadWatchedState();

    if (source != null) {
      _initPlayer(source['video_url']);
      if (subUrl.isNotEmpty) _loadSubs(subUrl);
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

  void _openEpisodesDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Text('اختر حلقة للمشاهدة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ...widget.episodes.asMap().entries.map((e) {
                  final ep = e.value;
                  final idx = e.key + 1;
                  final epId = (ep['nb'] ?? ep['id']).toString();
                  final isCurrent = idx == _activeEpIndex;
                  final isWatched = _watchedSet.contains(epId);

                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: AppColors.primary.withOpacity(0.15),
                    leading: Icon(
                      isWatched ? Icons.visibility_rounded : Icons.play_circle_outline_rounded,
                      color: isCurrent ? AppColors.primary : (isWatched ? Colors.greenAccent : Colors.white70),
                    ),
                    title: Text('الحلقة $idx', style: TextStyle(color: isCurrent ? AppColors.primary : Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                    trailing: isWatched ? const Text('تمت المشاهدة', style: TextStyle(color: Colors.greenAccent, fontSize: 10)) : null,
                    onTap: () {
                      Navigator.pop(context);
                      _switchEpisode(ep, idx);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSettingsBottomSheet() {
    final settings = PlayerSettings.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(Icons.closed_caption_outlined, color: Colors.white70),
                    title: const Text('إعدادات الترجمة ومكان الظهور', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()));
                    },
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70),
                    title: const Text('أبعاد الشاشة', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Text(_videoFit == BoxFit.cover ? 'ملء الشاشة' : 'أصلي', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    onTap: () {
                      setState(() {
                        _videoFit = _videoFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(Icons.fast_forward_rounded, color: Colors.white70),
                    title: const Text('فترة تمرير الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Text('${settings.seekDuration} ثوانٍ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _showSeekPicker();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSeekPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
      backgroundColor: AppColors.surface,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: widget.qualities.map((q) {
          final res = q['resolution'] ?? '240p';
          final url = q['url'] ?? '';
          return ListTile(
            title: Text(res, style: const TextStyle(color: Colors.white)),
            trailing: _activeQuality == res ? const Icon(Icons.check, color: AppColors.primary) : null,
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

                  // مكان الترجمة القابل للتخصيص عمودياً
                  if (_currentSubText.isNotEmpty)
                    Positioned(
                      bottom: settings.subBottomPadding,
                      left: 20,
                      right: 20,
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
                      bottom: 85,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                        child: Row(
                          children: [
                            Text('الحلقة التالية خلال $_autoNextCountdown ث', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                              onPressed: _playNextEpisode,
                              child: const Text('تشغيل الآن', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_showControls)
                    Positioned(
                      left: 16,
                      top: constraints.maxHeight / 2 - 20,
                      child: IconButton(
                        icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.white),
                        onPressed: () => setState(() => _isLocked = !_isLocked),
                      ),
                    ),

                  if (_showControls && !_isLocked) ...[
                    Positioned(
                      top: 10,
                      left: 14,
                      right: 14,
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
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.white10,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _openEpisodesDrawer,
                                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 18),
                                    label: const Text('الحلقات', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.tune_rounded, color: Colors.white),
                                  onPressed: _openSettingsBottomSheet,
                                ),
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
                        bottom: 12,
                        left: 16,
                        right: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
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
            );
          },
        ),
      ),
    );
  }
}

// =========================================================================
// شاشة إعدادات الترجمة مع التحكم بارتفاع وموقع النص
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('إعدادات الترجمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
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
                    bottom: (s.subBottomPadding / 120) * 80,
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
            const SizedBox(height: AppSpacing.lg),
            // التحكم بمكان الترجمة (Bottom Padding Slider)
            ListTile(
              title: const Text('موقع الترجمة من الأسفل', style: TextStyle(color: Colors.white, fontSize: 13)),
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
            const Divider(color: AppColors.border),
            ListTile(
              title: const Text('حجم خط الترجمة', style: TextStyle(color: Colors.white, fontSize: 13)),
              trailing: DropdownButton<double>(
                dropdownColor: AppColors.surface,
                value: s.subFontSize,
                items: const [
                  DropdownMenuItem(value: 14.0, child: Text('صغير', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: 18.0, child: Text('متوسط', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: 24.0, child: Text('كبير', style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => setState(() => s.updateSubStyle(size: v)),
              ),
            ),
            const Divider(color: AppColors.border),
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
            const Divider(color: AppColors.border),
            SwitchListTile(
              title: const Text('ظل حواف الخط', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: s.subHasShadow,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => s.updateSubStyle(shadow: v)),
            ),
            const SizedBox(height: 30),
            OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border)),
              onPressed: () => setState(() => s.resetSubtitles()),
              child: const Text('إعادة ضبط الترجمة الافتراضية', style: TextStyle(color: Colors.white70)),
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
          border: isSelected ? Border.all(color: AppColors.primary, width: 2.5) : null,
        ),
      ),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  final List<Map<String, dynamic>> _allCategories = const [
    {'key': 'action', 'ar': 'أكشن وحركة', 'icon': Icons.flash_on_rounded},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'icon': Icons.animation_rounded},
    {'key': 'comedy', 'ar': 'كوميديا وضحك', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'key': 'horror', 'ar': 'رعب وتشويق', 'icon': Icons.nights_stay_rounded},
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
        padding: const EdgeInsets.all(AppSpacing.md),
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
                  MaterialPageRoute(builder: (_) => CategoryCatalogPage(category: cat)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class CategoryCatalogPage extends StatefulWidget {
  final Map<String, dynamic> category;
  const CategoryCatalogPage({super.key, required this.category});

  @override
  State<CategoryCatalogPage> createState() => _CategoryCatalogPageState();
}

class _CategoryCatalogPageState extends State<CategoryCatalogPage> {
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
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 350) {
        if (!_isLoading && _hasMore) _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final res = await StreamService.fetchByCategoryName(widget.category['key'], page: _page);
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
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(widget.category['ar'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppSpacing.md),
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
                        child: poster.isNotEmpty
                            ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                            : Container(color: AppColors.surface),
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
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'ابحث عن فيلم أو أنمي...', hintStyle: TextStyle(color: AppColors.textMuted), border: InputBorder.none),
          onSubmitted: _search,
        ),
      ),
      body: _isSearching
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, childAspectRatio: 0.56, crossAxisSpacing: 8, mainAxisSpacing: 10),
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final item = _results[i];
                final poster = StreamService.extractPoster(item);
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: poster.isNotEmpty ? Image.network(poster, fit: BoxFit.cover) : Container(color: AppColors.surface),
                  ),
                );
              },
            ),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _completed = [];
  List<Map<String, dynamic>> _watchlist = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  void _loadData() async {
    final downloads = await LocalStorageService.getList('downloaded_works_list');
    final wl = await LocalStorageService.getList('user_watchlist');
    if (mounted) {
      setState(() {
        _completed = downloads;
        _watchlist = wl;
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

  @override
  Widget build(BuildContext context) {
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 4;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('المكتبة الشخصية'),
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
          tabs: const [
            Tab(text: 'التنزيلات'),
            Tab(text: 'قائمة المشاهدة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _completed.isEmpty
              ? _buildEmptyState(Icons.download_done_rounded, 'لا توجد تنزيلات مكتملة', 'قم بتنزيل أفلامك وحلقاتك المفضلة لمشاهدتها بدون إنترنت')
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _completed.length,
                  itemBuilder: (ctx, i) {
                    final item = _completed[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_fill, color: AppColors.primary),
                        title: Text(item['title'] ?? '', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(item['size'] ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                      ),
                    );
                  },
                ),
          _watchlist.isEmpty
              ? _buildEmptyState(Icons.bookmark_border_rounded, 'قائمة المشاهدة فارغة', 'أضف الأعمال التي تنوي مشاهدتها لاحقاً بنقرة واحدة من صفحة التفاصيل')
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
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
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.border),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
