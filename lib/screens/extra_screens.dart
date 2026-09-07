import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import '../services/download_manager.dart';
import '../player/media_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    final list = StorageService.getList('downloaded_works_list');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التنزيلات')),
        body: ListView.builder(
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final itm = list[i];
            return ListTile(
              leading: const Icon(Icons.download_done, color: Colors.green),
              title: Text(itm['title'] ?? ''),
              subtitle: Text(itm['size'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  final f = File(itm['path'] ?? '');
                  if (f.existsSync()) f.deleteSync();
                  StorageService.removeItem('downloaded_works_list', itm['id']);
                  setState(() {});
                },
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaPlayerScreen(
                    mediaId: itm['id'],
                    title: itm['title'],
                    videoUrl: itm['path'],
                    qualities: const [],
                    isLocalFile: true,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = StorageService.get('active_profile', defaultValue: 'الرئيسي');
    final list = StorageService.getList('favorites_list_$p');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المفضلة')),
        body: list.isEmpty
            ? const Center(child: Text('لا توجد عناصر بالمفضلة'))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(list[i]['title'] ?? list[i]['name'] ?? ''),
                  leading: const Icon(Icons.star, color: Colors.amber),
                ),
              ),
      ),
    );
  }
}
