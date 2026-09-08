import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/stream_service.dart';
import 'details_screen.dart';
import 'extra_screens.dart';

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _breaking = [];
  List<dynamic> _gridItems = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasError = false;
  String _selectedCategory = 'all';

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'الكل'},
    {'id': 'movie', 'label': 'أفلام'},
    {'id': 'tv', 'label': 'مسلسلات'},
    {'id': 'top_rated', 'label': 'الأعلى تقييماً'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400 && !_isLoading) {
        _fetchData();
      }
    });
  }

  String _buildEndpoint() {
    if (_selectedCategory == 'movie') return '/discover/movie?sort_by=popularity.desc&page=$_page';
    if (_selectedCategory == 'tv') return '/discover/tv?sort_by=popularity.desc&page=$_page';
    if (_selectedCategory == 'top_rated') return '/movie/top_rated?page=$_page';
    return '/trending/all/day?page=$_page';
  }

  Future<void> _fetchData() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final endpoint = _buildEndpoint();
      final res = await StreamService.fetchTmdb(endpoint);
      if (res != null && res['results'] != null) {
        final list = (res['results'] as List<dynamic>)
            .where((e) => (e['poster_path'] != null || e['backdrop_path'] != null))
            .toList();

        if (mounted) {
          setState(() {
            if (_page == 1) {
              _breaking = list.take(5).toList();
              _gridItems = list.skip(5).toList();
            } else {
              _gridItems.addAll(list);
            }
            _page++;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (_gridItems.isEmpty && _breaking.isEmpty) {
          _hasError = true;
        }
      });
    }
  }

  void _onCategorySelected(String id) {
    if (_selectedCategory == id) return;
    setState(() {
      _selectedCategory = id;
      _page = 1;
      _gridItems.clear();
      _breaking.clear();
    });
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07090E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07090E),
          elevation: 0,
          title: const Text(
            'ONEBR TV',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFE50914)),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Colors.white70),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchLaterScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_rounded, color: Colors.white70),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: const Color(0xFFE50914),
          backgroundColor: const Color(0xFF111726),
          onRefresh: () async {
            setState(() {
              _page = 1;
              _gridItems.clear();
              _breaking.clear();
            });
            await _fetchData();
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _categories.length,
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      final isSel = _selectedCategory == cat['id'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(cat['label']!),
                          selected: isSel,
                          selectedColor: const Color(0xFFE50914),
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.white70),
                          backgroundColor: const Color(0xFF161B26),
                          onSelected: (_) => _onCategorySelected(cat['id']!),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 64),
                        const SizedBox(height: 12),
                        const Text('تعذر تحميل المحتوى، تحقق من الاتصال', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                          onPressed: _fetchData,
                          child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                if (_breaking.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 220,
                      child: PageView.builder(
                        itemCount: _breaking.length,
                        itemBuilder: (ctx, i) {
                          final itm = _breaking[i];
                          final poster = itm['backdrop_path'] ?? itm['poster_path'] ?? '';
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(media: itm))),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                image: DecorationImage(
                                  image: CachedNetworkImageProvider('https://image.tmdb.org/t/p/w780$poster'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                                  ),
                                ),
                                alignment: Alignment.bottomRight,
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  itm['title'] ?? itm['name'] ?? '',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final itm = _gridItems[i];
                        final p = itm['poster_path'] ?? '';
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(media: itm))),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: 'https://image.tmdb.org/t/p/w500$p',
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Shimmer.fromColors(
                                baseColor: const Color(0xFF161B26),
                                highlightColor: const Color(0xFF222B3D),
                                child: Container(color: const Color(0xFF161B26)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF161B26),
                                child: const Icon(Icons.movie, color: Colors.white24),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _gridItems.length,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
