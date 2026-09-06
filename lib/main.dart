import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'stream_service.dart';
import 'favorites_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF07090E),
        primaryColor: const Color(0xFFE50914),
        cardColor: const Color(0xFF0F1422),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF0F1422),
          secondary: Color(0xFF00F0FF),
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

class _MainHomeScreenState extends State<MainHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _items = [];
  int _currentOffset = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    StreamService.startRelayWorker();
    _fetchCeeFeed(isRefresh: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 350) {
        if (!_isLoadingMore && _hasMore) {
          _fetchCeeFeed(isRefresh: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // جلب الأعمال عبر API NewlyVideosItems الحقيقي
  Future<void> _fetchCeeFeed({bool isRefresh = false}) async {
    if (isRefresh) {
      _currentOffset = 0;
      _hasMore = true;
      setState(() => _isLoadingInitial = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final url = Uri.parse(
          'https://cee.buzz/api/android/newlyVideosItems/level/0/offset/$_currentOffset/');

      final res = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36',
        'Referer': 'https://cee.buzz/home',
        'Accept': 'application/json, text/plain, */*',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(res.body);
        List list = (decoded is List)
            ? decoded
            : (decoded['articles'] ?? decoded['data'] ?? []);

        if (mounted) {
          setState(() {
            if (isRefresh) {
              _items = list;
            } else {
              _items.addAll(list);
            }
            if (list.isEmpty || list.length < 10) {
              _hasMore = false;
            } else {
              _currentOffset += 12;
            }
            _isLoadingInitial = false;
            _isLoadingMore = false;
          });

          if (isRefresh && list.isNotEmpty) {
            _preCacheFirstBatch(list);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _preCacheFirstBatch(List rawList) {
    final List<Map<String, String>> batch = [];
    for (var it in rawList.take(20)) {
      final nb = it['nb']?.toString();
      final title = it['en_title'] ?? it['ar_title'] ?? '';
      if (nb != null) {
        batch.add({'id': nb, 'title': title});
      }
    }
    StreamService.preCacheMovieTitles(batch);
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    final b64Query = base64Url.encode(utf8.encode(query.trim()));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00F0FF))),
    );

    try {
      final url = Uri.parse(
          'https://cee.buzz/api/android/video/V/2/itemsPerPage/20/video_title_search/$b64Query/itemsPerPage/12/pageNumber/0/level/0');
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile)',
        'Referer': 'https://cee.buzz/home',
      });

      Navigator.pop(context);

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(res.body);
        List results = (decoded is List) ? decoded : (decoded['articles'] ?? []);

        if (results.isNotEmpty && mounted) {
          setState(() {
            _items = results;
            _hasMore = false;
          });
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لم يتم العثور على نتائج مطابقة')),
          );
        }
      }
    } catch (_) {
      Navigator.pop(context);
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(media: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE50914)),
                ),
                child: const Icon(Icons.movie_filter_rounded,
                    color: Color(0xFFE50914), size: 18),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFF3344), Color(0xFF00F0FF)],
                ).createShader(bounds),
                child: const Text(
                  'ONEBR TV',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_rounded,
                  color: Color(0xFFF59E0B)),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FavoritesScreen()));
              },
            ),
          ],
        ),
        body: _isLoadingInitial
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: () => _fetchCeeFeed(isRefresh: true),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // شريط البحث الذكي
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _performSearch,
                          decoration: InputDecoration(
                            hintText: 'بحث في سينمانا (اسم الفيلم أو المسلسل)...',
                            hintStyle: const TextStyle(
                                fontSize: 12, color: Colors.white38),
                            prefixIcon: const Icon(Icons.search,
                                color: Color(0xFF00F0FF)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _fetchCeeFeed(isRefresh: true);
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F1422),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),

                      if (_items.isNotEmpty)
                        _buildHeroBanner(_items.first, screenWidth),

                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.0, vertical: 10.0),
                        child: Text(
                          '🔥 الأعمال المتوفرة في سينمانا (تحديث لحظي)',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white),
                        ),
                      ),

                      _buildCeeGrid(),

                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00F0FF))),
                        ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeroBanner(Map<String, dynamic> item, double width) {
    final title = item['ar_title'] ?? item['en_title'] ?? '';
    final poster = item['imgThumbObjUrl'] ??
        item['imgMediumThumbObjUrl'] ??
        item['img'] ??
        '';

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: width * 0.52,
          width: double.infinity,
          decoration: BoxDecoration(
            image: poster.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(poster), fit: BoxFit.cover)
                : null,
          ),
        ),
        Container(
          height: width * 0.52,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF07090E), Colors.transparent],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () => _openDetails(item),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 20, color: Colors.white),
                    SizedBox(width: 6),
                    Text('مشاهدة العمل الآن',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCeeGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.58,
        ),
        itemCount: _items.length,
        itemBuilder: (ctx, i) {
          final item = _items[i];
          final title = item['ar_title'] ?? item['en_title'] ?? '';
          final poster = item['imgThumbObjUrl'] ??
              item['imgMediumThumbObjUrl'] ??
              item['img'] ??
              '';
          final stars = item['stars']?.toString() ?? '8';

          return InkWell(
            onTap: () => _openDetails(item),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1422),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      child: poster.isNotEmpty
                          ? Image.network(
                              poster,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: const Color(0xFF172033)),
                            )
                          : Container(color: const Color(0xFF172033)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text('⭐ $stars',
                            style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.bold)),
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
// شاشة تفاصيل العمل المرتبطة بـ nb الحقيقي
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isLaunchingStream = false;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
  }

  void _checkFav() async {
    final nb = widget.media['nb']?.toString() ?? '';
    final isFav = await FavoritesService.isFavorited(nb);
    if (mounted) setState(() => _isFav = isFav);
  }

  void _toggleFav() async {
    final newState =
        await FavoritesService.toggleFavorite(widget.media, 'video');
    if (mounted) {
      setState(() => _isFav = newState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState
              ? 'تمت إضافة العمل إلى المفضلة ⭐'
              : 'تمت إزالة العمل من المفضلة'),
          backgroundColor:
              newState ? const Color(0xFF10B981) : const Color(0xFFE50914),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _playVideo() async {
    setState(() => _isLaunchingStream = true);

    // المعرف الحقيقي الدقيق كما في DevTools
    final nb = widget.media['nb'].toString();
    final title =
        widget.media['ar_title'] ?? widget.media['en_title'] ?? 'فيديو سينمانا';

    // سحب الرابط الفعلي من cee عبر المعرف الحقيقي
    final data = await StreamService.getVideoSource(nb);

    setState(() => _isLaunchingStream = false);

    if (data != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: title,
            videoUrl: data['video_url'],
            qualities:
                List<Map<String, dynamic>>.from(data['qualities'] ?? []),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر جلب سيرفر المشاهدة لهذا العمل حالياً'),
          backgroundColor: Color(0xFFE50914),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.media['ar_title'] ?? widget.media['en_title'] ?? '';
    final enTitle = widget.media['en_title'] ?? '';
    final poster = widget.media['imgThumbObjUrl'] ??
        widget.media['imgMediumThumbObjUrl'] ??
        widget.media['img'] ??
        '';
    final nb = widget.media['nb']?.toString() ?? '';
    final stars = widget.media['stars']?.toString() ?? '8';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          title: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        ? Image.network(poster,
                            width: 110, height: 160, fit: BoxFit.cover)
                        : Container(
                            width: 110,
                            height: 160,
                            color: const Color(0xFF172033)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        if (enTitle.isNotEmpty && enTitle != title) ...[
                          const SizedBox(height: 4),
                          Text(enTitle,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8))),
                        ],
                        const SizedBox(height: 8),
                        Text('⭐ $stars',
                            style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text('معرف سينمانا الحقيقي: $nb',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF00F0FF))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isLaunchingStream ? null : _playVideo,
                        icon: _isLaunchingStream
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded,
                                size: 28, color: Colors.white),
                        label: const Text('مشاهدة العمل الآن',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1422),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _isFav
                              ? const Color(0xFFF59E0B)
                              : Colors.white24),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isFav
                            ? Icons.bookmark_added_rounded
                            : Icons.bookmark_border_rounded,
                        color: _isFav
                            ? const Color(0xFFF59E0B)
                            : Colors.white70,
                      ),
                      onPressed: _toggleFav,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// المشغل مع زر التخطي والجودات
// -------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.videoUrl,
    required this.qualities,
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
  bool _showSkipIntroBtn = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _initFastPlayer(_currentUrl!);
  }

  void _initFastPlayer(String streamUrl) async {
    _chewieController?.dispose();
    _videoPlayerController?.removeListener(_checkIntro);
    await _videoPlayerController?.dispose();

    setState(() {
      _isReady = false;
      _showSkipIntroBtn = false;
    });

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    await _videoPlayerController!.initialize();
    _videoPlayerController!.addListener(_checkIntro);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControlsOnInitialize: true,
      allowFullScreen: true,
      deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFE50914),
        handleColor: const Color(0xFF00F0FF),
        bufferedColor: Colors.white24,
        backgroundColor: Colors.white10,
      ),
      additionalOptions: (context) {
        return <OptionItem>[
          OptionItem(
            onTap: (ctx) => _showQualitySheet(),
            iconData: Icons.hd_outlined,
            title: 'الجودة: $_selectedQualityName',
          ),
        ];
      },
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _checkIntro() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized) return;
    final seconds = _videoPlayerController!.value.position.inSeconds;
    final shouldShow = seconds >= 2 && seconds <= 120;
    if (shouldShow != _showSkipIntroBtn && mounted) {
      setState(() => _showSkipIntroBtn = shouldShow);
    }
  }

  void _skipIntro() {
    if (_videoPlayerController == null) return;
    _videoPlayerController!.seekTo(
        _videoPlayerController!.value.position + const Duration(seconds: 85));
    setState(() => _showSkipIntroBtn = false);
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
            final isSelected = url == _currentUrl;
            return ListTile(
              title: Text(res,
                  style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF00F0FF)
                          : Colors.white)),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Color(0xFF00F0FF))
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (!isSelected && url != null) {
                  setState(() {
                    _currentUrl = url;
                    _selectedQualityName = res;
                  });
                  _initFastPlayer(url);
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
    _videoPlayerController?.removeListener(_checkIntro);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F1422),
      ),
      body: Center(
        child: _isReady && _chewieController != null
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Chewie(controller: _chewieController!),
                  if (_showSkipIntroBtn)
                    Positioned(
                      bottom: 75,
                      left: 20,
                      child: InkWell(
                        onTap: _skipIntro,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFF59E0B), width: 1.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward_rounded,
                                  color: Color(0xFFF59E0B), size: 18),
                              SizedBox(width: 6),
                              Text('تخطي المقدمة (+85s)',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
      ),
    );
  }
}

// -------------------------------------------------------------
// المفضلة
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
    if (mounted) {
      setState(() {
        _favorites = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('⭐ قائمة المفضلة'),
            backgroundColor: const Color(0xFF0F1422)),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : _favorites.isEmpty
                ? const Center(
                    child: Text('لم تقم بإضافة أي أعمال للمفضلة بعد',
                        style: TextStyle(color: Colors.white54)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, i) {
                      final item = _favorites[i];
                      final poster = item['imgThumbObjUrl'] ??
                          item['imgMediumThumbObjUrl'] ??
                          item['img'] ??
                          '';
                      final title =
                          item['ar_title'] ?? item['en_title'] ?? '';

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MediaDetailScreen(media: item),
                            ),
                          ).then((_) => _load());
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1422),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                  child: poster.isNotEmpty
                                      ? Image.network(poster,
                                          width: double.infinity,
                                          fit: BoxFit.cover)
                                      : Container(
                                          color: const Color(0xFF172033)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(5.0),
                                child: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold)),
                              ),
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
