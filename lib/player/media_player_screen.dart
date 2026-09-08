import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String videoUrl;
  final List<dynamic> qualities;
  final bool isLocalFile;

  const MediaPlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.videoUrl,
    this.qualities = const [],
    this.isLocalFile = false,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final Player player;
  late final VideoController controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;

  // إعدادات الترجمة
  double _subSize = 18.0;
  Color _subTextColor = Colors.white;
  Color _subBgColor = Colors.transparent;

  // الوضع العائلي وحجب اللقطات
  bool _familyMode = false;
  bool _skipSensitive = false;

  final List<Map<String, dynamic>> _colorOptions = [
    {'name': 'أبيض', 'color': Colors.white},
    {'name': 'أصفر', 'color': Colors.yellowAccent},
    {'name': 'أخضر', 'color': Colors.greenAccent},
    {'name': 'سماوي', 'color': Colors.cyanAccent},
  ];

  final List<Map<String, dynamic>> _bgOptions = [
    {'name': 'شفاف', 'color': Colors.transparent},
    {'name': 'أسود نصف شفاف', 'color': Colors.black54},
    {'name': 'أسود معتم', 'color': Colors.black},
    {'name': 'رمادي داكن', 'color': const Color(0xFF1E1E1E)},
  ];

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _loadPreferences();
    _initPlayer();
  }

  void _loadPreferences() {
    _familyMode = StorageService.get('family_mode', defaultValue: false);
    _skipSensitive = StorageService.get('skip_sensitive', defaultValue: false);
    _subSize = StorageService.get('sub_size', defaultValue: 18.0);
    int txtVal = StorageService.get('sub_txt_color', defaultValue: Colors.white.value);
    int bgVal = StorageService.get('sub_bg_color', defaultValue: Colors.transparent.value);
    _subTextColor = Color(txtVal);
    _subBgColor = Color(bgVal);
  }

  Future<void> _initPlayer() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'رابط التشغيل غير متاح حالياً';
      });
      return;
    }

    try {
      await player.open(Media(url));
      StreamService.recordWatchHistory(widget.mediaId, widget.title);
      _startHideTimer();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر تشغيل الفيديو: $e';
        });
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111726),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('إعدادات المشغل والترجمة', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white12),

                      SwitchListTile(
                        title: const Text('الوضع العائلي', style: TextStyle(color: Colors.white)),
                        subtitle: const Text('كتم وحجب المشاهد غير اللائقة تلقائياً', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _familyMode,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          setSheetState(() => _familyMode = val);
                          setState(() => _familyMode = val);
                          StorageService.put('family_mode', val);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('تخطي اللقطات الحساسة', style: TextStyle(color: Colors.white)),
                        subtitle: const Text('القفز التلقائي عن المشاهد التي تم الإبلاغ عنها', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _skipSensitive,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          setSheetState(() => _skipSensitive = val);
                          setState(() => _skipSensitive = val);
                          StorageService.put('skip_sensitive', val);
                        },
                      ),

                      const SizedBox(height: 12),
                      Text('حجم خط الترجمة: ${_subSize.toInt()}px', style: const TextStyle(color: Colors.white70)),
                      Slider(
                        value: _subSize,
                        min: 14.0,
                        max: 32.0,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          setSheetState(() => _subSize = val);
                          setState(() => _subSize = val);
                          StorageService.put('sub_size', val);
                        },
                      ),

                      const SizedBox(height: 8),
                      const Text('لون الخط:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: _colorOptions.map((opt) {
                          final isSel = _subTextColor == opt['color'];
                          return ChoiceChip(
                            label: Text(opt['name']),
                            selected: isSel,
                            selectedColor: const Color(0xFFE50914),
                            onSelected: (_) {
                              setSheetState(() => _subTextColor = opt['color']);
                              setState(() => _subTextColor = opt['color']);
                              StorageService.put('sub_txt_color', (opt['color'] as Color).value);
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),
                      const Text('لون خلفية الخط:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: _bgOptions.map((opt) {
                          final isSel = _subBgColor == opt['color'];
                          return ChoiceChip(
                            label: Text(opt['name']),
                            selected: isSel,
                            selectedColor: const Color(0xFFE50914),
                            onSelected: (_) {
                              setSheetState(() => _subBgColor = opt['color']);
                              setState(() => _subBgColor = opt['color']);
                              StorageService.put('sub_bg_color', (opt['color'] as Color).value);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            Center(
              child: _errorMessage != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 52),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Video(controller: controller),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            if (_showControls)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  color: Colors.black38,
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_familyMode)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.greenAccent),
                                  ),
                                  child: const Text('عائلي', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                ),
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                                onPressed: _openSettingsDialog,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _subBgColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'معاينة الترجمة التجريبية',
                              style: TextStyle(
                                fontSize: _subSize,
                                color: _subTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
