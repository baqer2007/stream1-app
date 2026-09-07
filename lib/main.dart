import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

// -------------------------------------------------------------
// 1. محرك سينمانا الصافي (CEE Pure Engine)
// -------------------------------------------------------------
class CinemanaPureEngine {
  static const String _apiBase = 'https://cee.buzz/api/android';

  static Map<String, String> get headers => {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
        'Accept': 'application/json, text/plain, */*',
      };

  static Future<List<Map<String, dynamic>>> fetchCatalog({
    required int page,
    required String level, // '0' للأفلام، '1' للمسلسلات
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/video/V/2/itemsPerPage/24/pageNumber/$page/level/$level'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        return List<Map<String, dynamic>>.from(list);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> searchCinemana(String query) async {
    try {
      final b64 = base64Url.encode(utf8.encode(query.trim())).replaceAll('=', '');
      final res = await http.get(
        Uri.parse('$_apiBase/video/V/2/itemsPerPage/30/video_title_search/$b64/itemsPerPage/30/pageNumber/0/level/0'),
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        return List<Map<String, dynamic>>.from(list);
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchEpisodes(String parentId) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/video/V/2/itemsPerPage/100/parent_id/$parentId/itemsPerPage/100/pageNumber/0/level/2'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        return List<Map<String, dynamic>>.from(list);
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getStreamData(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/transcoddedFiles/id/$videoId'),
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['videos'] ?? []);
        if (list.isEmpty) return null;

        List<Map<String, String>> qualities = [];
        for (var item in list) {
          final resName = item['resolution']?.toString() ?? 'Auto';
          final url = item['videoUrl']?.toString() ?? item['videourl']?.toString() ?? item['url']?.toString();
          if (url != null && url.isNotEmpty) {
            qualities.add({'resolution': resName, 'url': url});
          }
        }
        if (qualities.isEmpty) return null;

        final defaultUrl = qualities.firstWhere(
          (q) => q['resolution'] == '480p' || q['resolution'] == '360p',
          orElse: () => qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first),
        )['url'];

        return {'default_url': defaultUrl, 'qualities': qualities};
      }
    } catch (_) {}
    return null;
  }
}

// -------------------------------------------------------------
// 2. طبقة التخزين الموحدة (LocalStorageService)
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

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 25, String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => x[idField]?.toString() == item[idField]?.toString());
    list.insert(0, item);
    if (list.length > maxLength) list.removeRange(maxLength, list.length);
    await setList(key, list);
  }

  static Future<void> removeItem(String key, String id, {String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => x[idField]?.toString() == id);
    await setList(key, list);
  }
}

// -------------------------------------------------------------
// 3. مدير التنزيلات (DownloadManager)
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

      int downloadedBytes = file.existsSync() ? file.lengthSync() : 0;
      final client = http.Client();
      download.client = client;

      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(CinemanaPureEngine.headers);
      if (downloadedBytes > 0) request.headers['Range'] = 'bytes=$downloadedBytes-';

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
          'nb': targetId,
          'title': title,
          'path': filePath,
          'size': '$fileSizeMb MB',
          'imgUrl': poster,
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
// 4. إدارة الحالة العامة (AppState)
// -------------------------------------------------------------
class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  bool isFamilyMode = true;
  String currentProfile = 'الرئيسي';
  List<String> profiles = ['الرئيسي', 'أنمي', 'أطفال'];
  bool isAdmin = false;
  String deviceId = '';

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('app_device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'usr_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString('app_device_id', deviceId);
    }
    currentProfile = prefs.getString('active_profile') ?? 'الرئيسي';
    isFamilyMode = prefs.getBool('app_family_mode') ?? true;
    isAdmin = prefs.getBool('is_admin_mode') ?? false;

    StreamService.sendHeartbeat(deviceId);
    Timer.periodic(const Duration(minutes: 4), (_) => StreamService.sendHeartbeat(deviceId));
  }

  void switchProfile(String p) async {
    currentProfile = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_profile', p);
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
  await AppState.instance.initSession();
  StreamService.startRelayWorker();
  runApp(const OnebrFutureApp());
}

class OnebrFutureApp extends StatelessWidget {
  const OnebrFutureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ONEBR TV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF030712),
        primaryColor: const Color(0xFFFF003C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF003C),
          secondary: Color(0xFF00F0FF),
          surface: Color(0xFF0B0F19),
        ),
      ),
      home: const FutureHomeScreen(),
    );
  }
}

// -------------------------------------------------------------
// 5. الشاشة الرئيسية
// -------------------------------------------------------------
class FutureHomeScreen extends StatefulWidget {
  const FutureHomeScreen({super.key});

  @override
  State<FutureHomeScreen> createState() => _FutureHomeScreenState();
}

class _FutureHomeScreenState extends State<FutureHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _bannerList = [];
  List<Map<String, dynamic>> _continueWatching = [];
  bool _isLoading = true;
  bool _isSearching = false;
  int _page = 0;
  String _selectedType = '0'; // 0: أفلام، 1: مسلسلات

  @override
  void initState() {
    super.initState();
    _loadCinemanaCatalog(reset: true);
    _loadContinueWatching();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoading && !_isSearching) _loadCinemanaCatalog(reset: false);
      }
    });
  }

  void _loadContinueWatching() async {
    final list = await LocalStorageService.getList('continue_watching_pure');
    if (mounted) setState(() => _continueWatching = list);
  }

  Future<void> _loadCinemanaCatalog({bool reset = false}) async {
    if (reset) {
      _page = 0;
      setState(() => _isLoading = true);
    }

    final items = await CinemanaPureEngine.fetchCatalog(page: _page, level: _selectedType);

    if (mounted) {
      setState(() {
        if (reset) {
          _catalog = items;
          _bannerList = items.take(5).toList();
        } else {
          _catalog.addAll(items);
        }
        _page++;
        _isLoading = false;
      });
    }
  }

  void _onSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _isSearching = false);
      _loadCinemanaCatalog(reset: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearching = true;
    });

    final results = await CinemanaPureEngine.searchCinemana(q);
    if (mounted) {
      setState(() {
        _catalog = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: _buildFuturisticDrawer(),
        body: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF003C).withOpacity(0.18),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFFF003C).withOpacity(0.3), blurRadius: 160, spreadRadius: 60),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 120,
              left: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00F0FF).withOpacity(0.12),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00F0FF).withOpacity(0.2), blurRadius: 160, spreadRadius: 50),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Builder(
                            builder: (ctx) => GestureDetector(
                              onTap: () => Scaffold.of(ctx).openDrawer(),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFFF003C), Color(0xFF7000FF)]),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: const Color(0xFFFF003C).withOpacity(0.5), blurRadius: 12)],
                                ),
                                child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                          const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          _buildGlassSwitch(),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: TextField(
                              controller: _searchController,
                              onSubmitted: _onSearch,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'ابحث في مكتبة الأعمال المتوفرة...',
                                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                prefixIcon: Icon(Icons.search, color: Color(0xFF00F0FF), size: 20),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isSearching && _continueWatching.isNotEmpty)
                    SliverToBoxAdapter(child: _buildContinueWatchingShelf()),
                  if (!_isSearching && _bannerList.isNotEmpty)
                    SliverToBoxAdapter(child: _buildFuturisticHero()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isSearching
                                ? 'نتائج البحث'
                                : (_selectedType == '0' ? '⚡ أحدث الأفلام' : '📺 أحدث المسلسلات والأنمي'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                            ),
                            child: const Text('أعلى سرعة بأقل إنترنت ⚡', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _isLoading && _catalog.isEmpty
                      ? const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator(color: Color(0xFFFF003C))),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.58,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 14,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _buildFuturisticCard(_catalog[i]),
                              childCount: _catalog.length,
                            ),
                          ),
                        ),
                  if (_isLoading && _catalog.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          _switchBtn('أفلام', '0'),
          _switchBtn('مسلسلات', '1'),
        ],
      ),
    );
  }

  Widget _switchBtn(String title, String val) {
    final active = _selectedType == val;
    return GestureDetector(
      onTap: () {
        if (_selectedType != val) {
          setState(() => _selectedType = val);
          _loadCinemanaCatalog(reset: true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: active ? const LinearGradient(colors: [Color(0xFFFF003C), Color(0xFF990024)]) : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active ? [BoxShadow(color: const Color(0xFFFF003C).withOpacity(0.4), blurRadius: 10)] : null,
        ),
        child: Text(
          title,
          style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
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
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('continue_watching_pure');
                  setState(() => _continueWatching.clear());
                },
                child: const Text('مسح', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _continueWatching.length,
            itemBuilder: (ctx, i) {
              final item = _continueWatching[i];
              final isTv = item['is_series'] == true;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: item, isSeries: isTv))).then((_) => _loadContinueWatching()),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        item['imgUrl'] != null ? Image.network(item['imgUrl'], fit: BoxFit.cover) : Container(color: Colors.black),
                        Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]))),
                        Positioned(
                          bottom: 6,
                          right: 8,
                          left: 8,
                          child: Text(item['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFuturisticHero() {
    final item = _bannerList.first;
    final imgUrl = item['imgUrl']?.toString() ?? '';
    final title = item['title']?.toString() ?? item['en_title']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFF003C).withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            imgUrl.isNotEmpty ? Image.network(imgUrl, fit: BoxFit.cover) : Container(color: Colors.black54),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF030712), Colors.transparent],
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 18,
              left: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: item, isSeries: _selectedType == '1'))).then((_) => _loadContinueWatching()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF003C), Color(0xFF7000FF)]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFFFF003C).withOpacity(0.6), blurRadius: 14)],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 4),
                          Text('تشغيل فوري', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticCard(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? item['en_title']?.toString() ?? '';
    final imgUrl = item['imgUrl']?.toString() ?? '';
    final year = item['year']?.toString() ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: item, isSeries: _selectedType == '1'))).then((_) => _loadContinueWatching()),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imgUrl.isNotEmpty ? Image.network(imgUrl, fit: BoxFit.cover) : Container(color: Colors.grey.shade900),
                    if (year.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(year, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticDrawer() {
    final app = AppState.instance;
    return Drawer(
      backgroundColor: const Color(0xFF0B0F19),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 48, bottom: 24, right: 20, left: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF003C), Color(0xFF1E293B)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ONEBR TV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 10),
                Text('الملف: ${app.currentProfile}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_done_rounded, color: Color(0xFF10B981)),
            title: const Text('التنزيلات المحفوظة', style: TextStyle(fontWeight: FontWeight.bold)),
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
          if (app.isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber),
              title: const Text('👑 لوحة تحكم المشرف', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
              },
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 6. شاشة التفاصيل (Details Screen)
// -------------------------------------------------------------
class DetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isSeries;

  const DetailScreen({super.key, required this.item, required this.isSeries});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _isLoading = false;
  bool _isFav = false;
  bool _isWatchLater = false;
  List<Map<String, dynamic>> _episodes = [];

  @override
  void initState() {
    super.initState();
    _checkSavedStates();
    if (widget.isSeries) _loadEpisodes();
  }

  void _checkSavedStates() async {
    final id = widget.item['nb'].toString();
    final isFav = await FavoritesService.isFavorited(id);
    final wl = await LocalStorageService.getList('watch_later_pure');
    if (mounted) {
      setState(() {
        _isFav = isFav;
        _isWatchLater = wl.any((x) => x['nb']?.toString() == id);
      });
    }
  }

  void _toggleWatchLater() async {
    final id = widget.item['nb'].toString();
    if (_isWatchLater) {
      await LocalStorageService.removeItem('watch_later_pure', id);
    } else {
      await LocalStorageService.appendItem('watch_later_pure', widget.item);
    }
    setState(() => _isWatchLater = !_isWatchLater);
  }

  void _loadEpisodes() async {
    setState(() => _isLoading = true);
    final eps = await CinemanaPureEngine.fetchEpisodes(widget.item['nb'].toString());
    if (mounted) setState(() { _episodes = eps; _isLoading = false; });
  }

  void _startPlay(String videoId, String title) async {
    setState(() => _isLoading = true);
    final toSave = Map<String, dynamic>.from(widget.item);
    toSave['is_series'] = widget.isSeries;
    await LocalStorageService.appendItem('continue_watching_pure', toSave);

    final streamData = await CinemanaPureEngine.getStreamData(videoId);
    setState(() => _isLoading = false);

    if (streamData != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PurePlayerScreen(
            mediaId: videoId,
            title: title,
            videoUrl: streamData['default_url'],
            qualities: List<Map<String, String>>.from(streamData['qualities']),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل رابط الفيديو من الخادم'), backgroundColor: Color(0xFFFF003C)),
      );
    }
  }

  void _triggerDownload() async {
    final videoId = widget.item['nb'].toString();
    final title = widget.item['title'] ?? 'Video';
    final streamData = await CinemanaPureEngine.getStreamData(videoId);
    if (streamData != null) {
      DownloadManager.instance.startDownload(
        targetId: videoId,
        title: title,
        url: streamData['default_url'],
        poster: widget.item['imgUrl'] ?? '',
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بدأ التنزيل في قائمة التنزيلات!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item['title']?.toString() ?? widget.item['en_title']?.toString() ?? '';
    final enTitle = widget.item['en_title']?.toString() ?? '';
    final imgUrl = widget.item['imgUrl']?.toString() ?? '';
    final story = widget.item['content']?.toString() ?? 'لا يوجد وصف متاح.';
    final year = widget.item['year']?.toString() ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: const Color(0xFF030712),
              actions: [
                IconButton(
                  icon: Icon(_isWatchLater ? Icons.watch_later_rounded : Icons.watch_later_outlined, color: const Color(0xFF00F0FF)),
                  onPressed: _toggleWatchLater,
                ),
                IconButton(
                  icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
                  onPressed: () async {
                    final state = await FavoritesService.toggleFavorite(widget.item, widget.isSeries ? 'tv' : 'movie');
                    setState(() => _isFav = state);
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    imgUrl.isNotEmpty ? Image.network(imgUrl, fit: BoxFit.cover) : Container(color: Colors.black),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFF030712), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    if (enTitle.isNotEmpty && enTitle != title) ...[
                      const SizedBox(height: 4),
                      Text(enTitle, style: const TextStyle(fontSize: 13, color: Color(0xFF00F0FF), fontWeight: FontWeight.bold)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (year.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                            child: Text(year, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _triggerDownload,
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('تنزيل في التطبيق', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!widget.isSeries)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF003C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            elevation: 8,
                          ),
                          onPressed: _isLoading ? null : () => _startPlay(widget.item['nb'].toString(), title),
                          icon: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                          label: const Text('مشاهدة الفيلم الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text('قصة العمل:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(story, style: const TextStyle(color: Colors.white70, height: 1.6, fontSize: 13)),
                    if (widget.isSeries) ...[
                      const SizedBox(height: 24),
                      Text('الحلقات (${_episodes.length}):', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                          : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.3,
                              ),
                              itemCount: _episodes.length,
                              itemBuilder: (ctx, i) {
                                final ep = _episodes[i];
                                final epNum = i + 1;
                                return GestureDetector(
                                  onTap: () => _startPlay(ep['nb'].toString(), '$title - حلقة $epNum'),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0B0F19),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Center(
                                      child: Text('$epNum', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white)),
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
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 7. المشغل المتكامل مع الترجمة، إيماءات الصوت، والقفل
// -------------------------------------------------------------
class Subtitle {
  final int index;
  final Duration start;
  final Duration end;
  final String text;
  Subtitle({required this.index, required this.start, required this.end, required this.text});
}

class PurePlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, String>> qualities;
  final bool isLocalFile;

  const PurePlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.isLocalFile = false,
  });

  @override
  State<PurePlayerScreen> createState() => _PurePlayerScreenState();
}

class _PurePlayerScreenState extends State<PurePlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isReady = false;
  bool _isLocked = false;

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
    _startStream(widget.videoUrl);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveCurrentPosition();
    }
  }

  void _saveCurrentPosition() {
    if (_controller != null && _controller!.value.isInitialized) {
      final pos = _controller!.value.position.inSeconds;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('resume_pure_${widget.mediaId}', pos);
      });
    }
  }

  void _fetchSubs() async {
    try {
      final res = await http.get(Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'), headers: CinemanaPureEngine.headers).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        dynamic info = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final subUrl = info['arTranslationFilePath']?.toString() ?? info['arTranslationFile']?.toString() ?? '';
        if (subUrl.isNotEmpty) {
          final sRes = await http.get(Uri.parse(subUrl), headers: CinemanaPureEngine.headers);
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

  void _startStream(String url, {int startAtSecond = 0}) async {
    setState(() => _isReady = false);

    _controller?.removeListener(_updateSubsAndProgress);
    _controller?.dispose();
    _chewieController?.dispose();

    _controller = widget.isLocalFile
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: CinemanaPureEngine.headers,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );

    await _controller!.initialize();

    final prefs = await SharedPreferences.getInstance();
    int resumePos = startAtSecond > 0 ? startAtSecond : (prefs.getInt('resume_pure_${widget.mediaId}') ?? 0);
    if (resumePos > 5 && resumePos < _controller!.value.duration.inSeconds - 10) {
      await _controller!.seekTo(Duration(seconds: resumePos));
    }

    _controller!.addListener(_updateSubsAndProgress);

    _chewieController = ChewieController(
      videoPlayerController: _controller!,
      autoPlay: true,
      looping: false,
      aspectRatio: _controller!.value.aspectRatio,
      showControlsOnInitialize: false,
      allowFullScreen: true,
      showOptions: false,
    );

    if (mounted) {
      setState(() => _isReady = true);
      if (!widget.isLocalFile) {
        Future.delayed(const Duration(milliseconds: 500), _fetchSubs);
      }
    }
  }

  void _updateSubsAndProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final pos = _controller!.value.position;

    if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
      final adjustedPos = pos + Duration(milliseconds: (_subtitleOffsetSeconds * 1000).round());
      final text = _findSubtitleBinary(adjustedPos);
      if (text != _activeSubtitleText && mounted) setState(() => _activeSubtitleText = text);
    } else if (_activeSubtitleText.isNotEmpty && mounted) {
      setState(() => _activeSubtitleText = '');
    }

    if (pos.inSeconds % 5 == 0) _saveCurrentPosition();
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

  void _onVerticalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final delta = details.primaryDelta ?? 0;
    _volumeIndicator = (_volumeIndicator - (delta / constraints.maxHeight)).clamp(0.0, 1.0);
    _controller?.setVolume(_volumeIndicator);

    setState(() => _showVolumeIndicator = true);
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0F19),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر جودة البث (للإنترنت الضعيف اختر 360p أو 480p):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            ...widget.qualities.map((q) => ListTile(
                  leading: const Icon(Icons.speed_rounded, color: Color(0xFF00F0FF)),
                  title: Text(q['resolution'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    if (q['url'] != null) {
                      final cur = _controller?.value.position.inSeconds ?? 0;
                      _startStream(q['url']!, startAtSecond: cur);
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _openSubtitleSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0F19),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('تشغيل الترجمة العربية'),
                  value: _subtitlesEnabled,
                  onChanged: (v) {
                    setSheet(() => _subtitlesEnabled = v);
                    setState(() => _subtitlesEnabled = v);
                  },
                ),
                Text('مزامنة الترجمة: ${_subtitleOffsetSeconds.toStringAsFixed(1)} ثانية'),
                Slider(
                  value: _subtitleOffsetSeconds, min: -5.0, max: 5.0, divisions: 20,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (v) {
                    setSheet(() => _subtitleOffsetSeconds = v);
                    setState(() => _subtitleOffsetSeconds = v);
                  },
                ),
                const Text('حجم الخط:'),
                Slider(
                  value: _subtitleFontSize, min: 14, max: 32, divisions: 9,
                  activeColor: const Color(0xFF00F0FF),
                  onChanged: (v) {
                    setSheet(() => _subtitleFontSize = v);
                    setState(() => _subtitleFontSize = v);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentPosition();
    _indicatorTimer?.cancel();
    _controller?.removeListener(_updateSubsAndProgress);
    _controller?.dispose();
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
                        : const CircularProgressIndicator(color: Color(0xFFFF003C)),
                  ),
                  if (_showVolumeIndicator)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: Colors.black87.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
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
                          decoration: BoxDecoration(color: _subtitleBgColor, borderRadius: BorderRadius.circular(16)),
                          child: Text(_activeSubtitleText, style: TextStyle(color: _subtitleTextColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  if (!_isLocked)
                    Positioned(
                      top: 14,
                      left: 14,
                      right: 14,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.high_quality_rounded, color: Color(0xFF00F0FF), size: 24),
                                onPressed: _showQualityPicker,
                              ),
                              IconButton(
                                icon: const Icon(Icons.subtitles_rounded, color: Colors.white, size: 22),
                                onPressed: _openSubtitleSettings,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 22),
                                onPressed: () => setState(() => _isLocked = true),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                                onPressed: () => Navigator.pop(context),
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
                        decoration: const BoxDecoration(color: Color(0xFFFF003C), shape: BoxShape.circle),
                        child: IconButton(
                          icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
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
// 8. الشاشات التابعة (Downloads, Favorites, WatchLater, Admin)
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
    _load();
    DownloadManager.instance.addListener(() => setState(() {}));
  }

  void _load() async {
    final list = await LocalStorageService.getList('downloaded_works_list');
    if (mounted) setState(() => _completed = list);
  }

  @override
  Widget build(BuildContext context) {
    final active = DownloadManager.instance.activeDownloads.values.toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('📥 مدير التنزيلات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              const Text('⏳ جاري التنزيل:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
              ...active.map((d) => ListTile(
                    title: Text(d.title),
                    subtitle: LinearProgressIndicator(value: d.progress, color: const Color(0xFF10B981)),
                    trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => DownloadManager.instance.cancelDownload(d.id)),
                  )),
            ],
            const SizedBox(height: 12),
            const Text('✅ التنزيلات الجاهزة (دون إنترنت):', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ..._completed.map((c) => ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981)),
                  title: Text(c['title'] ?? ''),
                  subtitle: Text(c['size'] ?? ''),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurePlayerScreen(mediaId: c['nb'], title: c['title'], videoUrl: c['path'], qualities: const [], isLocalFile: true))),
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
    FavoritesService.getFavorites().then((l) {
      if (mounted) setState(() => _favorites = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('⭐ المفضلة')),
        body: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.6),
          itemCount: _favorites.length,
          itemBuilder: (ctx, i) {
            final it = _favorites[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: it, isSeries: it['media_type'] == 'tv'))),
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: it['imgUrl'] != null ? Image.network(it['imgUrl'], fit: BoxFit.cover) : Container(color: Colors.black)),
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
    LocalStorageService.getList('watch_later_pure').then((l) {
      if (mounted) setState(() => _items = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('🕒 المشاهدة لاحقاً')),
        body: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.6),
          itemCount: _items.length,
          itemBuilder: (ctx, i) {
            final it = _items[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(item: it, isSeries: false))),
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: it['imgUrl'] != null ? Image.network(it['imgUrl'], fit: BoxFit.cover) : Container(color: Colors.black)),
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
    StreamService.getRealAdminStats().then((s) {
      if (mounted) setState(() { _stats = s; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('👑 لوحة تحكم المشرف')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('المتصلين حالياً: ${_stats['active_users'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  const SizedBox(height: 10),
                  Text('إجمالي المشاهدات: ${_stats['total_views'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
                ],
              ),
      ),
    );
  }
}
