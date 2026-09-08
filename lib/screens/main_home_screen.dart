import 'dart:convert';
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
  final ScrollController _scroll = ScrollController();
  List<dynamic> _trending = [];
  List<dynamic> _gridItems = [];
  int _page = 1;
  bool _loading = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 && !_loading && _hasMore) {
        _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await StreamService.fetchTmdb('trending/all/week?language=ar&page=$_page');
      if (res != null && res.statusCode == 200) {
        final list = jsonDecode(res.body)['results'] ?? [];
        setState(() {
          if (_page == 1) {
            _trending = list.take(6).toList();
            _gridItems = list;
          } else {
            _gridItems.addAll(list);
          }
          _page++;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ONEBR TV', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, color: Color(0xFFF59E0B)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
            ),
          ],
        ),
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            if (_trending.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: PageView.builder(
                    itemCount: _trending.length,
                    itemBuilder: (ctx, i) {
                      final itm = _trending[i];
                      final b = itm['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${itm['backdrop_path']}' : '';
                      return InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: itm))),
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedNetworkImage(imageUrl: b, fit: BoxFit.cover),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Text('🔥 الأكثر تداولاً هذا الأسبوع', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final itm = _gridItems[i];
                    final p = itm['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${itm['poster_path']}' : '';
                    return InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: itm))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: p,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade900,
                            highlightColor: Colors.grey.shade800,
                            child: Container(color: Colors.black),
                          ),
                        ),
                      );
                    },
                  ),
                  childCount: _gridItems.length,
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))),
              )
          ],
        ),
      ),
    );
  }
}
