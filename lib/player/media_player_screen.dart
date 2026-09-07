import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  SubtitleCue({required this.start, required this.end, required this.text});
}

class MediaPlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<Map<String, dynamic>> qualities;
  final VoidCallback? onNextEpisode;
  final bool isLocalFile;

  const MediaPlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    required this.qualities,
    this.onNextEpisode,
    this.isLocalFile = false,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  bool _isLocked = false;
  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18.0;
  Color _subtitleColor = Colors.white;
  double _subtitleOffset = 0.0;
  List<SubtitleCue> _subtitles = [];
  String _activeSub = '';

  String _currentUrl = '';
  String _activeQuality = 'تلقائي (Auto)';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _initEngine();
    if (!widget.isLocalFile) _loadSubtitles();
  }

  void _initEngine() async {
    await _player.open(
      Media(_currentUrl, httpHeaders: StreamService.stealthHeaders),
      play: true,
    );

    final resume = StorageService.get('resume_${widget.mediaId}', defaultValue: 0);
    if (resume > 5) {
      await _player.seek(Duration(seconds: resume));
    }

    _player.stream.position.listen((pos) {
      if (mounted) {
        _syncSubtitles(pos);
        if (pos.inSeconds % 5 == 0) {
          StorageService.put('resume_${widget.mediaId}', pos.inSeconds);
        }
      }
    });
  }

  void _loadSubtitles() async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/${widget.mediaId}'),
        headers: StreamService.stealthHeaders,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final subPath = data['arTranslationFilePath'] ?? data['arTranslationFile'] ?? '';
        if (subPath.isNotEmpty) {
          final subRes = await http.get(Uri.parse(subPath));
          if (subRes.statusCode == 200 && mounted) {
            _parseSrt(utf8.decode(subRes.bodyBytes, allowMalformed: true));
          }
        }
      }
    } catch (_) {}
  }

  void _parseSrt(String srt) {
    final matches = RegExp(r'(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\r?\n([\s\S]*?)(?=\n\n|\r\n\r\n|$)').allMatches(srt);
    final List<SubtitleCue> list = [];
    for (var m in matches) {
      list.add(SubtitleCue(
        start: _toDuration(m.group(1)!),
        end: _toDuration(m.group(2)!),
        text: m.group(3)!.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      ));
    }
    setState(() => _subtitles = list);
  }

  Duration _toDuration(String s) {
    final p = s.replaceAll(',', '.').split(':');
    final sec = p[2].split('.');
    return Duration(
      hours: int.parse(p[0]),
      minutes: int.parse(p[1]),
      seconds: int.parse(sec[0]),
      milliseconds: int.parse(sec[1].padRight(3, '0').substring(0, 3)),
    );
  }

  void _syncSubtitles(Duration pos) {
    if (!_subtitlesEnabled || _subtitles.isEmpty) {
      if (_activeSub.isNotEmpty) setState(() => _activeSub = '');
      return;
    }
    final adjusted = pos + Duration(milliseconds: (_subtitleOffset * 1000).round());
    int low = 0, high = _subtitles.length - 1;
    String matched = '';
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      if (adjusted < _subtitles[mid].start) {
        high = mid - 1;
      } else if (adjusted > _subtitles[mid].end) {
        low = mid + 1;
      } else {
        matched = _subtitles[mid].text;
        break;
      }
    }
    if (_activeSub != matched) setState(() => _activeSub = matched);
  }

  void _changeQuality(String url, String name) async {
    final pos = _player.state.position;
    setState(() {
      _currentUrl = url;
      _activeQuality = name;
    });
    await _player.open(Media(url, httpHeaders: StreamService.stealthHeaders));
    await _player.seek(pos);
  }

  @override
  void dispose() {
    _player.dispose();
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
              child: Video(
                controller: _controller,
                controls: (state) => const SizedBox.shrink(),
              ),
            ),
            if (_subtitlesEnabled && _activeSub.isNotEmpty)
              Positioned(
                bottom: 80,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      _activeSub,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _subtitleColor, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            if (!_isLocked) ...[
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.high_quality_rounded, color: Color(0xFF00F0FF)),
                          onPressed: () => _openQualityPicker(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
                          onPressed: () => _openSubConfig(),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                          onPressed: () => setState(() => _isLocked = true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ] else ...[
              Positioned(
                top: 16,
                right: 16,
                child: FloatingActionButton.small(
                  backgroundColor: const Color(0xFFE50914),
                  child: const Icon(Icons.lock_rounded, color: Colors.white),
                  onPressed: () => setState(() => _isLocked = false),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _openQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.qualities.map((q) => ListTile(
            title: Text(q['resolution'] ?? 'HD', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: _activeQuality == q['resolution'] ? const Icon(Icons.check, color: Color(0xFF00F0FF)) : null,
            onTap: () {
              Navigator.pop(context);
              _changeQuality(q['url'], q['resolution']);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _openSubConfig() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBtm) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('تشغيل الترجمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                value: _subtitlesEnabled,
                onChanged: (v) {
                  setBtm(() => _subtitlesEnabled = v);
                  setState(() => _subtitlesEnabled = v);
                },
              ),
              Slider(
                value: _subtitleOffset, min: -5.0, max: 5.0, divisions: 20,
                activeColor: const Color(0xFF00F0FF),
                onChanged: (v) {
                  setBtm(() => _subtitleOffset = v);
                  setState(() => _subtitleOffset = v);
                },
              ),
              Text('المزامنة: ${_subtitleOffset.toStringAsFixed(1)} ثانية', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
