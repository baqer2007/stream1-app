import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  String _statusMessage = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMovies();
  }

  // دالة موحدة لجلب أحدث الأفلام أو تنفيذ البحث
  Future<void> _fetchMovies([String query = '']) async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    // رابط أحدث الأعمال أو رابط البحث الرسمي في تطبيق سينمانا
    final String url = query.trim().isEmpty
        ? 'https://cinemana.shabakaty.com/api/android/allVideo/page/0/level/0'
        : 'https://cinemana.shabakaty.com/api/android/videoSearch/title/${Uri.encodeComponent(query.trim())}';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Cinemana/3.0.0 (Android)',
          'Accept': 'application/json',
          'Referer': 'https://cinemana.shabakaty.com/',
        },
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        List<dynamic> resultList = [];
        if (decoded is List) {
          resultList = decoded;
        } else if (decoded is Map) {
          if (decoded['items'] is List) {
            resultList = decoded['items'];
          } else if (decoded['videos'] is List) {
            resultList = decoded['videos'];
          } else if (decoded['data'] is List) {
            resultList = decoded['data'];
          }
        }

        setState(() {
          _items = resultList;
          if (_items.isEmpty) {
            _statusMessage = 'لم يتم العثور على نتائج.';
          }
        });
      } else {
        setState(() {
          _statusMessage = 'فشل الاتصال بالخادم (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في جلب البيانات: تأكد من اتصالك بشبكة تدعم سينمانا.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('أفلام سينمانا', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _fetchMovies(value),
              decoration: InputDecoration(
                hintText: 'ابحث عن فيلم أو مسلسل واضغط بحث...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.redAccent),
                  onPressed: () => _fetchMovies(_searchController.text),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _fetchMovies();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // شبكة الأفلام
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            _statusMessage.isEmpty ? 'لا توجد بيانات متاحة' : _statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchMovies(_searchController.text),
                        child: GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final title = item['ar_title'] ?? item['en_title'] ?? 'بدون عنوان';
                            final poster = item['imgMediumThumbObjUrl'] ??
                                item['imgThumbObjUrl'] ??
                                item['imgObjUrl'] ??
                                '';
                            final videoId = (item['nb'] ?? item['id'] ?? '').toString();

                            return GestureDetector(
                              onTap: () {
                                if (videoId.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CinemanaPlayerScreen(
                                        videoId: videoId,
                                        initialTitle: title,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  color: const Color(0xFF1E293B),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (poster.isNotEmpty)
                                        Image.network(
                                          poster,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(Icons.movie, color: Colors.white24, size: 40),
                                          ),
                                        )
                                      else
                                        const Center(
                                          child: Icon(Icons.movie, color: Colors.white24, size: 40),
                                        ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.transparent, Colors.black],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                          ),
                                          child: Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
