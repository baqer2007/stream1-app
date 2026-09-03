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
  List _items = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  // جلب أحدث الأفلام أو البحث
  Future<void> _loadItems([String query = '']) async {
    setState(() => _isLoading = true);
    
    // API سينمانا لجلب أحدث الأفلام أو نتائج البحث
    final String endpoint = query.isEmpty
        ? 'https://cinemana.shabakaty.com/api/android/allVideo/page/0/level/0'
        : 'https://cinemana.shabakaty.com/api/android/videoSearch/page/0/title/${Uri.encodeComponent(query)}';

    try {
      final res = await http.get(Uri.parse(endpoint), headers: {
        'User-Agent': 'Cinemana/3.0.0 (Android)',
        'Accept': 'application/json',
      });

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _items = data is List ? data : (data['items'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Fetch items error: $e');
    }

    setState(() => _isLoading = false);
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
              onSubmitted: (val) => _loadItems(val),
              decoration: InputDecoration(
                hintText: 'ابحث عن فيلم أو مسلسل...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.redAccent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    _searchController.clear();
                    _loadItems();
                  },
                ),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // شبكة عرض الأفلام
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'لم يتم العثور على محتوى',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final title = item['ar_title'] ?? item['en_title'] ?? '';
                          final posterUrl = item['imgMediumThumbObjUrl'] ?? item['imgThumbObjUrl'] ?? '';
                          final videoId = item['nb']?.toString() ?? '';

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CinemanaPlayerScreen(
                                    videoId: videoId,
                                    initialTitle: title,
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  posterUrl.isNotEmpty
                                      ? Image.network(
                                          posterUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Colors.grey[800],
                                            child: const Icon(Icons.movie, color: Colors.white54),
                                          ),
                                        )
                                      : Container(color: Colors.grey[800]),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.transparent, Colors.black87],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
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
