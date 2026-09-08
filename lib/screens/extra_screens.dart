import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/storage_service.dart';
import 'details_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _list = StorageService.getList('favorites_list');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07090E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07090E),
          title: const Text('قائمة المفضلة'),
        ),
        body: _list.isEmpty
            ? const Center(child: Text('لا توجد عناصر في المفضلة', style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                itemCount: _list.length,
                itemBuilder: (ctx, i) {
                  final itm = _list[i];
                  final p = itm['poster_path'] ?? '';
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w185$p',
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(itm['title'] ?? itm['name'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text(itm['release_date'] ?? itm['first_air_date'] ?? '', style: const TextStyle(color: Colors.white54)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(media: itm))),
                  );
                },
              ),
      ),
    );
  }
}

class WatchLaterScreen extends StatefulWidget {
  const WatchLaterScreen({super.key});

  @override
  State<WatchLaterScreen> createState() => _WatchLaterScreenState();
}

class _WatchLaterScreenState extends State<WatchLaterScreen> {
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _list = StorageService.getList('watch_later_list');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07090E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07090E),
          title: const Text('المشاهدة لاحقاً'),
        ),
        body: _list.isEmpty
            ? const Center(child: Text('لا توجد أعمال مضافة للمشاهدة لاحقاً', style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                itemCount: _list.length,
                itemBuilder: (ctx, i) {
                  final itm = _list[i];
                  final p = itm['poster_path'] ?? '';
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w185$p',
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(itm['title'] ?? itm['name'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text(itm['release_date'] ?? itm['first_air_date'] ?? '', style: const TextStyle(color: Colors.white54)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(media: itm))),
                  );
                },
              ),
      ),
    );
  }
}
