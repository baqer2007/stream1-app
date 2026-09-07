import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class ActiveDownload {
  final String id;
  final String title;
  final String url;
  final String poster;
  double progress;
  http.Client? client;
  StreamSubscription<List<int>>? subscription;
  IOSink? fileSink;
  bool isCancelled = false;

  ActiveDownload({
    required this.id,
    required this.title,
    required this.url,
    required this.poster,
    this.progress = 0.0,
  });
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final Map<String, ActiveDownload> activeDownloads = {};

  Future<String> _getSafeStorageDir() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final savePath = Directory('${dir.path}/ONEBR_Downloads');
    if (!await savePath.exists()) {
      await savePath.create(recursive: true);
    }
    return savePath.path;
  }

  Future<void> startDownload({
    required String targetId,
    required String title,
    required String url,
    required String poster,
  }) async {
    if (activeDownloads.containsKey(targetId)) return;

    final download = ActiveDownload(id: targetId, title: title, url: url, poster: poster);
    activeDownloads[targetId] = download;
    notifyListeners();

    try {
      final basePath = await _getSafeStorageDir();
      final safeName = targetId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final filePath = '$basePath/$safeName.mp4';
      final file = File(filePath);

      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      final client = http.Client();
      download.client = client;

      final request = http.Request('GET', Uri.parse(url));
      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      final response = await client.send(request);
      final totalBytes = (response.contentLength ?? 0) + downloadedBytes;

      final sink = file.openWrite(mode: FileMode.append);
      download.fileSink = sink;

      final completer = Completer<void>();

      download.subscription = response.stream.listen(
        (chunk) {
          if (download.isCancelled) return;
          downloadedBytes += chunk.length;
          sink.add(chunk);
          if (totalBytes > 0) {
            download.progress = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
            notifyListeners();
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          completer.complete();
        },
        onError: (e) async {
          await sink.close();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;

      if (!download.isCancelled) {
        final fileSizeMb = ((await file.length()) / (1024 * 1024)).toStringAsFixed(1);
        await StorageService.appendItem('downloaded_works_list', {
          'id': targetId,
          'title': title,
          'path': filePath,
          'size': '$fileSizeMb MB',
          'poster': poster,
        });
      }
    } catch (_) {}

    activeDownloads.remove(targetId);
    notifyListeners();
  }

  void cancelDownload(String targetId) {
    if (activeDownloads.containsKey(targetId)) {
      final d = activeDownloads[targetId]!;
      d.isCancelled = true;
      d.subscription?.cancel();
      d.fileSink?.close();
      d.client?.close();
      activeDownloads.remove(targetId);
      notifyListeners();
    }
  }
}
