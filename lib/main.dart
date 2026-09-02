import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ArchiveStreamApp(),
  ));
}

class ArchiveItem {
  final String identifier;
  final String title;
  final String description;
  final String thumbnail;

  ArchiveItem({
    required this.identifier,
    required this.title,
    required this.description,
    required this.thumbnail,
  });
}

class ArchiveStreamApp extends StatefulWidget {
  const ArchiveStreamApp({super.key});

  @override
  State<ArchiveStreamApp> createState() => _ArchiveStreamAppState();
}

class _ArchiveStreamAppState extends State<ArchiveStreamApp> {
  final TextEditingController _searchCtrl = TextEditingController(text: "One Piece");
  List<ArchiveItem> _items = [];
  bool _loading = false;
  String _status = "الأرشيف الرقمي المفتوح للبث المباشر (بدون حظر)";

  @override
  void initState() {
    super.initState();
    _searchArchive("One Piece");
  }

  Future<void> _searchArchive(String query) async {
    final term = query.trim();
    if (term.isEmpty) return;

    setState(() {
      _loading = true;
      _status = "🔍 جاري البحث في خوادم الأرشيف المفتوحة...";
      _items.clear();
    });

    try {
      // البحث في وسائط الفيديو فقط داخل الأرشيف
      final encoded = Uri.encodeComponent(term);
      final searchUrl = Uri.parse(
        "https://archive.org/advancedsearch.php?q=$encoded+AND+mediatype:movies&fl[]=identifier,title,description&sort[]=&rows=15&page=1&output=json"
      );

      final res = await http.get(searchUrl).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['response']?['docs'] as List?;
        if (docs != null && docs.isNotEmpty) {
          final List<ArchiveItem> found = [];
          for (var doc in docs) {
            final id = doc['identifier'] ?? '';
            if (id.isNotEmpty) {
              found.add(ArchiveItem(
                identifier: id,
                title: doc['title'] ?? id,
                description: doc['description'] ?? 'محتوى فيديو من الأرشيف الرقمي',
                thumbnail: "https://archive.org/services/img/$id",
              ));
            }
          }

          setState(() {
            _items = found;
            _loading = false;
            _status = "تم العثور على ${found.length} عمل متاح للبث المباشر";
          });
          return;
        }
      }
    } catch (e) {
      // في حال وجود مشكلة بالشبكة
    }

    setState(() {
      _loading = false;
      _status = "لم نجد نتائج مطابقة، جرب كتابة الاسم بوضوح (مثال: One Piece)";
    });
  }

  void _openDetails(ArchiveItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FileSelectorScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(
        title: const Text("البث الأرشيفي المباشر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF141824),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "ابحث عن أي أنمي أو فيلم (One Piece, Conan, Naruto)...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1A1F2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: _searchArchive,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                  onPressed: () => _searchArchive(_searchCtrl.text),
                )
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: Color(0xFF45F3FF)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      _loading ? "جاري الفحص..." : "ابحث عن عنوان للبدء",
                      style: const TextStyle(color: Colors.white24),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return GestureDetector(
                        onTap: () => _openDetails(item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF151926),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                  child: Image.network(
                                    item.thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.video_library, size: 45, color: Colors.white24),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
      ),
    );
  }
}

class FileSelectorScreen extends StatefulWidget {
  final ArchiveItem item;
  const FileSelectorScreen({super.key, required this.item});

  @override
  State<FileSelectorScreen> createState() => _FileSelectorScreenState();
}

class _FileSelectorScreenState extends State<FileSelectorScreen> {
  List<Map<String, String>> _videoFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDirectVideoFiles();
  }

  // استخراج ملفات الفيديو الحقيقية (MP4) من metadata العنصر
  Future<void> _fetchDirectVideoFiles() async {
    try {
      final url = Uri.parse("https://archive.org/metadata/${widget.item.identifier}");
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final files = data['files'] as List?;
        if (files != null) {
          final List<Map<String, String>> found = [];
          for (var f in files) {
            final name = f['name']?.toString() ?? '';
            final format = (f['format']?.toString() ?? '').toLowerCase();

            // تصفية ملفات الفيديو الحقيقية القابلة للتشغيل المباشر
            if (name.endsWith('.mp4') || format.contains('h.264') || format.contains('mp4')) {
              final directUrl = "https://archive.org/download/${widget.item.identifier}/$name";
              final size = f['size'] != null ? "${(int.parse(f['size'].toString()) / (1024 * 1024)).toStringAsFixed(1)} MB" : "Direct Stream";
              found.add({
                "name": name,
                "url": directUrl,
                "size": size,
              });
            }
          }

          if (found.isNotEmpty) {
            setState(() {
              _videoFiles = found;
              _loading = false;
            });
            return;
          }
        }
      }
    } catch (_) {}

    setState(() {
      _loading = false;
    });
  }

  void _playVideo(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NativePlayerScreen(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(title: Text(widget.item.title, maxLines: 1), backgroundColor: const Color(0xFF141824)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF)))
          : (_videoFiles.isEmpty
              ? const Center(child: Text("لم نجد ملفات MP4 مباشرة لهذا العنصر، اختر عنصراً آخر.", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _videoFiles.length,
                  itemBuilder: (context, index) {
                    final f = _videoFiles[index];
                    return Card(
                      color: const Color(0xFF161A26),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_filled, color: Color(0xFF45F3FF), size: 34),
                        title: Text(f["name"]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text("الحجم: ${f["size"]}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF), foregroundColor: Colors.black),
                          onPressed: () => _playVideo(f["url"]!, f["name"]!),
                          child: const Text("تشغيل"),
                        ),
                      ),
                    );
                  },
                )),
    );
  }
}

class NativePlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const NativePlayerScreen({super.key, required this.url, required this.title});

  @override
  State<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends State<NativePlayerScreen> {
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _videoCtrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await _videoCtrl!.initialize();

      _chewieCtrl = ChewieController(
        videoPlayerController: _videoCtrl!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoCtrl!.value.aspectRatio > 0 ? _videoCtrl!.value.aspectRatio : 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
      );
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 13)), backgroundColor: Colors.transparent),
      body: Center(
        child: _error != null
            ? Text("خطأ في تشغيل الفيديو: $_error", style: const TextStyle(color: Colors.redAccent))
            : (_chewieCtrl != null && _videoCtrl!.value.isInitialized
                ? Chewie(controller: _chewieCtrl!)
                : const CircularProgressIndicator(color: Color(0xFF45F3FF))),
      ),
    );
  }
}
