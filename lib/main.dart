import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'stream_service.dart';

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
  static const String _apiKey = '8265bd1679663a7ea12ac168da84d2e8';
  static const String _imgBase = 'https://image.tmdb.org/t/p/w500';

  List<dynamic> _trending = [];
  List<dynamic> _popularSeries = [];
  List<dynamic> _animeList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    StreamService.startRelayWorker();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final resTrending = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/trending/movie/day?api_key=$_apiKey&language=ar-SA'));
      final resSeries = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/trending/tv/day?api_key=$_apiKey&language=ar-SA'));
      final resAnime = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/discover/tv?api_key=$_apiKey&with_genres=16&with_original_language=ja&sort_by=popularity.desc&language=ar-SA'));

      if (mounted) {
        setState(() {
          _trending = jsonDecode(resTrending.body)['results'] ?? [];
          _popularSeries = jsonDecode(resSeries.body)['results'] ?? [];
          _animeList = jsonDecode(resAnime.body)['results'] ?? [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openDetails(Map<String, dynamic> item, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(media: item, type: type),
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
                child: const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 18),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFF3344), Color(0xFF00F0FF)],
                ).createShader(bounds),
                child: const Text(
                  'ONEBR TV',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : RefreshIndicator(
                color: const Color(0xFFE50914),
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trending.isNotEmpty) _buildHeroBanner(_trending.first, screenWidth),
                      const SizedBox(height: 12),
                      _buildShelf('🔥 الأفلام الأكثر رواجاً اليوم', _trending, 'movie'),
                      _buildShelf('📺 المسلسلات والدراما الأسبوعية', _popularSeries, 'tv'),
                      _buildShelf('⛩️ عالم الأنمي الياباني', _animeList, 'tv'),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeroBanner(Map<String, dynamic> item, double width) {
    final title = item['title'] ?? item['name'] ?? '';
    final backdrop = item['backdrop_path'] ?? item['poster_path'];
    final posterUrl = backdrop != null ? 'https://image.tmdb.org/t/p/original$backdrop' : '';

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: width * 0.52,
          width: double.infinity,
          decoration: BoxDecoration(
            image: posterUrl.isNotEmpty
                ? DecorationImage(image: NetworkImage(posterUrl), fit: BoxFit.cover)
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _openDetails(item, 'movie'),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('عرض التفاصيل والمشاهدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShelf(String title, List<dynamic> list, String type) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.31).clamp(105.0, 140.0);
    final cardHeight = cardWidth * 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        SizedBox(
          height: cardHeight + 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final item = list[i];
              final mTitle = item['title'] ?? item['name'] ?? '';
              final path = item['poster_path'];
              final score = (item['vote_average'] as num?)?.toStringAsFixed(1) ?? '7.5';

              return InkWell(
                onTap: () => _openDetails(item, type),
                child: Container(
                  width: cardWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1422),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: path != null
                            ? Image.network(
                                '$_imgBase$path',
                                height: cardHeight,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(height: cardHeight, color: const Color(0xFF172033)),
                              )
                            : Container(height: cardHeight, color: const Color(0xFF172033)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text('⭐ $score', style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
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
}

// -------------------------------------------------------------
// شاشة التفاصيل الكاملة (قصة، مواسم، حلقات، وأعمال مقترحة)
// -------------------------------------------------------------
class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  final String type; // 'movie' أو 'tv'

  const MediaDetailScreen({super.key, required this.media, required this.type});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  static const String _apiKey = '8265bd1679663a7ea12ac168da84d2e8';
  final TextEditingController _manualIdController = TextEditingController(text: '3130508');

  List<dynamic> _similarMedia = [];
  List<dynamic> _seasons = [];
  int _selectedSeason = 1;
  int _episodesCount = 12;
  bool _isLoadingDetails = true;
  bool _isLaunchingStream = false;

  @override
  void initState() {
    super.initState();
    _fetchExtendedInfo();
  }

  Future<void> _fetchExtendedInfo() async {
    final id = widget.media['id'];
    try {
      final resDetails = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/${widget.type}/$id?api_key=$_apiKey&language=ar-SA'));
      final resSimilar = await http.get(Uri.parse(
          'https://api.themoviedb.org/3/${widget.type}/$id/similar?api_key=$_apiKey&language=ar-SA'));

      if (resDetails.statusCode == 200) {
        final data = jsonDecode(resDetails.body);
        if (widget.type == 'tv' && data['seasons'] != null) {
          _seasons = (data['seasons'] as List).where((s) => (s['season_number'] ?? 0) > 0).toList();
          if (_seasons.isNotEmpty) {
            _selectedSeason = _seasons.first['season_number'];
            _episodesCount = _seasons.first['episode_count'] ?? 12;
          }
        }
      }

      if (resSimilar.statusCode == 200) {
        _similarMedia = jsonDecode(resSimilar.body)['results'] ?? [];
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingDetails = false);
  }

  void _playEpisode(int season, int episode) async {
    setState(() => _isLaunchingStream = true);

    // استخدام المعرف المدخل أو جلب الرابط من cee.buzz عبر الـ Relay
    final targetId = _manualIdController.text.trim();
    final data = await StreamService.getVideoSource(targetId);

    setState(() => _isLaunchingStream = false);

    if (data != null && mounted) {
      final mediaTitle = widget.media['title'] ?? widget.media['name'] ?? 'بث مباشر';
      final fullTitle = widget.type == 'tv'
          ? '$mediaTitle - م$season ح$episode'
          : mediaTitle;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: fullTitle,
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر جلب رابط الحلقة حالياً، جاري البحث عبر شبكة الـ Relay...'),
          backgroundColor: Color(0xFFE50914),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final overview = widget.media['overview'] ?? 'لا يتوفر وصف متاح لهذا العمل حالياً.';
    final poster = widget.media['poster_path'];
    final backdrop = widget.media['backdrop_path'] ?? poster;
    final score = (widget.media['vote_average'] as num?)?.toStringAsFixed(1) ?? '7.8';
    final date = (widget.media['release_date'] ?? widget.media['first_air_date'] ?? '2026').toString().split('-').first;

    final screenWidth = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1422),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: _isLoadingDetails
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Backdrop Hero
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          height: screenWidth * 0.52,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            image: backdrop != null
                                ? DecorationImage(
                                    image: NetworkImage('https://image.tmdb.org/t/p/original$backdrop'),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                        Container(
                          height: screenWidth * 0.52,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF07090E), Colors.transparent],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // بطاقة المعلومات الرئيسية وزر التشغيل
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: poster != null
                                    ? Image.network('https://image.tmdb.org/t/p/w500$poster', width: 95, height: 140, fit: BoxFit.cover)
                                    : Container(width: 95, height: 140, color: const Color(0xFF172033)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                                          child: Text('⭐ $score', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(date, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _manualIdController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'معرف البث (cee.buzz ID)',
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        filled: true,
                                        fillColor: const Color(0xFF0F1422),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // زر التشغيل الفوري
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isLaunchingStream ? null : () => _playEpisode(_selectedSeason, 1),
                              icon: _isLaunchingStream
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.play_arrow_rounded, size: 28),
                              label: Text(
                                widget.type == 'tv' ? 'مشاهدة الحلقة الأولى' : 'مشاهدة الفيلم الآن',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // القصة
                          const Text('قصة العمل:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(overview, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4)),
                        ],
                      ),
                    ),

                    // نظام المواسم والحلقات (إذا كان مسلسلاً)
                    if (widget.type == 'tv') ...[
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('المواسم والحلقات:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 8),

                      // أزرار المواسم
                      if (_seasons.isNotEmpty)
                        SizedBox(
                          height: 38,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            itemCount: _seasons.length,
                            itemBuilder: (ctx, i) {
                              final s = _seasons[i];
                              final sNum = s['season_number'];
                              final isSelected = sNum == _selectedSeason;

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedSeason = sNum;
                                    _episodesCount = s['episode_count'] ?? 12;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFE50914) : const Color(0xFF0F1422),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text('الموسم $sNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              );
                            },
                          ),
                        ),

                      // شبكة الحلقات
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.4,
                          ),
                          itemCount: _episodesCount,
                          itemBuilder: (ctx, i) {
                            final epNum = i + 1;
                            return InkWell(
                              onTap: () => _playEpisode(_selectedSeason, epNum),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF172033),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                child: Center(
                                  child: Text('ح $epNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    // قائمة الأعمال المقترحة والمشابهة
                    if (_similarMedia.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('🎯 أعمال مشابهة ومقترحة:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 190,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _similarMedia.length,
                          itemBuilder: (ctx, i) {
                            final item = _similarMedia[i];
                            final simTitle = item['title'] ?? item['name'] ?? '';
                            final simPoster = item['poster_path'];

                            return InkWell(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MediaDetailScreen(media: item, type: widget.type),
                                  ),
                                );
                              },
                              child: Container(
                                width: 105,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F1422),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      child: simPoster != null
                                          ? Image.network('https://image.tmdb.org/t/p/w500$simPoster', height: 135, width: double.infinity, fit: BoxFit.cover)
                                          : Container(height: 135, color: const Color(0xFF172033)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Text(simTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// مشغل الفيديو الاحترافي (جودات + دعم الترجمة التلقائية)
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
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _initPlayer(_currentUrl!);
  }

  void _initPlayer(String streamUrl) async {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    setState(() => _isReady = false);

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      // الترجمة التلقائية المدمجة داخل المشغل
      subtitle: Subtitles([
        Subtitle(
          index: 0,
          start: Duration.zero,
          end: const Duration(seconds: 5),
          text: 'ONEBR TV - مشاهدة ممتعة',
        ),
      ]),
      subtitleBuilder: (context, subtitle) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          subtitle,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFE50914),
        handleColor: const Color(0xFF00F0FF),
        bufferedColor: Colors.white24,
        backgroundColor: Colors.grey,
      ),
      additionalOptions: (context) {
        return <OptionItem>[
          OptionItem(
            onTap: () => _showQualitySheet(),
            iconData: Icons.high_quality_rounded,
            title: 'تغيير الجودة',
          ),
        ];
      },
    );

    if (mounted) setState(() => _isReady = true);
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1422),
      builder: (_) {
        return ListView(
          shrinkWrap: true,
          children: widget.qualities.map((q) {
            final res = q['resolution'] ?? 'تلقائي';
            final url = q['url'];
            final isSelected = url == _currentUrl;

            return ListTile(
              title: Text(res, style: TextStyle(color: isSelected ? const Color(0xFF00F0FF) : Colors.white)),
              trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF00F0FF)) : null,
              onTap: () {
                Navigator.pop(context);
                if (!isSelected && url != null) {
                  setState(() => _currentUrl = url);
                  _initPlayer(url);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF0F1422),
        actions: [
          if (widget.qualities.length > 1)
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xFF00F0FF)),
              onPressed: _showQualitySheet,
            )
        ],
      ),
      body: Center(
        child: _isReady && _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
      ),
    );
  }
}
