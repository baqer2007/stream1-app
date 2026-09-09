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

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  bool isDark = true;
  bool isFamilyMode = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isFamilyMode = prefs.getBool('app_family_mode') ?? false;
    isDark = prefs.getBool('app_dark_theme') ?? true;
  }

  void toggleTheme() async {
    isDark = !isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_dark_theme', isDark);
    notifyListeners();
  }

  void toggleFamilyMode(bool val) async {
    isFamilyMode = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_family_mode', val);
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.init();
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
          title: 'سينمانا',
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0F141C),
            primaryColor: const Color(0xFFE50914),
            cardColor: const Color(0xFF182232),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFE50914),
              surface: Color(0xFF182232),
              secondary: Color(0xFFE50914),
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

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentNavIndex = 0;

  // معرفات التصنيفات الحقيقية من شبكة سينمانا
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
    {'id': 80, 'ar': 'إثارة'},
    {'id': 89, 'ar': 'حرب'},
    {'id': 87, 'ar': 'خارق للطبيعة'},
    {'id': 76, 'ar': 'غموض'},
    {'id': 58, 'ar': 'سيرة ذاتية'},
    {'id': 57, 'ar': 'رسوم متحركة'},
    {'id': 68, 'ar': 'تاريخي'},
    {'id': 67, 'ar': 'خيالي'},
    {'id': 65, 'ar': 'عائلي'},
  ];

  Map<String, dynamic>? _selectedCategory;
  List<dynamic> _bannerItems = [];
  List<dynamic> _marvelItems = [];
  List<dynamic> _featuredItems = [];
  List<dynamic> _recentItems = [];
  List<dynamic> _categoryItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeShelves();
  }

  Future<void> _loadHomeShelves() async {
    setState(() => _isLoading = true);
    try {
      final res = await Future.wait([
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 10),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 10),
        StreamService.fetchFeed(isSeries: false, page: 1, perPage: 10),
      ]);
      if (mounted) {
        setState(() {
          _bannerItems = [...res[0].take(5)];
          _marvelItems = res[0];
          _featuredItems = res[1];
          _recentItems = res[2];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCategory(Map<String, dynamic> cat) async {
    setState(() {
      _selectedCategory = cat;
      _isLoading = true;
    });

    if (cat['id'] == 0) {
      await _loadHomeShelves();
      return;
    }

    final items = await StreamService.fetchByCategory(cat['id']);
    if (mounted) {
      setState(() {
        _categoryItems = items;
        _isLoading = false;
      });
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F141C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F141C),
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),
              const Text('سينمانا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.cast, color: Colors.white70),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
            : (_selectedCategory != null && _selectedCategory!['id'] != 0)
                ? _buildCategoryGrid()
                : _buildHomeBody(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          backgroundColor: const Color(0xFF141A24),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          onTap: (i) {
            setState(() => _currentNavIndex = i);
            if (i == 1) _openCategoriesDrawer();
            if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            if (i == 3) Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'الأقسام'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'بحث'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'الحساب'),
          ],
        ),
      ),
    );
  }

  void _openCategoriesDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF182232),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 14),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('الأقسام والتصنيفات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            ..._officialCategories.map((cat) => ListTile(
                  title: Text(cat['ar'], style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(context);
                    _loadCategory(cat);
                  },
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeBody() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bannerItems.isNotEmpty) _buildHeroBanner(),
          const SizedBox(height: 14),
          _buildHorizontalShelf('عالم مارفل 4K', _marvelItems),
          _buildHorizontalShelf('الأفلام المميزة', _featuredItems),
          _buildHorizontalShelf('أضيف مؤخراً', _recentItems),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeroBanner() {
    final item = _bannerItems.first;
    final poster = StreamService.extractPoster(item);
    final title = item['ar_title'] ?? item['en_title'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      height: 185,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: poster.isNotEmpty ? DecorationImage(image: NetworkNetworkImageProvider(poster), fit: BoxFit.cover) : null,
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
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
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => _openDetails(item),
                  icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                  label: const Text('شاهد الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalShelf(String title, List<dynamic> items) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Text('المزيد', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final poster = StreamService.extractPoster(item);
              final name = item['ar_title'] ?? item['en_title'] ?? '';
              final score = (item['stars'] ?? '7.0').toString();

              return InkWell(
                onTap: () => _openDetails(item),
                child: Container(
                  width: 105,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: poster.isNotEmpty
                            ? Image.network(poster, height: 150, width: 105, fit: BoxFit.cover)
                            : Container(height: 150, width: 105, color: const Color(0xFF182232)),
                      ),
                      const SizedBox(height: 4),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(3)),
                            child: const Text('IMDb', style: TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
                          Text(score, style: const TextStyle(color: Colors.white70, fontSize: 10)),
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

  Widget _buildCategoryGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('تصنيف: ${_selectedCategory!['ar']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => _loadCategory({'id': 0, 'ar': 'الكل'}),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemCount: _categoryItems.length,
            itemBuilder: (ctx, i) {
              final item = _categoryItems[i];
              final poster = StreamService.extractPoster(item);
              final name = item['ar_title'] ?? item['en_title'] ?? '';

              return InkWell(
                onTap: () => _openDetails(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: poster.isNotEmpty
                            ? Image.network(poster, width: double.infinity, fit: BoxFit.cover)
                            : Container(color: const Color(0xFF182232)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
        ),
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
            subtitleTextHeader: _isSeries ? 'الموسم 1 الحلقة ${epIndex ?? 1}' : '',
            videoUrl: source['video_url'],
            subtitleUrl: subUrl,
            qualities: List<Map<String, dynamic>>.from(source['qualities'] ?? []),
            episodes: _episodes,
            currentEpIndex: epIndex ?? 1,
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
        backgroundColor: const Color(0xFF0F141C),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: poster.isNotEmpty ? Image.network(poster, width: 115, height: 165, fit: BoxFit.cover) : Container(width: 115, height: 165, color: Colors.grey.shade900),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(_isSeries ? 'مسلسل' : 'فيلم', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isLaunching ? null : () => _play(_isSeries && _episodes.isNotEmpty ? _episodes.first : null, 1),
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: Text(_isSeries ? 'مشاهدة الحلقة 1' : 'مشاهدة الآن', style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (story.isNotEmpty) ...[
              const Text('القصة', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(story, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
            ],
            if (_isSeries && _episodes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('الحلقات (${_episodes.length})', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._episodes.asMap().entries.map((e) {
                final ep = e.value;
                final idx = e.key + 1;
                return ListTile(
                  leading: const Icon(Icons.play_circle_fill, color: Color(0xFFE50914)),
                  title: Text('الحلقة $idx', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Colors.white54),
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
// المشغل الجديد المطابق لصور التصميم (1000018617 / 1000018618 / 1000018621)
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
  bool _filterScenes = true;
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white70),
                title: const Text('دقة الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text(_activeQuality, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showQualityPicker();
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.closed_caption, color: Colors.white70),
                title: const Text('الترجمة', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: const Text('عربي', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.aspect_ratio, color: Colors.white70),
                title: const Text('أبعاد الشاشة', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: const Text('ممتلئ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                onTap: () {
                  setState(() {
                    _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
                  });
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white10, height: 1),
              const ListTile(
                leading: const Icon(Icons.fast_forward, color: Colors.white70),
                title: Text('فترة تمرير الفيديو', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text('10 ثواني', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              const Divider(color: Colors.white10, height: 1),
              const ListTile(
                leading: const Icon(Icons.speed, color: Colors.white70),
                title: Text('سرعة العرض', style: TextStyle(color: Colors.white, fontSize: 13)),
                trailing: Text('الافتراضي', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                title: const Text('حذف المشاهد الغير ملائمة', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: _filterScenes,
                activeColor: const Color(0xFFE50914),
                onChanged: (val) {
                  setState(() => _filterScenes = val);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A24),
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

              // الترجمة
              if (_currentSubText.isNotEmpty)
                Positioned(
                  bottom: 60,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Text(
                      _currentSubText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                    ),
                  ),
                ),

              // أدوات التحكم المتطابقة مع الصورة 1000018617 و 1000018620
              if (_showControls) ...[
                // شريط العنوان العلوي
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
                            if (widget.subtitleTextHeader.isNotEmpty)
                              Text(widget.subtitleTextHeader, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.tune, color: Colors.white),
                          onPressed: _openSettingsBottomSheet,
                        ),
                      ],
                    ),
                  ),
                ),

                // أزرار المنتصف (تقديم وترجيع وتشغيل)
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.fast_rewind, color: Colors.white),
                        onPressed: () {
                          final p = _controller!.value.position - const Duration(seconds: 10);
                          _controller!.seekTo(p < Duration.zero ? Duration.zero : p);
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 48,
                        icon: Icon(_controller != null && _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                          });
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.fast_forward, color: Colors.white),
                        onPressed: () {
                          final p = _controller!.value.position + const Duration(seconds: 10);
                          _controller!.seekTo(p);
                        },
                      ),
                    ],
                  ),
                ),

                // شريط التقدم السفلي والوقتين
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
                                    child: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
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
        backgroundColor: const Color(0xFF0F141C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F141C),
          elevation: 0,
          title: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'ابحث عن فيلم أو مسلسل...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none),
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
        backgroundColor: const Color(0xFF0F141C),
        appBar: AppBar(title: const Text('التنزيلات'), backgroundColor: const Color(0xFF0F141C), elevation: 0),
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
