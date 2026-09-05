import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class CinemanaPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final String? initialTitle;

  const CinemanaPlayerScreen({
    super.key,
    required this.movieData,
    this.initialTitle,
  });

  @override
  State<CinemanaPlayerScreen> createState() => _CinemanaPlayerScreenState();
}

class _CinemanaPlayerScreenState extends State<CinemanaPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  double _progressValue = 0.0;
  String _statusText = 'جاري بدء الاتصال...';
  String? _movieTitle;
  String? _movieDescription;
  String? _errorMessage;

  StreamSubscription? _streamSub;

  // ضع عنوان IP هاتف Termux الفعلي هنا
  static const String serverBaseUrl = 'http://192.168.1.50:3000';

  @override
  void initState() {
    super.initState();
    _movieTitle = widget.initialTitle ??
        widget.movieData['ar_title'] ??
        widget.movieData['en_title'];
    _movieDescription =
        widget.movieData['ar_content'] ?? widget.movieData['en_content'];
    _listenToLiveProgress();
  }

  Future<void> _listenToLiveProgress() async {
    final postId = (widget.movieData['nb'] ?? widget.movieData['id'] ?? '').toString();
    final title = _movieTitle ?? 'Movie_$postId';

    if (postId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'معرف الفيديو غير صالح.';
      });
      return;
    }

    try {
      final client = http.Client();
      final request = http.Request(
        'GET',
        Uri.parse('$serverBaseUrl/progress?postId=$postId&title=${Uri.encodeComponent(title)}&res=240p'),
      );

      final response = await client.send(request);

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('data: ')) {
          final rawJson = line.substring(6).trim();
          try {
            final data = json.decode(rawJson);

            if (data['status'] == 'uploading' || data['status'] == 'downloading') {
              setState(() {
                _statusText = data['message'] ?? 'جاري التجهيز...';
                if (data['progress'] != null) {
                  _progressValue = (data['progress'] as num).toDouble();
                }
              });
            } else if (data['status'] == 'ready') {
              final String embedUrl = data['embedUrl'];
              final videoId = embedUrl.split('/').last;
              const libraryId = '744597';
              final streamUrl = 'https://video.bunnycdn.com/play/$libraryId/$videoId/playlist.m3u8';
              _streamSub?.cancel();
              _initPlayer(streamUrl);
            } else if (data['status'] == 'error') {
              setState(() {
                _isLoading = false;
                _errorMessage = data['message'];
              });
              _streamSub?.cancel();
            }
          } catch (_) {}
        }
      }, onError: (err) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'خطأ في استقبال البيانات: $err';
        });
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر الاتصال بالسيرفر: $e';
        });
      }
    }
  }

  Future<void> _initPlayer(String streamUrl) async {
    try {
      setState(() {
        _statusText = 'جاري فتح المشغل...';
      });

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
      );

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        fullScreenByDefault: false,
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'فشل المشغل: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: Text(_movieTitle ?? 'مشغل سينمانا'),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: _progressValue > 0 ? _progressValue / 100 : null,
                            strokeWidth: 6,
                            color: Colors.redAccent,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '${_progressValue.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _statusText,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SelectableText(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.black,
                        child: AspectRatio(
                          aspectRatio: _videoPlayerController!.value.isInitialized
                              ? _videoPlayerController!.value.aspectRatio
                              : 16 / 9,
                          child: Chewie(controller: _chewieController!),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _movieTitle ?? 'بدون عنوان',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _movieDescription ?? 'لا يوجد وصف متاح.',
                              style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
