import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/stream_service.dart';
import '../player/media_player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final dynamic media;
  const DetailsScreen({super.key, required this.media});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool _isFavorite = false;
  bool _isWatchLater = false;
  bool _isLoadingStream = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() {
    final id = widget.media['id'].toString();
    setState(() {
      _isFavorite = StreamService.isFavorite(id);
      _isWatchLater = StreamService.isWatchLater(id);
    });
  }

  void _toggleFavorite() {
    final id = widget.media['id'].toString();
    StreamService.toggleFavorite(id, widget.media);
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFavorite ? 'تمت الإضافة إلى المفضلة' : 'تمت الإزالة من المفضلة'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleWatchLater() {
    final id = widget.media['id'].toString();
    StreamService.toggleWatchLater(id, widget.media);
    setState(() => _isWatchLater = !_isWatchLater);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isWatchLater ? 'تمت الإضافة إلى المشاهدة لاحقاً' : 'تمت الإزالة من المشاهدة لاحقاً'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _playMedia() async {
    setState(() => _isLoadingStream = true);
    final id = widget.media['id'].toString();
    final type = widget.media['media_type'] ?? (widget.media['title'] != null ? 'movie' : 'tv');

    final streamData = await StreamService.getStream(id, type: type);
    setState(() => _isLoadingStream = false);

    if (!mounted) return;

    final url = streamData['video_url'] ?? '';
    final title = widget.media['title'] ?? widget.media['name'] ?? 'تشغيل';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(
          mediaId: id,
          title: title,
          videoUrl: url,
          qualities: streamData['qualities'] ?? [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final overview = widget.media['overview'] ?? 'لا يوجد وصف متوفر لهذا العمل حالياً.';
    final backdrop = widget.media['backdrop_path'] ?? widget.media['poster_path'] ?? '';
    final vote = (widget.media['vote_average'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    final releaseDate = widget.media['release_date'] ?? widget.media['first_air_date'] ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07090E),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: const Color(0xFF07090E),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w780$backdrop',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF111726)),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xFF07090E)],
                        ),
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
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text(vote, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                        Text(releaseDate, style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _isLoadingStream ? null : _playMedia,
                            icon: _isLoadingStream
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.play_arrow, color: Colors.white),
                            label: const Text('تشغيل الآن', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? Colors.redAccent : Colors.white70),
                          onPressed: _toggleFavorite,
                        ),
                        IconButton(
                          icon: Icon(_isWatchLater ? Icons.bookmark : Icons.bookmark_border, color: _isWatchLater ? Colors.amber : Colors.white70),
                          onPressed: _toggleWatchLater,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('قصة العمل', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      overview,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
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
