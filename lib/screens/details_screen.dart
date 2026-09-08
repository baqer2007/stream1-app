import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import '../services/download_manager.dart';
import '../player/media_player_screen.dart';

class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _isMatching = true;
  bool _isFav = false;
  Map<String, dynamic>? _matchedCee;
  List<dynamic> _episodes = [];
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media['first_air_date'] != null || widget.media['name'] != null;
    _checkFav();
    _saveContinueWatching();
    _matchServer();
  }

  void _checkFav() async {
    final fav = await StreamService.isFavorited(widget.media['id'].toString());
    if (mounted) setState(() => _isFav = fav);
  }

  void _saveContinueWatching() {
    final p = StorageService.get('active_profile', defaultValue: 'الرئيسي');
    StorageService.appendItem('continue_watching_$p', widget.media);
  }

  Future<void> _matchServer() async {
    final title = (widget.media['name'] ?? widget.media['title'] ?? '').toString();
    try {
      final b64 = base64.encode(utf8.encode(title));
      final lvl = _isSeries ? '1' : '0';
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/30/video_title_search/$b64/itemsPerPage/30/pageNumber/0/level/$lvl'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (decoded is List) ? decoded : (decoded['articles'] ?? []);
        if (list.isNotEmpty) {
          _matchedCee = list.first;
          if (_isSeries) await _loadEpisodes(_matchedCee!['nb'].toString());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isMatching = false);
  }

  Future<void> _loadEpisodes(String parentId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/100/parent_id/$parentId/itemsPerPage/100/pageNumber/0/level/2'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        dynamic d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        setState(() => _episodes = (d is List) ? d : (d['articles'] ?? []));
      }
    } catch (_) {}
  }

  void _play(int index) async {
    if (_matchedCee == null) return;
    String id = _matchedCee!['nb'].toString();
    if (_isSeries && _episodes.isNotEmpty && index < _episodes.length) {
      id = _episodes[index]['nb'].toString();
    }
    final data = await StreamService.getVideoSource(id);
    if (data != null && mounted) {
      StreamService.recordWatchEvent(id, widget.media['title'] ?? widget.media['name'] ?? '');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaPlayerScreen(
            mediaId: id,
            title: '${widget.media['title'] ?? widget.media['name']} - ${index + 1}',
            videoUrl: data['video_url'],
            qualities: List<Map<String, dynamic>>.from(data['qualities'] ?? []),
          ),
        ),
      );
    }
  }

  void _downloadAction() async {
    if (_matchedCee == null) return;
    String id = _matchedCee!['nb'].toString();
    final title = widget.media['title'] ?? widget.media['name'] ?? 'Video';
    final data = await StreamService.getVideoSource(id);
    if (data != null) {
      final qualities = List<Map<String, dynamic>>.from(data['qualities'] ?? []);
      final dlUrl = qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first)['url'];
      DownloadManager.instance.startDownload(
        targetId: id,
        title: title,
        url: dlUrl,
        poster: widget.media['poster_path'] ?? '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بدأ التنزيل...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.media['title'] ?? widget.media['name'] ?? '';
    final poster = widget.media['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.media['poster_path']}' : '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          actions: [
            IconButton(
              icon: Icon(_isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: const Color(0xFFF59E0B)),
              onPressed: () async {
                final state = await StreamService.toggleFavorite(widget.media);
                setState(() => _isFav = state);
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CachedNetworkImage(
                    imageUrl: poster,
                    width: 120,
                    height: 175,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor: Colors.grey.shade900,
                      highlightColor: Colors.grey.shade800,
                      child: Container(width: 120, height: 175, color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text('⭐ ${(widget.media['vote_average'] ?? 8.0).toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_isMatching)
                        const Row(children: [CircularProgressIndicator(strokeWidth: 2), SizedBox(width: 8), Text('جاري الفحص...')])
                      else
                        Text(_matchedCee != null ? '✅ متوفر للمشاهدة' : '❌ غير متوفر بالسيرفر', style: TextStyle(color: _matchedCee != null ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('تنزيل'),
                        onPressed: _matchedCee != null ? _downloadAction : null,
                      )
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _matchedCee != null ? () => _play(0) : null,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: const Text('مشاهدة الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            Text(widget.media['overview'] ?? '', style: const TextStyle(color: Colors.grey, height: 1.5)),
            if (_isSeries && _episodes.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('قائمة الحلقات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_episodes.length, (i) => ActionChip(
                  label: Text('${i + 1}'),
                  onPressed: () => _play(i),
                )),
              )
            ]
          ],
        ),
      ),
    );
  }
}
