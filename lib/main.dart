import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CinemanaProxyTestApp(),
  ));
}

class CinemanaProxyTestApp extends StatefulWidget {
  const CinemanaProxyTestApp({super.key});

  @override
  State<CinemanaProxyTestApp> createState() => _CinemanaProxyTestAppState();
}

class _CinemanaProxyTestAppState extends State<CinemanaProxyTestApp> {
  final TextEditingController _searchCtrl = TextEditingController(text: "One Piece");
  List<dynamic> _results = [];
  bool _loading = false;
  String _status = "جاهز لاختبار نفق سينمانا";

  // دالة مخصصة ترسل الطلب عبر وسيط البروكسي
  Future<String> _fetchViaProxy(Uri uri, {Map<String, String>? postData}) async {
    final client = HttpClient();
    
    // توجيه الطلب عبر البروكسي الوسيط
    client.findProxy = (url) {
      // تجربة التوجيه المباشر لسيرفر النفق
      return "PROXY 164.92.236.137:443; SOCKS5 164.92.236.137:443; DIRECT";
    };
    
    // تجاوز فحص الشهادات للأنفاق المخصصة
    client.badCertificateCallback = (cert, host, port) => true;

    HttpClientRequest request;
    if (postData != null) {
      request = await client.postUrl(uri);
      request.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');
      request.headers.set('User-Agent', 'okhttp/4.9.0');
      final bodyStr = postData.entries.map((e) => "${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}").join('&');
      request.write(bodyStr);
    } else {
      request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'okhttp/4.9.0');
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final responseBody = await response.transform(utf8.decoder).join();
    return responseBody;
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _status = "جاري الاتصال بسيرفر النفق...";
      _results.clear();
    });

    try {
      final res = await _fetchViaProxy(
        Uri.parse("https://cinemana.shabakkat.cc/api/android/allVideo/search"),
        postData: {'query': query.trim()},
      );

      final List data = json.decode(res);
      setState(() {
        _results = data;
        _loading = false;
        _status = "نجح الاتصال! تم جلب ${data.length} عمل عبر النفق.";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = "فشل الاتصال: $e\n(قد يتطلب البروكسي مصادقة VLESS/UUID)";
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _search("One Piece");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(
        title: const Text("اختبار نفق سينمانا المباشر", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF141724),
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
                      hintText: "اكتب اسم فيلم للبحث...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF181C2B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onSubmitted: _search,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF45F3FF)),
                  onPressed: () => _search(_searchCtrl.text),
                )
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: Color(0xFF45F3FF), backgroundColor: Colors.transparent),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: const TextStyle(color: Colors.amber, fontSize: 12), textAlign: TextAlign.center),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final item = _results[i];
                return ListTile(
                  leading: item['mediumPoster'] != null
                      ? Image.network(item['mediumPoster'], width: 45, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: Colors.white24))
                      : const Icon(Icons.movie, color: Colors.white24),
                  title: Text(item['title'] ?? '', style: const TextStyle(color: Colors.white)),
                  subtitle: Text("السنة: ${item['year'] ?? ''} | النوع: ${item['kind'] ?? ''}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
