import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cloud_firestore/cloud_firestore.dart' if (dart.library.io) 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/return_code.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'stream_service.dart';

class SecureHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 15);
    client.findProxy = (uri) => 'DIRECT';
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (kReleaseMode) return false;
      return true;
    };
    return client;
  }
}

class RemoteAdminConfig {
  static final RemoteAdminConfig instance = RemoteAdminConfig._();
  RemoteAdminConfig._();

  bool isMaintenance = false;
  String maintenanceMsg = 'التطبيق في وضع الصيانة المجدولة حالياً، يرجى المحاولة لاحقاً 🛠️';
  String globalAlert = '';
  bool globalCensorEnabled = true;
  bool allowDownloads = true;
  String defaultGlobalQuality = '360p';
  int minAppVersion = 1;
  String updateDownloadUrl = '';
  String customBaseUrl = '';
  List<String> pinnedHeroIds = [];
  List<String> blacklistedMediaIds = [];
  String popupTitle = '';
  String popupBody = '';
  String popupActionUrl = '';

  // Remote feature flags / official links / live channels.
  Map<String, bool> featureFlags = {
    'clip_share': true,
    'external_subtitles': true,
    'social_links': true,
    'content_requests': true,
    'subtitle_manager': true,
    'device_ban': true,
    'iptv_manager': true,
  };
  Map<String, String> socialLinks = {};
  List<Map<String, dynamic>> iptvChannels = [];

  bool isFeatureEnabled(String key) => featureFlags[key] ?? true;

  static const List<String> authorizedAdminEmails = [
    'admin@onebr.tv',
    'baqer@onebr.tv',
    'baqer2007@gmail.com',
  ];

  static bool isEmailAdmin(String? email) {
    if (email == null) return false;
    return authorizedAdminEmails.any((e) => e.toLowerCase() == email.trim().toLowerCase());
  }

  void listenToSettings(VoidCallback onUpdate) {
    try {
      FirebaseFirestore.instance.collection('app_config').doc('global_settings').snapshots().listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          isMaintenance = data['is_maintenance'] ?? false;
          maintenanceMsg = data['maintenance_msg'] ?? maintenanceMsg;
          globalAlert = data['global_alert'] ?? '';
          globalCensorEnabled = data['censor_enabled'] ?? true;
          allowDownloads = data['allow_downloads'] ?? true;
          defaultGlobalQuality = data['default_quality'] ?? '360p';
          minAppVersion = data['min_version'] ?? 1;
          updateDownloadUrl = data['update_url'] ?? '';
          customBaseUrl = data['custom_base_url'] ?? '';
          popupTitle = data['popup_title'] ?? '';
          popupBody = data['popup_body'] ?? '';
          popupActionUrl = data['popup_action_url'] ?? '';

          if (data['pinned_hero_ids'] is List) {
            pinnedHeroIds = List<String>.from(data['pinned_hero_ids']);
          }
          if (data['blacklisted_ids'] is List) {
            blacklistedMediaIds = List<String>.from(data['blacklisted_ids']);
          }

          onUpdate();
        }
      }, onError: (_) {});
    } catch (_) {}
  }
}

class SearchEngineUtils {
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\-_:,\.\(\)\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isMatch(String query, String target) {
    final q = normalize(query);
    final t = normalize(target);
    if (q.isEmpty || t.isEmpty) return false;
    if (t.contains(q) || q.contains(t)) return true;
    final parts = q.split(' ').where((w) => w.length > 1).toList();
    if (parts.isEmpty) return false;
    return parts.any((p) => t.contains(p));
  }
}

class ChromaVisionEngine {
  static bool analyzeFramePixels(Uint8List rgbaBytes) {
    int skinPixels = 0;
    final totalPixels = rgbaBytes.length ~/ 4;
    if (totalPixels < 100) return false;

    for (int i = 0; i < rgbaBytes.length; i += 4) {
      final r = rgbaBytes[i];
      final g = rgbaBytes[i + 1];
      final b = rgbaBytes[i + 2];

      final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;

      final bool isSkinYCbCr = (cb >= 85 && cb <= 125) && (cr >= 138 && cr <= 170);
      final bool isValidBrightness = r > 90 && r < 235 && g > 55 && b > 35;

      if (isSkinYCbCr && isValidBrightness) {
        skinPixels++;
      }
    }

    final double ratio = skinPixels / totalPixels;
    return ratio > 0.62;
  }
}

class ContentFilterEngine {
  static final List<String> triggers = [
    'kiss', 'kissing', 'kisses', 'they kiss', 'make out', 'moan', 'moaning',
    'sex', 'sexual', 'nudity', 'naked', 'passionate', 'undress', 'sleep with',
    'before dawn', 'in bed', 'swimsuit',
    'قبلة', 'يقبل', 'تقبل', 'يقبلها', 'تقبله', 'مداعبة', 'تقبيل', 'عري', 'عارية',
    'عاري', 'مضاجعة', 'جنس', 'ممارسة الجنس', 'فراش', 'السرير', 'ثدي', 'يخلع', 'تخلع'
  ];

  static const String serverBaseUrl = 'https://onebr-censor-api.onrender.com';

  static List<Map<String, int>> parseSubtitles(List<Subtitle> subs) {
    final List<Map<String, int>> segments = [];

    for (var s in subs) {
      final textLower = s.text.toLowerCase();
      final isMatch = triggers.any((t) => textLower.contains(t));

      if (isMatch) {
        final startSec = (s.start.inSeconds - 2).clamp(0, 999999);
        final endSec = s.end.inSeconds + 12;
        segments.add({'start': startSec, 'end': endSec});
      }
    }

    if (segments.isEmpty) return [];
    segments.sort((a, b) => a['start']!.compareTo(b['start']!));

    final List<Map<String, int>> merged = [];
    var current = segments.first;

    for (int i = 1; i < segments.length; i++) {
      final next = segments[i];
      if (next['start']! <= current['end']!) {
        current = {
          'start': current['start']!,
          'end': next['end']! > current['end']! ? next['end']! : current['end']!,
        };
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  static Future<List<Map<String, int>>> fetchCloudTimestamps(String mediaId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('censored_scenes').doc(mediaId).get();
      if (doc.exists && doc.data()?['scenes'] != null) {
        final List raw = doc.data()!['scenes'];
        return raw.map<Map<String, int>>((e) => {
          'start': int.tryParse(e['start'].toString()) ?? 0,
          'end': int.tryParse(e['end'].toString()) ?? 0,
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> triggerBackendScan({
    required String mediaId,
    required String titleEn,
    String? imdbId,
  }) async {
    try {
      String slug = titleEn
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');

      if (slug.isEmpty) slug = 'movie-$mediaId';

      final queryParams = {
        'media_id': mediaId,
        'movie_slug': slug,
      };
      if (imdbId != null && imdbId.isNotEmpty) {
        queryParams['imdb_id'] = imdbId;
      }

      final uri = Uri.parse('$serverBaseUrl/scan').replace(queryParameters: queryParams);
      http.post(uri).catchError((_) => http.Response('', 500));
    } catch (_) {}
  }
}

class AppColors {
  static const Color primary = Color(0xFFFF2D55);
  static const Color primaryDark = Color(0xFFD81E43);
  static const Color star = Color(0xFFFFCC00);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceLight = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);
  static const Color darkBorder = Color(0x28FFFFFF);
  static const Color darkGlassFill = Color(0xB3161618);

  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceLight = Color(0xFFE5E5EA);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF6C6C70);
  static const Color lightBorder = Color(0x1F000000);
  static const Color lightGlassFill = Color(0xCCFFFFFF);
}

class AppRadius {
  static const double card = 16.0;
  static const double chip = 12.0;
  static const double sheet = 26.0;
  static const double button = 22.0;
}

class ExternalPlayerService {
  static Future<void> playInExternalPlayer({
    required String videoUrl,
    required String title,
    Map<String, String>? headers,
  }) async {
    final AndroidIntent intent = AndroidIntent(
      action: 'action_view',
      data: Uri.encodeFull(videoUrl),
      type: 'video/*',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      arguments: <String, dynamic>{
        'title': title,
        if (headers != null) 'headers': headers,
      },
    );
    await intent.launch();
  }
}

class CloudSyncService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static final _messaging = FirebaseMessaging.instance;

  static Future<void> syncWatchlistToCloud(String profile, List<Map<String, dynamic>> watchlist) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('users').doc(uid).collection('profiles').doc(profile).set({
        'watchlist': watchlist,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> toggleSeriesTopic(String seriesId, bool subscribe) async {
    try {
      final topic = 'series_$seriesId';
      if (subscribe) {
        await _messaging.subscribeToTopic(topic);
      } else {
        await _messaging.unsubscribeFromTopic(topic);
      }
    } catch (_) {}
  }

  static Future<void> reportIssue({
    required String mediaId,
    required String title,
    required String reason,
    int? positionSec,
  }) async {
    try {
      await _firestore.collection('user_reports').add({
        'media_id': mediaId,
        'title': title,
        'reason': reason,
        'position_sec': positionSec,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
    } catch (_) {}
  }
}

class Subtitle {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  Subtitle({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });
}

class SubtitleCache {
  static final Map<String, List<Subtitle>> _mem = {};
  static List<Subtitle>? get(String url) => _mem[url];
  static void set(String url, List<Subtitle> list) => _mem[url] = list;
}

class LocalStorageService {
  static Future<List<Map<String, dynamic>>> getList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final raw = prefs.getString('${currentProfile}_$key') ?? prefs.getString(key);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<void> setList(String key, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    await prefs.setString('${currentProfile}_$key', jsonEncode(list));
    if (key == 'user_watchlist') {
      CloudSyncService.syncWatchlistToCloud(currentProfile, list);
    }
  }

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 50, String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => (x[idField] ?? x['id'])?.toString() == (item[idField] ?? item['id'])?.toString());
    list.insert(0, item);
    if (list.length > maxLength) list.removeRange(maxLength, list.length);
    await setList(key, list);
  }

  static Future<void> removeItem(String key, String id, {String idField = 'nb'}) async {
    final list = await getList(key);
    list.removeWhere((x) => (x[idField] ?? x['id'])?.toString() == id);
    await setList(key, list);
  }

  static Future<void> savePlaybackPosition(String id, int positionMs, int durationMs, String title, String poster) async {
    if (durationMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    await prefs.setInt('pos_${currentProfile}_$id', positionMs);

    int totalMinutes = prefs.getInt('stats_minutes_$currentProfile') ?? 0;
    await prefs.setInt('stats_minutes_$currentProfile', totalMinutes + (positionMs > 60000 ? 1 : 0));

    final resumeList = await getList('resume_playback_list');
    resumeList.removeWhere((x) => x['id'] == id);
    if (positionMs < (durationMs - 15000)) {
      resumeList.insert(0, {
        'id': id,
        'position': positionMs,
        'duration': durationMs,
        'title': title,
        'poster': poster,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      if (resumeList.length > 20) resumeList.removeLast();
    }
    await setList('resume_playback_list', resumeList);
  }

  static Future<int> getPlaybackPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    return prefs.getInt('pos_${currentProfile}_$id') ?? prefs.getInt('pos_$id') ?? 0;
  }

  static Future<Set<String>> getWatchedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final list = prefs.getStringList('watched_episodes_${currentProfile}_list') ?? [];
    return list.toSet();
  }

  static Future<void> markEpisodeWatched(String epId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = prefs.getString('current_active_profile') ?? 'default';
    final list = prefs.getStringList('watched_episodes_${currentProfile}_list') ?? [];
    if (!list.contains(epId)) {
      list.add(epId);
      await prefs.setStringList('watched_episodes_${currentProfile}_list', list);
      int epCount = prefs.getInt('stats_episodes_$currentProfile') ?? 0;
      await prefs.setInt('stats_episodes_$currentProfile', epCount + 1);
    }
  }

  static Future<bool> isWatchlist(String id) async {
    final list = await getList('user_watchlist');
    return list.any((x) => (x['nb'] ?? x['id'])?.toString() == id);
  }

  static Future<void> toggleWatchlist(Map<String, dynamic> media) async {
    final list = await getList('user_watchlist');
    final id = (media['nb'] ?? media['id'])?.toString();
    final exists = list.any((x) => (x['nb'] ?? x['id'])?.toString() == id);
    if (exists) {
      list.removeWhere((x) => (x['nb'] ?? x['id'])?.toString() == id);
    } else {
      list.insert(0, media);
    }
    await setList('user_watchlist', list);
  }

  static Future<bool> isSubscribed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('subscribed_notifications') ?? [];
    return list.contains(id);
  }

  static Future<void> toggleSubscribed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('subscribed_notifications') ?? [];
    final subscribed = list.contains(id);
    if (subscribed) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await prefs.setStringList('subscribed_notifications', list);
    CloudSyncService.toggleSeriesTopic(id, !subscribed);
  }
}

class BackgroundDownloadService {
  static final ReceivePort _port = ReceivePort();
  static final StreamController<List<dynamic>> progressStream = StreamController<List<dynamic>>.broadcast();

  static Future<void> initialize() async {
    try {
      await FlutterDownloader.initialize(debug: false, ignoreSsl: true);
      IsolateNameServer.removePortNameMapping('downloader_send_port');
      IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
      FlutterDownloader.registerCallback(downloadCallback);

      _port.listen((dynamic data) {
        progressStream.add(data);
      });
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  static Future<String> getAppStoragePath() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/Downloads');
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }
    return saveDir.path;
  }

  static Future<String?> startDownload({
    required String url,
    required String fileName,
    required String targetId,
    required String title,
    required String poster,
    String? subUrl,
  }) async {
    if (!RemoteAdminConfig.instance.allowDownloads) return null;

    final path = await getAppStoragePath();
    final filePath = '$path/$fileName';
    final cleanId = targetId.replaceAll(RegExp(r'[^\w\.-]'), '_');
    final localSubPath = '$path/${cleanId}_sub.srt';

    final taskId = await FlutterDownloader.enqueue(
      url: url,
      headers: StreamService.stealthHeaders,
      savedDir: path,
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: false,
      saveInPublicStorage: false,
    );

    if (taskId != null) {
      await LocalStorageService.appendItem('downloaded_works_list', {
        'nb': targetId,
        'taskId': taskId,
        'title': title,
        'path': filePath,
        'subPath': localSubPath,
        'poster': poster,
        'progress': 0,
        'status': 1,
        'isCompleted': false,
        'date': DateTime.now().millisecondsSinceEpoch,
      });

      if (subUrl != null && subUrl.isNotEmpty) {
        http.get(Uri.parse(subUrl), headers: StreamService.stealthHeaders).then((subRes) async {
          if (subRes.statusCode == 200) {
            final subFile = File(localSubPath);
            await subFile.writeAsBytes(subRes.bodyBytes);
          }
        }).catchError((_) {});
      }
    }

    return taskId;
  }
}

class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._();
  AppSettings._();

  bool isDarkMode = true;
  int seekDuration = 10;
  bool skipSensitiveScenes = true;
  double subFontSize = 18.0;
  Color subColor = Colors.white;
  bool subHasShadow = true;
  double subBottomPadding = 26.0;
  String subBackgroundMode = 'semi';
  bool enableDualSubtitlesFlag = false;
  int appFilterMode = 0;
  String appLanguage = 'ar';
  String selectedFont = 'iPhone';
  bool autoSmartDownload = false;
  bool smartNotifications = true;
  bool tvModeEnabled = false;
  String themeMode = 'dark'; // dark, light, system

  String? userName;
  String? userEmail;
  String activeProfile = 'الرئيسي';
  List<String> userProfiles = ['الرئيسي', 'الأطفال', 'عائلي'];

  Color get bg => isDarkMode ? AppColors.darkBackground : AppColors.lightBackground;
  Color get surface => isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;
  Color get surfaceLight => isDarkMode ? AppColors.darkSurfaceLight : AppColors.lightSurfaceLight;
  Color get textPrimary => isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get border => isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;
  Color get glassFill => isDarkMode ? AppColors.darkGlassFill : AppColors.lightGlassFill;

  Color get subtitleBackgroundColor {
    switch (subBackgroundMode) {
      case 'transparent':
        return Colors.transparent;
      case 'dark':
        return Colors.black.withOpacity(0.85);
      case 'semi':
      default:
        return Colors.black.withOpacity(0.40);
    }
  }

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      isDarkMode = p.getBool('app_is_dark_mode') ?? true;
      seekDuration = p.getInt('player_seek_dur') ?? 10;
      skipSensitiveScenes = p.getBool('player_skip_sens') ?? true;
      subFontSize = p.getDouble('player_sub_size') ?? 18.0;
      subBottomPadding = p.getDouble('player_sub_bottom') ?? 26.0;
      subBackgroundMode = p.getString('player_sub_bg_mode') ?? 'semi';
      enableDualSubtitlesFlag = p.getBool('player_dual_sub') ?? false;
      appFilterMode = p.getInt('app_filter_mode') ?? 0;
      appLanguage = p.getString('app_lang') ?? 'ar';
      selectedFont = p.getString('app_font') ?? 'iPhone';
      autoSmartDownload = p.getBool('app_smart_dl') ?? false;
      smartNotifications = p.getBool('app_smart_notif') ?? true;
      tvModeEnabled = p.getBool('app_tv_mode') ?? false;
      themeMode = p.getString('app_theme_mode') ?? (isDarkMode ? 'dark' : 'light');
      userName = p.getString('auth_user_name');
      userEmail = p.getString('auth_user_email');
      activeProfile = p.getString('current_active_profile') ?? 'الرئيسي';
      final rawP = p.getStringList('user_profiles_list');
      if (rawP != null) userProfiles = rawP;
    } catch (_) {}
  }

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
    themeMode = isDarkMode ? 'dark' : 'light';
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_is_dark_mode', isDarkMode);
    await p.setString('app_theme_mode', themeMode);
  }

  void updateThemeMode(String mode) async {
    themeMode = mode;
    isDarkMode = mode == 'dark' ? true : mode == 'light' ? false : isDarkMode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('app_theme_mode', mode);
    await p.setBool('app_is_dark_mode', isDarkMode);
  }

  void updateLanguage(String lang) async {
    appLanguage = lang;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('app_lang', lang);
  }

  void updateSeek(int sec) async {
    seekDuration = sec;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('player_seek_dur', sec);
  }

  void updateFilterMode(int mode) async {
    appFilterMode = mode;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('app_filter_mode', mode);
  }

  void updateTvMode(bool val) async {
    tvModeEnabled = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_tv_mode', val);
  }

  void updateSubStyle({double? size, Color? color, bool? shadow, double? bottomPadding, String? bgMode}) async {
    if (size != null) subFontSize = size;
    if (color != null) subColor = color;
    if (shadow != null) subHasShadow = shadow;
    if (bottomPadding != null) subBottomPadding = bottomPadding;
    if (bgMode != null) subBackgroundMode = bgMode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (bottomPadding != null) await p.setDouble('player_sub_bottom', bottomPadding);
    if (size != null) await p.setDouble('player_sub_size', size);
    if (bgMode != null) await p.setString('player_sub_bg_mode', bgMode);
  }

  void resetSubtitles() async {
    subFontSize = 18.0;
    subColor = Colors.white;
    subHasShadow = true;
    subBottomPadding = 26.0;
    subBackgroundMode = 'semi';
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('player_sub_size', 18.0);
    await p.setDouble('player_sub_bottom', 26.0);
    await p.setString('player_sub_bg_mode', 'semi');
  }

  void updateDualSubtitles(bool val) async {
    enableDualSubtitlesFlag = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('player_dual_sub', val);
  }

  void updateSkipScenes(bool val) async {
    skipSensitiveScenes = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('player_skip_sens', val);
  }

  void updateSmartNotifications(bool val) async {
    smartNotifications = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_smart_notif', val);
  }

  void updateSmartDownload(bool val) async {
    autoSmartDownload = val;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('app_smart_dl', val);
  }

  void updateFont(String font) async {
    selectedFont = font;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('app_font', font);
  }

  void login(String name, String email) async {
    userName = name;
    userEmail = email;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('auth_user_name', name);
    await p.setString('auth_user_email', email);
  }

  void logout() async {
    userName = null;
    userEmail = null;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove('auth_user_name');
    await p.remove('auth_user_email');
  }

  void switchProfile(String profile) async {
    activeProfile = profile;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('current_active_profile', profile);
  }

  void addProfile(String profileName) async {
    if (!userProfiles.contains(profileName)) {
      userProfiles.add(profileName);
      notifyListeners();
      (await SharedPreferences.getInstance()).setStringList('user_profiles_list', userProfiles);
    }
  }

  TextTheme getCustomTextTheme() {
    final base = isDarkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    switch (selectedFont) {
      case 'Cairo':
        return GoogleFonts.cairoTextTheme(base);
      case 'Tajawal':
        return GoogleFonts.tajawalTextTheme(base);
      case 'Almarai':
        return GoogleFonts.almaraiTextTheme(base);
      default:
        return GoogleFonts.ibmPlexSansArabicTextTheme(base);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = SecureHttpOverrides();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase error: $e");
  }

  try {
    await BackgroundDownloadService.initialize();
  } catch (e) {
    debugPrint("Download service error: $e");
  }

  try {
    await AppSettings.instance.init();
  } catch (e) {
    debugPrint("Settings error: $e");
  }

  runApp(const OnebrTvApp());
}


class AppLocalization {
  static const Map<String, Map<String, String>> _values = {
    'ar': {
      'clip_share': 'قص ومشاركة Short / Reels',
      'external_subtitles': 'استيراد ترجمة خارجية',
      'subtitle_offset': 'مزامنة توقيت الترجمة',
      'social_accounts': 'حسابات التطبيق الرسمية',
      'content_request': 'طلب فيلم أو مسلسل',
      'link_health': 'فحص حالة الروابط',
      'iptv_channels': 'قنوات البث المباشر',
      'advanced_security': 'لوحة الأمان المتقدمة',
    },
    'en': {
      'clip_share': 'Clip & Share Short / Reels',
      'external_subtitles': 'Import External Subtitle',
      'subtitle_offset': 'Subtitle Timing Offset',
      'social_accounts': 'Official App Accounts',
      'content_request': 'Request a Movie or Series',
      'link_health': 'Link Health Check',
      'iptv_channels': 'Live IPTV Channels',
      'advanced_security': 'Advanced Security Panel',
    },
  };

  static String tr(String key, String lang) => _values[lang]?[key] ?? _values['en']?[key] ?? key;
}

class BanService {
  static String _installationId = '';

  static Future<String> installationId() async {
    if (_installationId.isNotEmpty) return _installationId;
    final p = await SharedPreferences.getInstance();
    var id = p.getString('installation_id');
    if (id == null || id.isEmpty) {
      final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      id = '${seed}_${Random().nextInt(0x7fffffff).toRadixString(36)}';
      await p.setString('installation_id', id);
    }
    _installationId = id;
    return id;
  }

  static Future<bool> isBanned() async {
    if (!RemoteAdminConfig.instance.isFeatureEnabled('device_ban')) return false;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final email = FirebaseAuth.instance.currentUser?.email ?? AppSettings.instance.userEmail;
      final deviceId = await installationId();
      if (email != null && email.isNotEmpty) {
        final emailDoc = await FirebaseFirestore.instance.collection('banned_users').doc(email.trim().toLowerCase()).get();
        if (emailDoc.exists && emailDoc.data()?['active'] != false) return true;
      }
      if (uid != null && uid.isNotEmpty) {
        final uidDoc = await FirebaseFirestore.instance.collection('banned_users').doc(uid).get();
        if (uidDoc.exists && uidDoc.data()?['active'] != false) return true;
      }
      final deviceDoc = await FirebaseFirestore.instance.collection('banned_devices').doc(deviceId).get();
      return deviceDoc.exists && deviceDoc.data()?['active'] != false;
    } catch (_) {
      return false;
    }
  }
}

class BanLockScreen extends StatelessWidget {
  const BanLockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      backgroundColor: s.bg,
      body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.block_rounded, color: AppColors.primary, size: 72),
        const SizedBox(height: 18),
        Text(s.appLanguage == 'ar' ? 'تم تقييد الوصول' : 'Access restricted', style: TextStyle(color: s.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(s.appLanguage == 'ar' ? 'تم تعطيل هذا الحساب أو الجهاز من استخدام التطبيق.' : 'This account or device has been restricted from using the app.', textAlign: TextAlign.center, style: TextStyle(color: s.textSecondary, height: 1.5)),
      ])),
    );
  }
}

class OnebrTvApp extends StatefulWidget {
  const OnebrTvApp({super.key});

  @override
  State<OnebrTvApp> createState() => _OnebrTvAppState();
}

class _OnebrTvAppState extends State<OnebrTvApp> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(() => setState(() {}));
    RemoteAdminConfig.instance.listenToSettings(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final r = RemoteAdminConfig.instance;

    final systemDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final effectiveDark = s.themeMode == 'system' ? systemDark : s.themeMode == 'dark';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ONEBR TV',
      theme: (effectiveDark ? ThemeData.dark() : ThemeData.light()).copyWith(
        scaffoldBackgroundColor: s.bg,
        primaryColor: AppColors.primary,
        cardColor: s.surface,
        textTheme: s.getCustomTextTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: effectiveDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        ),
        colorScheme: effectiveDark
            ? const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.darkSurface)
            : const ColorScheme.light(primary: AppColors.primary, surface: AppColors.lightSurface),
      ),
      home: r.isMaintenance && !RemoteAdminConfig.isEmailAdmin(s.userEmail)
          ? const MaintenanceLockScreen()
          : FutureBuilder<bool>(
              future: BanService.isBanned(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
                }
                return snapshot.data == true ? const BanLockScreen() : const MainNavigationHolder();
              },
            ),
    );
  }
}

class MaintenanceLockScreen extends StatelessWidget {
  const MaintenanceLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final r = RemoteAdminConfig.instance;

    return Scaffold(
      backgroundColor: s.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.build_circle_rounded, color: AppColors.primary, size: 70),
              const SizedBox(height: 20),
              Text(
                'ONEBR TV - وضع الصيانة السحابية',
                style: TextStyle(color: s.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                r.maintenanceMsg,
                textAlign: TextAlign.center,
                style: TextStyle(color: s.textSecondary, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreenContent(),
    CategoriesScreen(),
    const AdvancedSearchScreen(),
    const LibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _checkAppPopup();
  }

  void _checkAppPopup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = RemoteAdminConfig.instance;
      if (r.popupTitle.isNotEmpty && r.popupBody.isNotEmpty) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: Text(r.popupTitle),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(r.popupBody),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('إغلاق'),
                onPressed: () => Navigator.pop(ctx),
              ),
              if (r.popupActionUrl.isNotEmpty)
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('فتح الرابط'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    launchUrl(Uri.parse(r.popupActionUrl), mode: LaunchMode.externalApplication);
                  },
                ),
            ],
          ),
        );
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('الخروج من ONEBR TV'),
        content: const Text('هل ترغب حقاً في إغلاق التطبيق؟'),
        actions: [
          CupertinoDialogAction(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('خروج'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: s.bg,
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: s.glassFill,
                  border: Border(top: BorderSide(color: s.border, width: 0.5)),
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: s.textSecondary,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 10,
                  unselectedFontSize: 10,
                  onTap: (i) {
                    HapticFeedback.lightImpact();
                    setState(() => _currentIndex = i);
                  },
                  items: [
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.home_filled, size: 23)),
                      label: isAr ? 'الرئيسية' : 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.grid_view_rounded, size: 23)),
                      label: isAr ? 'الأقسام' : 'Categories',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.search_rounded, size: 23)),
                      label: isAr ? 'بحث' : 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: const Padding(padding: EdgeInsets.only(bottom: 2), child: Icon(Icons.person_rounded, size: 23)),
                      label: isAr ? 'الحساب' : 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  CategoriesScreen({super.key});

  final List<Map<String, dynamic>> _allCategories = const [
    {'key': 'horror', 'ar': 'رعب وتشويق', 'en': 'Horror & Suspense', 'icon': Icons.local_fire_department_rounded},
    {'key': 'action', 'ar': 'أكشن وحركة', 'en': 'Action & Adventure', 'icon': Icons.flash_on_rounded},
    {'key': 'animation', 'ar': 'أنمي ورسوم متحركة', 'en': 'Anime & Animation', 'icon': Icons.auto_awesome_rounded},
    {'key': 'comedy', 'ar': 'كوميديا وضحك', 'en': 'Comedy', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'key': 'sci-fi', 'ar': 'خيال علمي وفضاء', 'en': 'Sci-Fi & Space', 'icon': Icons.rocket_launch_rounded},
    {'key': 'drama', 'ar': 'دراما وقصص واقعية', 'en': 'Drama & Real Stories', 'icon': Icons.movie_rounded},
    {'key': 'romance', 'ar': 'رومانسية وحب', 'en': 'Romance', 'icon': Icons.favorite_rounded},
    {'key': 'crime', 'ar': 'جريمة وتحقيق', 'en': 'Crime & Mystery', 'icon': Icons.shield_rounded},
    {'key': 'adventure', 'ar': 'مغامرات واستكشاف', 'en': 'Adventure', 'icon': Icons.explore_rounded},
    {'key': 'thriller', 'ar': 'إثارة وغموض', 'en': 'Thriller', 'icon': Icons.remove_red_eye_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'الأقسام والتصنيفات' : 'Categories & Genres', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: s.textPrimary)),
        ),
        body: ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _allCategories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final cat = _allCategories[i];
            final title = isAr ? cat['ar'] : cat['en'];

            return FocusBuilder(
              builder: (context, hasFocus) => Container(
                decoration: BoxDecoration(
                  color: hasFocus ? s.surfaceLight : s.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasFocus ? AppColors.primary : s.border,
                    width: hasFocus ? 1.5 : 0.5,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: s.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(cat['icon'], color: AppColors.primary, size: 20),
                  ),
                  title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: s.textPrimary)),
                  trailing: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: s.textSecondary, size: 20),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FullCategoryView(title: title, categoryEn: cat['key'])),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FullCategoryView extends StatefulWidget {
  final String title;
  final bool isSeriesOnly;
  final String? categoryEn;
  final String? searchQuery;
  final bool isTopRated;

  const FullCategoryView({
    super.key,
    required this.title,
    this.isSeriesOnly = false,
    this.categoryEn,
    this.searchQuery,
    this.isTopRated = false,
  });

  @override
  State<FullCategoryView> createState() => _FullCategoryViewState();
}

class _FullCategoryViewState extends State<FullCategoryView> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<dynamic> _items = [];
  final Set<String> _unique = {};
  int _page = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
        if (!_isLoading && widget.searchQuery == null) _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    List<dynamic> fresh = [];
    final level = AppSettings.instance.appFilterMode;

    if (widget.searchQuery != null) {
      fresh = await StreamService.searchContent(widget.searchQuery!, level: level);
    } else if (widget.categoryEn != null) {
      fresh = await StreamService.fetchByCategoryName(widget.categoryEn!, page: _page, level: level);
    } else {
      fresh = await StreamService.fetchFeed(isSeries: widget.isSeriesOnly, page: _page, perPage: 28, level: level);
      if (widget.isTopRated) {
        fresh.sort((a, b) {
          final sA = double.tryParse((a['stars'] ?? '0').toString()) ?? 0.0;
          final sB = double.tryParse((b['stars'] ?? '0').toString()) ?? 0.0;
          return sB.compareTo(sA);
        });
      }
    }

    final blacklisted = RemoteAdminConfig.instance.blacklistedMediaIds.toSet();
    final List<dynamic> deduplicated = [];
    for (var it in fresh) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_unique.contains(id) && !blacklisted.contains(id)) {
        _unique.add(id);
        deduplicated.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _items.addAll(deduplicated);
        _page++;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final isTv = s.tvModeEnabled;
    final count = isTv ? 6 : (MediaQuery.of(context).size.width > 700 ? 5 : 3);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: s.textPrimary)),
          leading: IconButton(
            icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 28, color: s.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: GridView.builder(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.58,
          ),
          itemCount: _items.length,
          itemBuilder: (ctx, i) {
            final it = _items[i];
            final poster = StreamService.extractPoster(it);
            final title = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');

            return FocusBuilder(
              builder: (context, hasFocus) => InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it)));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: s.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                            color: hasFocus ? AppColors.primary : s.border,
                            width: hasFocus ? 2.0 : 0.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: poster.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: poster,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: s.surfaceLight),
                                  errorWidget: (_, __, ___) => Container(color: s.surfaceLight, child: const Icon(Icons.broken_image_rounded, color: Colors.white24)),
                                )
                              : Container(color: s.surface),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _heroItems = [];
  List<dynamic> _marvelItems = [];
  List<dynamic> _featuredItems = [];
  List<dynamic> _recentItems = [];
  List<dynamic> _infiniteList = [];
  List<Map<String, dynamic>> _resumeList = [];
  final Set<String> _uniqueIds = {};
  int _currentHeroIdx = 0;
  int _page = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  int _adminClickCount = 0;
  DateTime? _lastAdminClick;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    AppSettings.instance.addListener(_onSettingsChanged);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoadingMore) {
          _fetchMore();
        }
      }
    });
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _handleSecretAdminTap() {
    final now = DateTime.now();
    if (_lastAdminClick == null || now.difference(_lastAdminClick!) > const Duration(seconds: 2)) {
      _adminClickCount = 1;
    } else {
      _adminClickCount++;
    }
    _lastAdminClick = now;

    if (_adminClickCount >= 5) {
      _adminClickCount = 0;
      _triggerAdminEmailAuth();
    }
  }

  void _triggerAdminEmailAuth() {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    if (RemoteAdminConfig.isEmailAdmin(s.userEmail)) {
      HapticFeedback.heavyImpact();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
      return;
    }

    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isAr ? 'منطقة الإدارة السحابية 🔒' : 'Cloud Admin Portal 🔒'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'أدخل البريد المعتمد للأدمن وكلمة المرور' : 'Enter authorized admin email & password',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: emailCtrl,
                placeholder: isAr ? 'بريد المسؤول' : 'Admin Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: passCtrl,
                obscureText: true,
                placeholder: isAr ? 'كلمة المرور' : 'Password',
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(isAr ? 'تحقق ودخول' : 'Authorize'),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              final pass = passCtrl.text.trim();

              if (!RemoteAdminConfig.isEmailAdmin(email)) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isAr ? 'هذا البريد غير مصرّح له بالدخول كمسؤول' : 'Unauthorized admin email')),
                );
                return;
              }

              try {
                final authResult = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
                if (authResult.user != null) {
                  s.login(authResult.user?.displayName ?? 'Admin', email);
                  Navigator.pop(ctx);
                  HapticFeedback.heavyImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                }
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isAr ? 'فشل التحقق: تأكد من صحة البريد وكلمة المرور' : 'Auth failed: Check email & password')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);
    _resumeList = await LocalStorageService.getList('resume_playback_list');
    _uniqueIds.clear();

    final level = AppSettings.instance.appFilterMode;
    final blacklisted = RemoteAdminConfig.instance.blacklistedMediaIds.toSet();

    try {
      final res = await Future.wait([
        StreamService.fetchFeed(isSeries: false, page: 0, perPage: 35, level: level),
        StreamService.fetchFeed(isSeries: true, page: 0, perPage: 25, level: level),
        StreamService.fetchByCategoryName('action', page: 0, level: level),
      ]);

      final allMovies = res[0].where((x) => !blacklisted.contains((x['nb'] ?? x['id']).toString())).toList();
      final allSeries = res[1].where((x) => !blacklisted.contains((x['nb'] ?? x['id']).toString())).toList();
      final actionList = res[2].where((x) => !blacklisted.contains((x['nb'] ?? x['id']).toString())).toList();

      List<dynamic> hero = [];
      final pinned = RemoteAdminConfig.instance.pinnedHeroIds;
      if (pinned.isNotEmpty) {
        hero = allMovies.where((x) => pinned.contains((x['nb'] ?? x['id']).toString())).toList();
      }
      if (hero.isEmpty) {
        hero = allMovies.take(5).toList();
      }

      final heroIds = hero.map((e) => (e['nb'] ?? e['id']).toString()).toSet();

      final featured = allMovies.where((it) {
        final id = (it['nb'] ?? it['id']).toString();
        return !heroIds.contains(id);
      }).toList();
      featured.sort((a, b) {
        final sA = double.tryParse((a['stars'] ?? '0').toString()) ?? 0.0;
        final sB = double.tryParse((b['stars'] ?? '0').toString()) ?? 0.0;
        return sB.compareTo(sA);
      });

      final recent = allSeries.take(12).toList();
      final combined = [...allMovies, ...allSeries];
      for (var it in combined) {
        final id = (it['nb'] ?? it['id'])?.toString();
        if (id != null) _uniqueIds.add(id);
      }

      if (mounted) {
        setState(() {
          _heroItems = hero;
          _marvelItems = actionList.take(12).toList();
          _featuredItems = featured.take(12).toList();
          _recentItems = recent;
          _infiniteList = List.from(combined);
          _page = 1;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMore() async {
    setState(() => _isLoadingMore = true);
    final level = AppSettings.instance.appFilterMode;
    final blacklisted = RemoteAdminConfig.instance.blacklistedMediaIds.toSet();

    final res = await Future.wait([
      StreamService.fetchFeed(isSeries: false, page: _page, perPage: 16, level: level),
      StreamService.fetchFeed(isSeries: true, page: _page, perPage: 16, level: level),
    ]);

    final fresh = [...res[0], ...res[1]];
    final List<dynamic> deduplicated = [];
    for (var it in fresh) {
      final id = (it['nb'] ?? it['id'])?.toString();
      if (id != null && !_uniqueIds.contains(id) && !blacklisted.contains(id)) {
        _uniqueIds.add(id);
        deduplicated.add(it);
      }
    }

    if (mounted) {
      setState(() {
        _infiniteList.addAll(deduplicated);
        _page++;
        _isLoadingMore = false;
      });
    }
  }

  void _openDetails(Map<String, dynamic> item) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: MediaDetailScreen(media: item)),
      ),
    ).then((_) async {
      final l = await LocalStorageService.getList('resume_playback_list');
      if (mounted) setState(() => _resumeList = l);
    });
  }

  void _openSectionView(String title, bool isSeries) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullCategoryView(
          title: title,
          isSeriesOnly: isSeries,
        ),
      ),
    );
  }

  void _spinMovieRoulette() {
    HapticFeedback.heavyImpact();
    if (_infiniteList.isEmpty) return;
    final randomItem = _infiniteList[(DateTime.now().millisecondsSinceEpoch) % _infiniteList.length];
    final isAr = AppSettings.instance.appLanguage == 'ar';
    final title = isAr ? (randomItem['ar_title'] ?? randomItem['en_title'] ?? '') : (randomItem['en_title'] ?? randomItem['ar_title'] ?? '');

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isAr ? 'اقترحنا لك هذا العمل! 🎬' : 'Our Pick For You! 🎬'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          CupertinoDialogAction(child: Text(isAr ? 'إلغاء' : 'Cancel'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(isAr ? 'مشاهدة التفاصيل' : 'View Details'),
            onPressed: () {
              Navigator.pop(ctx);
              _openDetails(randomItem);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final r = RemoteAdminConfig.instance;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = s.tvModeEnabled;
    final gridCount = isTv ? 6 : (screenWidth > 700 ? 5 : 3);
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tv_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _handleSecretAdminTap,
                child: Text(
                  'ONEBR TV',
                  style: TextStyle(
                    color: s.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: s.isDarkMode ? (isAr ? 'الوضع الفاتح' : 'Light Mode') : (isAr ? 'الوضع الداكن' : 'Dark Mode'),
                icon: Icon(s.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: s.textPrimary, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  s.toggleTheme();
                },
              ),
              IconButton(
                tooltip: isAr ? 'وضع التلفاز' : 'TV Mode',
                icon: Icon(isTv ? Icons.tv_rounded : Icons.phone_android_rounded, color: isTv ? AppColors.primary : s.textSecondary, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  s.updateTvMode(!isTv);
                },
              ),
              IconButton(
                tooltip: isAr ? 'شنو نباوع اليوم؟' : 'Roulette',
                icon: const Icon(Icons.casino_rounded, color: AppColors.star, size: 22),
                onPressed: _spinMovieRoulette,
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadFeed,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.globalAlert.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.campaign_rounded, color: Colors.amber, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(r.globalAlert, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),

                      if (_heroItems.isNotEmpty) _buildCarouselBanner(isAr),
                      _buildCinemaFilterButtons(isAr),
                      if (_resumeList.isNotEmpty) _buildResumeSection(isAr),

                      _buildMediaShelf(
                        isAr ? 'أفلام الحركة والأكشن' : 'Action Movies',
                        _marvelItems,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullCategoryView(
                              title: isAr ? 'أفلام الحركة والأكشن' : 'Action Movies',
                              categoryEn: 'action',
                            ),
                          ),
                        ),
                        isAr,
                      ),

                      _buildMediaShelf(
                        isAr ? 'الأفلام المميزة' : 'Featured Movies',
                        _featuredItems,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullCategoryView(
                              title: isAr ? 'الأفلام المميزة' : 'Featured Movies',
                              isTopRated: true,
                            ),
                          ),
                        ),
                        isAr,
                      ),

                      _buildMediaShelf(
                        isAr ? 'أُضيف مؤخراً' : 'Recently Added',
                        _recentItems,
                        () => _openSectionView(isAr ? 'أُضيف مؤخراً' : 'Recently Added', true),
                        isAr,
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isAr ? 'استكشف المزيد من الأعمال' : 'Explore More Titles', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                            const Icon(Icons.movie_filter_rounded, color: AppColors.primary, size: 18),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: gridCount,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.58,
                          ),
                          itemCount: _infiniteList.length,
                          itemBuilder: (ctx, i) {
                            final it = _infiniteList[i];
                            final poster = StreamService.extractPoster(it);
                            final t = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
                            final score = (it['stars'] ?? '7.0').toString();

                            return FocusBuilder(
                              builder: (context, hasFocus) => InkWell(
                                onTap: () => _openDetails(it),
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: s.surface,
                                          borderRadius: BorderRadius.circular(AppRadius.card),
                                          border: Border.all(
                                            color: hasFocus ? AppColors.primary : s.border,
                                            width: 2.0,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(AppRadius.card),
                                          child: poster.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: poster,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  placeholder: (_, __) => Container(color: s.surfaceLight),
                                                  errorWidget: (_, __, ___) => Container(color: s.surfaceLight, child: const Icon(Icons.broken_image_rounded, color: Colors.white24)),
                                                )
                                              : Container(color: s.surface),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                                        const SizedBox(width: 3),
                                        Text(score, style: TextStyle(color: s.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCinemaFilterButtons(bool isAr) {
    final s = AppSettings.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: FocusBuilder(
              builder: (context, hasFocus) => InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _openSectionView(isAr ? 'الأفلام السينمائية' : 'Movies', false);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: hasFocus ? s.surfaceLight : s.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFocus ? AppColors.primary : s.border,
                      width: hasFocus ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(isAr ? 'الأفلام' : 'Movies', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FocusBuilder(
              builder: (context, hasFocus) => InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _openSectionView(isAr ? 'المسلسلات والأنمي' : 'TV Series', true);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: hasFocus ? s.surfaceLight : s.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFocus ? AppColors.primary : s.border,
                      width: hasFocus ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tv_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(isAr ? 'المسلسلات' : 'Series', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselBanner(bool isAr) {
    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 220,
            viewportFraction: 0.92,
            enlargeCenterPage: true,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            onPageChanged: (idx, _) => setState(() => _currentHeroIdx = idx),
          ),
          items: _heroItems.map<Widget>((item) {
            final poster = StreamService.extractPoster(item, highRes: true);
            final title = isAr ? (item['ar_title'] ?? item['en_title'] ?? '') : (item['en_title'] ?? item['ar_title'] ?? '');

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppSettings.instance.border, width: 0.5),
                color: AppSettings.instance.surface,
              ),
              child: Stack(
                children: [
                  if (poster.isNotEmpty)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: Colors.black26),
                          errorWidget: (_, __, ___) => Container(color: Colors.black26),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x77000000), Color(0xF2000000)],
                        stops: [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14, right: 16, left: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              const Text('4K Ultra HD', style: TextStyle(color: AppColors.star, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minSize: 0,
                          onPressed: () => _openDetails(item),
                          child: Text(
                            isAr ? 'شاهد الآن' : 'Watch',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _heroItems.asMap().entries.map<Widget>((entry) {
            final isSel = entry.key == _currentHeroIdx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSel ? 18 : 6,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSel ? AppColors.primary : Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildResumeSection(bool isAr) {
    final s = AppSettings.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isAr ? 'متابعة المشاهدة' : 'Continue Watching', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await LocalStorageService.setList('resume_playback_list', []);
                  setState(() => _resumeList = []);
                },
                child: Text(isAr ? 'إزالة الكل' : 'Clear All', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 115,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _resumeList.length,
            itemBuilder: (ctx, i) {
              final it = _resumeList[i];
              final progress = (it['position'] / it['duration']).clamp(0.0, 1.0);

              return Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            mediaId: it['id'],
                            title: it['title'] ?? '',
                            videoUrl: '',
                            qualities: const [],
                            poster: it['poster'] ?? '',
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: s.border, width: 0.5),
                        color: s.surface,
                      ),
                      child: Stack(
                        children: [
                          if (it['poster'].toString().isNotEmpty)
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                child: CachedNetworkImage(imageUrl: it['poster'], fit: BoxFit.cover),
                              ),
                            ),
                          Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), color: Colors.black45)),
                          const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 34)),
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                              child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4, right: 14,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await LocalStorageService.removeItem('resume_playback_list', it['id'].toString(), idField: 'id');
                        final l = await LocalStorageService.getList('resume_playback_list');
                        setState(() => _resumeList = l);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaShelf(String title, List<dynamic> items, VoidCallback onMore, bool isAr) {
    if (items.isEmpty) return const SizedBox();
    final s = AppSettings.instance;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onMore();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(isAr ? 'المزيد' : 'More', style: TextStyle(color: s.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final it = items[i];
              final poster = StreamService.extractPoster(it);
              final t = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
              final score = (it['stars'] ?? '7.0').toString();

              return Container(
                width: 105,
                margin: const EdgeInsets.only(left: 10),
                child: FocusBuilder(
                  builder: (context, hasFocus) => InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: () => _openDetails(it),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: s.surface,
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              border: Border.all(
                                color: hasFocus ? AppColors.primary : s.border,
                                width: 2.0,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              child: poster.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: poster,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(color: s.surfaceLight),
                                      errorWidget: (_, __, ___) => Container(color: s.surfaceLight, child: const Icon(Icons.broken_image_rounded, color: Colors.white24)),
                                    )
                                  : Container(color: s.surface),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                            const SizedBox(width: 3),
                            Text(score, style: TextStyle(color: s.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _movieResults = [];
  List<dynamic> _seriesResults = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _isSearching = false;
  Timer? _debounce;
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadRecents() async {
    final list = await LocalStorageService.getList('recent_search_history');
    if (mounted) setState(() => _recentSearches = list);
  }

  void _onQueryChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(val);
    });
  }

  void _executeSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _movieResults.clear();
          _seriesResults.clear();
          _isSearching = false;
        });
      }
      return;
    }

    setState(() => _isSearching = true);
    final level = AppSettings.instance.appFilterMode;

    try {
      final results = await StreamService.searchContent(q, level: level);

      final List<dynamic> movies = [];
      final List<dynamic> series = [];

      for (var it in results) {
        final isSeries = (it['is_series_fixed'] == true) ||
            (it['season'] != null && it['season'].toString() != '0' && it['season'].toString() != '');
        if (isSeries) {
          series.add(it);
        } else {
          movies.add(it);
        }
      }

      if (mounted) {
        setState(() {
          _movieResults = movies;
          _seriesResults = series;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onQueryChanged,
                    style: TextStyle(color: s.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: isAr ? 'بحث عن فيلم أو مسلسل...' : 'Search movies or series...',
                      hintStyle: TextStyle(color: s.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, color: s.textSecondary, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _executeSearch('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip(isAr ? 'الكل' : 'All', _filterType == 'all', () => setState(() => _filterType = 'all')),
                      const SizedBox(width: 8),
                      _buildFilterChip(isAr ? 'أفلام' : 'Movies', _filterType == 'movie', () => setState(() => _filterType = 'movie')),
                      const SizedBox(width: 8),
                      _buildFilterChip(isAr ? 'مسلسلات' : 'Series', _filterType == 'series', () => setState(() => _filterType = 'series')),
                    ],
                  ),
                ),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _searchCtrl.text.isNotEmpty
                        ? (_movieResults.isNotEmpty || _seriesResults.isNotEmpty)
                            ? _buildCategorizedResults(isAr)
                            : Center(
                                child: Text(
                                  isAr ? 'لم يتم العثور على نتائج تطابق هذا البحث' : 'No results found',
                                  style: TextStyle(color: s.textSecondary, fontSize: 13),
                                ),
                              )
                        : _buildRecentSearches(isAr),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    final s = AppSettings.instance;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : s.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : s.border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : s.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCategorizedResults(bool isAr) {
    final s = AppSettings.instance;
    final showSeries = _filterType == 'all' || _filterType == 'series';
    final showMovies = _filterType == 'all' || _filterType == 'movie';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (showSeries && _seriesResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(isAr ? 'المسلسلات' : 'Series', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._seriesResults.map<Widget>((it) => _buildMediaSearchRow(it, isAr)).toList(),
          Divider(color: s.border, height: 24),
        ],
        if (showMovies && _movieResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(isAr ? 'الأفلام' : 'Movies', style: TextStyle(color: s.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          ..._movieResults.map<Widget>((it) => _buildMediaSearchRow(it, isAr)).toList(),
        ],
      ],
    );
  }

  Widget _buildMediaSearchRow(dynamic it, bool isAr) {
    final s = AppSettings.instance;
    final poster = StreamService.extractPoster(it);
    final title = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');
    final year = it['year']?.toString() ?? '2024';
    final score = (it['stars'] ?? '7.5').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.lightImpact();
        LocalStorageService.appendItem('recent_search_history', it, maxLength: 20);
        _loadRecents();
        Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('$year • HD', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: s.border, width: 0.8), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('IMDb', style: TextStyle(color: s.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Text(score, style: TextStyle(color: s.textPrimary, fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: poster.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: poster,
                      width: 54,
                      height: 78,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(width: 54, height: 78, color: s.surfaceLight),
                      errorWidget: (_, __, ___) => Container(width: 54, height: 78, color: s.surfaceLight, child: const Icon(Icons.broken_image_rounded, size: 16, color: Colors.white24)),
                    )
                  : Container(width: 54, height: 78, color: s.surface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearches(bool isAr) {
    final s = AppSettings.instance;
    if (_recentSearches.isEmpty) {
      return Center(
        child: Text(
          isAr ? 'ابدأ بكتابة اسم العمل للبحث الفوري' : 'Type title to start search',
          style: TextStyle(color: s.textSecondary, fontSize: 12),
        ),
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(isAr ? 'عمليات البحث الأخيرة' : 'Recent Searches', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await LocalStorageService.setList('recent_search_history', []);
                _loadRecents();
              },
              child: Text(isAr ? 'مسح السجل' : 'Clear History', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._recentSearches.map<Widget>((it) => _buildMediaSearchRow(it, isAr)).toList(),
      ],
    );
  }
}

class MediaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> media;
  const MediaDetailScreen({super.key, required this.media});

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  Map<int, List<dynamic>> _seasonsMap = {};
  int _selectedSeason = 1;
  Set<String> _watchedEpisodes = {};
  bool _isSeries = false;
  bool _isWatchlist = false;
  bool _isSubscribed = false;
  Map<String, dynamic> _extendedInfo = {};
  List<dynamic> _similarMedia = [];
  List<String> _realActors = [];

  @override
  void initState() {
    super.initState();
    _isSeries = (widget.media['is_series_fixed'] == true) || (widget.media['season'] != null && widget.media['season'].toString() != '0');
    _loadState();
    _loadFullData();
    _loadSimilar();
    if (_isSeries) _loadEpisodes();
  }

  void _triggerCloudCensorSync() {
    final mediaId = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    
    String titleForSlug = (_extendedInfo['en_title'] ?? widget.media['en_title'] ?? '').toString().trim();
    if (titleForSlug.isEmpty) {
      titleForSlug = (_extendedInfo['ar_title'] ?? widget.media['ar_title'] ?? '').toString().trim();
    }

    titleForSlug = titleForSlug
        .replaceAll(RegExp(r'\(\d{4}\)|\b\d{4}\b'), '')
        .replaceAll(RegExp(r'[\-_:\.\(\)\[\]]'), ' ')
        .trim();

    final imdbId = (_extendedInfo['imdb_id'] ?? 
                    _extendedInfo['imdb'] ?? 
                    widget.media['imdb_id'] ?? 
                    widget.media['imdb'])?.toString();

    if (mediaId.isNotEmpty && titleForSlug.isNotEmpty) {
      ContentFilterEngine.triggerBackendScan(
        mediaId: mediaId,
        titleEn: titleForSlug,
        imdbId: imdbId,
      );
    }
  }

  void _loadState() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final watched = await LocalStorageService.getWatchedEpisodes();
    final wl = await LocalStorageService.isWatchlist(id);
    final sub = await LocalStorageService.isSubscribed(id);
    if (mounted) {
      setState(() {
        _watchedEpisodes = watched;
        _isWatchlist = wl;
        _isSubscribed = sub;
      });
    }
  }

  void _loadFullData() async {
    final id = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final info = await StreamService.getVideoExtendedInfo(id);

    List<String> actorsList = [];
    final rawActors = info['actors'] ?? info['cast'] ?? widget.media['actors'] ?? widget.media['cast'];
    if (rawActors is List) {
      actorsList = rawActors.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else if (rawActors is String && rawActors.isNotEmpty) {
      actorsList = rawActors.split(RegExp(r'[,،\|]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    if (mounted) {
      setState(() {
        _extendedInfo = info;
        _realActors = actorsList;
      });

      _triggerCloudCensorSync();
    }
  }

  void _loadSimilar() async {
    final level = AppSettings.instance.appFilterMode;
    final res = await StreamService.fetchFeed(isSeries: _isSeries, page: 0, perPage: 12, level: level);
    final currentId = (widget.media['nb'] ?? widget.media['id'])?.toString();
    if (mounted) {
      setState(() {
        _similarMedia = res.where((it) => (it['nb'] ?? it['id'])?.toString() != currentId).take(8).toList();
      });
    }
  }

  void _loadEpisodes() async {
    final seriesId = (widget.media['nb'] ?? widget.media['id'])?.toString() ?? '';
    final eps = await StreamService.getSeriesEpisodes(seriesId);

    final Map<int, List<dynamic>> rawSeasons = {};
    for (var ep in eps) {
      final sNum = int.tryParse(ep['season']?.toString() ?? '1') ?? 1;
      rawSeasons.putIfAbsent(sNum, () => []).add(ep);
    }

    final sortedKeys = rawSeasons.keys.toList()..sort((a, b) => a.compareTo(b));
    final Map<int, List<dynamic>> sortedSeasons = {};
    for (var k in sortedKeys) {
      final epList = rawSeasons[k]!;
      epList.sort((a, b) {
        final aNum = int.tryParse((a['episode_number'] ?? a['episode'] ?? '0').toString()) ?? 0;
        final bNum = int.tryParse((b['episode_number'] ?? b['episode'] ?? '0').toString()) ?? 0;
        return aNum.compareTo(bNum);
      });
      sortedSeasons[k] = epList;
    }

    if (mounted) {
      setState(() {
        _seasonsMap = sortedSeasons.isNotEmpty ? sortedSeasons : {1: eps};
        _selectedSeason = _seasonsMap.keys.first;
      });
    }
  }

  void _shareMedia(bool isAr) async {
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final id = widget.media['nb'] ?? widget.media['id'] ?? '';
    final text = isAr ? 'شاهد $title بجودة عالية عبر ONEBR TV!\nhttps://onebr.tv/watch/$id' : 'Watch $title in HD on ONEBR TV!\nhttps://onebr.tv/watch/$id';
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'تم نسخ رابط العمل بنجاح' : 'Link copied to clipboard')));
      }
    }
  }

  void _playTrailer(bool isAr) {
    final trailer = _extendedInfo['trailer']?.toString() ?? widget.media['trailer']?.toString() ?? '';
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    if (trailer.isNotEmpty && trailer.startsWith('http')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: 'trailer',
            title: isAr ? 'الإعلان: $title' : 'Trailer: $title',
            videoUrl: trailer,
            qualities: const [],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'الإعلان الترويجي الرسمي غير متوفر لهذا العمل' : 'Official trailer not available')));
    }
  }

  void _playEpisode(dynamic ep, int idx, bool isAr) {
    final targetId = (ep['nb'] ?? ep['id']).toString();
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final poster = StreamService.extractPoster(widget.media);
    final titleEn = widget.media['en_title']?.toString() ?? '';
    final imdbId = widget.media['imdb_id']?.toString() ?? widget.media['imdb']?.toString();

    LocalStorageService.markEpisodeWatched(targetId);
    _loadState();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: targetId,
          title: title,
          subtitleTextHeader: isAr ? 'الموسم $_selectedSeason - الحلقة $idx' : 'Season $_selectedSeason - Episode $idx',
          videoUrl: '',
          qualities: const [],
          episodes: _seasonsMap[_selectedSeason] ?? [],
          currentEpIndex: idx,
          poster: poster,
          titleEn: titleEn,
          imdbId: imdbId ?? '',
          onEpisodeChanged: (newId) {
            LocalStorageService.markEpisodeWatched(newId);
            _loadState();
          },
        ),
      ),
    );
  }

  void _playMovie(bool isAr) {
    final targetId = (widget.media['nb'] ?? widget.media['id']).toString();
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final poster = StreamService.extractPoster(widget.media);
    final titleEn = widget.media['en_title']?.toString() ?? '';
    final imdbId = widget.media['imdb_id']?.toString() ?? widget.media['imdb']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: targetId,
          title: title,
          videoUrl: '',
          qualities: const [],
          poster: poster,
          titleEn: titleEn,
          imdbId: imdbId ?? '',
        ),
      ),
    );
  }

  void _showDownloadQualityPicker(String targetId, String title, String poster, bool isAr) async {
    final s = AppSettings.instance;
    if (!RemoteAdminConfig.instance.allowDownloads) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAr ? 'التنزيل معطل مؤقتاً من قبل الإدارة' : 'Downloads are temporarily disabled')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: s.glassFill,
              child: FutureBuilder<Map<String, dynamic>?>(
                future: StreamService.getVideoSource(targetId),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    );
                  }
                  final qualities = snap.data?['qualities'] as List? ?? [];
                  if (qualities.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: Text(isAr ? 'لا تتوفر روابط تنزيل مباشرة' : 'No direct download links available', style: TextStyle(color: s.textSecondary))),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isAr ? 'اختر جودة التنزيل' : 'Select Download Quality', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ...qualities.map<Widget>((q) {
                          final res = q['resolution'] ?? '360p';
                          final url = q['url'] ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: s.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: s.border, width: 0.5),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.download_for_offline_rounded, color: AppColors.primary),
                              title: Text(isAr ? 'دقة $res' : '$res Resolution', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                              subtitle: Text(isAr ? 'تخزين خاص يُحذف مع إزالة التطبيق' : 'Private app storage', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                              trailing: const Icon(Icons.arrow_downward_rounded, color: Colors.white70),
                              onTap: () async {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);

                                final cleanId = targetId.replaceAll(RegExp(r'[^\w\.-]'), '_');
                                final safeFileName = '${cleanId}_$res.mp4';

                                final subInfo = await StreamService.getVideoExtendedInfo(targetId);
                                final subUrl = subInfo['arTranslationFilePath']?.toString() ?? '';

                                await BackgroundDownloadService.startDownload(
                                  url: url,
                                  fileName: safeFileName,
                                  targetId: targetId,
                                  title: '$title ($res)',
                                  poster: poster,
                                  subUrl: subUrl,
                                );

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(isAr ? 'بدأ التنزيل في خلفية النظام! راقب شريط الإشعارات' : 'Download started in background!')),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openActorWorks(String actorName) {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullCategoryView(
          title: actorName,
          searchQuery: actorName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final title = isAr ? (widget.media['ar_title'] ?? widget.media['en_title'] ?? '') : (widget.media['en_title'] ?? widget.media['ar_title'] ?? '');
    final poster = StreamService.extractPoster(widget.media, highRes: true);
    final story = isAr ? (_extendedInfo['ar_content'] ?? widget.media['ar_content'] ?? widget.media['en_content'] ?? '') : (_extendedInfo['en_content'] ?? widget.media['en_content'] ?? widget.media['ar_content'] ?? '');
    final score = (_extendedInfo['stars'] ?? widget.media['stars'] ?? '7.9').toString();
    final year = widget.media['year']?.toString() ?? '2024';
    final rateCount = (_extendedInfo['rate'] ?? widget.media['rate'] ?? '4818').toString();
    final currentEpisodes = _seasonsMap[_selectedSeason] ?? [];
    final id = (widget.media['nb'] ?? widget.media['id']).toString();
    final rawCats = widget.media['categories'];
    final List<dynamic> catList = rawCats is List ? rawCats : [];
    final sortedSeasonKeys = _seasonsMap.keys.toList()..sort((a, b) => a.compareTo(b));

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 460,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: () => _shareMedia(isAr)),
                if (_isSeries)
                  IconButton(
                    icon: Icon(_isSubscribed ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: _isSubscribed ? AppColors.primary : Colors.white),
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      await LocalStorageService.toggleSubscribed(id);
                      _loadState();
                    },
                  ),
                IconButton(
                  icon: Icon(_isWatchlist ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _isWatchlist ? AppColors.primary : Colors.white),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await LocalStorageService.toggleWatchlist(widget.media);
                    _loadState();
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: s.surface),
                        errorWidget: (_, __, ___) => Container(color: s.surface),
                      )
                    else
                      Container(color: s.surface),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.black87, s.bg],
                          stops: const [0.0, 0.4, 0.75, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12, left: 16, right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(AppRadius.chip)),
                                child: Text('IMDb $score', style: const TextStyle(color: AppColors.star, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Text('$year • ${_isSeries ? (isAr ? 'مسلسل' : 'Series') : (isAr ? 'فيلم' : 'Movie')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              InkWell(
                                onTap: () async {
                                  HapticFeedback.selectionClick();
                                  await LocalStorageService.toggleWatchlist(widget.media);
                                  _loadState();
                                },
                                child: Column(
                                  children: [
                                    Icon(_isWatchlist ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined, color: _isWatchlist ? AppColors.primary : Colors.white, size: 26),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isWatchlist ? (isAr ? 'في المفضلة' : 'Saved') : (isAr ? 'المفضلة' : 'Watchlist'),
                                      style: TextStyle(color: _isWatchlist ? AppColors.primary : Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              CupertinoButton(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppRadius.button),
                                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                                minSize: 0,
                                onPressed: () => _isSeries && currentEpisodes.isNotEmpty ? _playEpisode(currentEpisodes.first, 1, isAr) : _playMovie(isAr),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 4),
                                    Text(isAr ? 'شاهد الآن' : 'Watch Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              InkWell(
                                onTap: () => _showDownloadQualityPicker(id, title, poster, isAr),
                                child: Column(
                                  children: [
                                    const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 24),
                                    const SizedBox(height: 4),
                                    Text(isAr ? 'تحميل' : 'Download', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (catList.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: catList.map<Widget>((c) {
                          final name = isAr ? (c['ar_title'] ?? c['en_title'] ?? '') : (c['en_title'] ?? c['ar_title'] ?? '');
                          return Chip(
                            backgroundColor: s.surface,
                            side: BorderSide(color: s.border, width: 0.5),
                            label: Text(name.toString(), style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 14),

                    if (_realActors.isNotEmpty) ...[
                      Text(isAr ? 'طاقم التمثيل' : 'Cast', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _realActors.length,
                          itemBuilder: (ctx, i) {
                            final actor = _realActors[i];
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ActionChip(
                                backgroundColor: s.surface,
                                side: BorderSide(color: s.border, width: 0.5),
                                label: Text(actor, style: TextStyle(color: s.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                                onPressed: () => _openActorWorks(actor),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: s.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: s.border, width: 0.5),
                      ),
                      child: InkWell(
                        onTap: () => _playTrailer(isAr),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(isAr ? 'مشاهدة الإعلان الرسمي' : 'Watch Official Trailer', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(isAr ? 'تشغيل' : 'Play', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (story.isNotEmpty)
                      Text(story, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textSecondary, fontSize: 13, height: 1.6)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.thumb_up_rounded, color: s.textSecondary, size: 16),
                        const SizedBox(width: 4),
                        Text(rateCount, style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        const SizedBox(width: 16),
                        Icon(Icons.thumb_down_rounded, color: s.textSecondary, size: 16),
                        const SizedBox(width: 4),
                        Text('84', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                      ],
                    ),
                    Divider(color: s.border, height: 32),

                    if (_isSeries && _seasonsMap.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isAr ? 'الحلقات' : 'Episodes', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (sortedSeasonKeys.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: s.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: s.border, width: 0.5),
                              ),
                              child: DropdownButton<int>(
                                dropdownColor: s.surface,
                                value: _selectedSeason,
                                underline: const SizedBox(),
                                items: sortedSeasonKeys.map<DropdownMenuItem<int>>((season) => DropdownMenuItem(value: season, child: Text(isAr ? 'الموسم $season' : 'Season $season', style: TextStyle(color: s.textPrimary, fontSize: 12)))).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _selectedSeason = v;
                                    });
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: ValueKey<int>(_selectedSeason),
                        child: Column(
                          children: currentEpisodes.asMap().entries.map<Widget>((e) {
                            final ep = e.value;
                            final idx = e.key + 1;
                            final targetId = (ep['nb'] ?? ep['id']).toString();
                            final isWatched = _watchedEpisodes.contains(targetId);

                            return FocusBuilder(
                              builder: (context, hasFocus) => Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: hasFocus ? s.surfaceLight : s.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: hasFocus ? AppColors.primary : s.border,
                                    width: 2.0,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () => _playEpisode(ep, idx, isAr),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.download_rounded, color: s.textSecondary, size: 20),
                                          onPressed: () => _showDownloadQualityPicker(targetId, '$title - ${isAr ? "حلقة" : "Ep"} $idx', poster, isAr),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(isAr ? 'الحلقة $idx' : 'Episode $idx', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 4),
                                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textSecondary, fontSize: 11)),
                                              if (isWatched) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.visibility_rounded, color: Colors.greenAccent, size: 14),
                                                    const SizedBox(width: 4),
                                                    Text(isAr ? 'تمت المشاهدة' : 'Watched', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(AppRadius.chip),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                width: 110,
                                                height: 65,
                                                color: Colors.black26,
                                                child: poster.isNotEmpty
                                                    ? CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
                                                    : null,
                                              ),
                                              Container(
                                                width: 28, height: 28,
                                                decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
                                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    if (_similarMedia.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(isAr ? 'أعمال مقترحة ومشابهة' : 'Similar & Recommended', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 175,
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          itemCount: _similarMedia.length,
                          itemBuilder: (ctx, i) {
                            final it = _similarMedia[i];
                            final simPoster = StreamService.extractPoster(it);
                            final simTitle = isAr ? (it['ar_title'] ?? it['en_title'] ?? '') : (it['en_title'] ?? it['ar_title'] ?? '');

                            return Container(
                              width: 105,
                              margin: const EdgeInsets.only(left: 10),
                              child: FocusBuilder(
                                builder: (context, hasFocus) => InkWell(
                                  borderRadius: BorderRadius.circular(AppRadius.card),
                                  onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: it))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(AppRadius.card),
                                            border: Border.all(color: hasFocus ? AppColors.primary : Colors.transparent, width: 2),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(AppRadius.card),
                                            child: simPoster.isNotEmpty
                                                ? CachedNetworkImage(imageUrl: simPoster, fit: BoxFit.cover, width: double.infinity)
                                                : Container(color: s.surface),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(simTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String mediaId;
  final String title;
  final String subtitleTextHeader;
  final String videoUrl;
  final String subtitleUrl;
  final String secondarySubtitleUrl;
  final List<Map<String, dynamic>> qualities;
  final List<dynamic> episodes;
  final int currentEpIndex;
  final String poster;
  final String titleEn;
  final String imdbId;
  final Function(String)? onEpisodeChanged;
  final bool isLocalFile;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    this.subtitleTextHeader = '',
    required this.videoUrl,
    this.subtitleUrl = '',
    this.secondarySubtitleUrl = '',
    required this.qualities,
    this.episodes = const [],
    this.currentEpIndex = 1,
    this.poster = '',
    this.titleEn = '',
    this.imdbId = '',
    this.onEpisodeChanged,
    this.isLocalFile = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _showControls = true;
  Timer? _hideTimer;

  final GlobalKey _repaintBoundaryKey = GlobalKey();
  Timer? _chromaScanTimer;
  int _consecutiveSkinHits = 0;
  bool _isSeekingNow = false;

  bool _isAutoQuality = false;
  String _activeQuality = '360p';
  String _currentStreamUrl = '';
  List<Map<String, dynamic>> _currentQualities = [];

  BoxFit _videoFit = BoxFit.contain;
  bool _isLandscape = true;
  double _playbackSpeed = 1.0;

  List<Subtitle> _subtitles = [];
  List<Subtitle> _secondarySubtitles = [];
  String _currentSubText = '';
  String _currentSecondarySubText = '';

  late int _activeEpIndex;
  late String _activeMediaId;
  late String _activeHeader;
  Set<String> _watchedSet = {};

  bool _isLocked = false;
  Timer? _sleepTimer;
  int? _sleepMinutesRemaining;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showIndicator = false;
  String _indicatorText = '';
  IconData _indicatorIcon = Icons.volume_up_rounded;

  bool _showDoubleTapRipple = false;
  bool _isDoubleTapForward = true;
  int _doubleTapAccumulatedSeconds = 0;
  Timer? _doubleTapTimer;

  bool _showAutoNext = false;
  int _autoNextCountdown = 5;
  Timer? _autoNextTimer;

  List<Map<String, int>> _sensitiveSegments = [];
  int _lastSkippedSecond = -1;
  int _subtitleOffsetSeconds = 0;
  String _externalSubtitlePath = '';

  double? _dragPositionMs;
  bool _isSeeking = false;

  bool get _showSmartSkip =>
      _controller != null &&
      _controller!.value.isInitialized &&
      _controller!.value.position.inSeconds < 95;

  @override
  void initState() {
    super.initState();
    _activeEpIndex = widget.currentEpIndex;
    _activeMediaId = widget.mediaId;
    _activeHeader = widget.subtitleTextHeader;
    _currentQualities = widget.qualities;
    _loadWatchedState();

    WakelockPlus.enable();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _loadLayeredTimestamps();

    if (widget.isLocalFile && widget.videoUrl.isNotEmpty) {
      _initPlayer(widget.videoUrl, isLocal: true);
      if (widget.subtitleUrl.isNotEmpty) {
        _loadSubs(widget.subtitleUrl, isSecondary: false);
      }
    } else if (widget.videoUrl.isEmpty) {
      _loadAndPlayMedia(_activeMediaId);
    } else {
      _currentStreamUrl = widget.videoUrl;
      _initPlayer(widget.videoUrl);
      _loadSubtitlesPipeline(widget.subtitleUrl, widget.secondarySubtitleUrl);
    }
  }

  void _loadLayeredTimestamps() async {
    final ceeSegs = await StreamService.fetchCeeSkippingDurations(_activeMediaId);
    if (ceeSegs.isNotEmpty && mounted) {
      setState(() {
        _sensitiveSegments.addAll(ceeSegs);
      });
      return;
    }

    final cloudSegs = await ContentFilterEngine.fetchCloudTimestamps(_activeMediaId);
    if (cloudSegs.isNotEmpty && mounted) {
      setState(() {
        _sensitiveSegments.addAll(cloudSegs);
      });
    } else if (widget.titleEn.isNotEmpty) {
      ContentFilterEngine.triggerBackendScan(
        mediaId: _activeMediaId,
        titleEn: widget.titleEn,
        imdbId: widget.imdbId,
      );

      Future.delayed(const Duration(seconds: 4), () async {
        if (mounted && _sensitiveSegments.isEmpty) {
          final delayedSegs = await ContentFilterEngine.fetchCloudTimestamps(_activeMediaId);
          if (delayedSegs.isNotEmpty && mounted) {
            setState(() {
              _sensitiveSegments.addAll(delayedSegs);
            });
          }
        }
      });
    }
  }

  void _loadWatchedState() async {
    final w = await LocalStorageService.getWatchedEpisodes();
    if (mounted) setState(() => _watchedSet = w);
  }

  void _loadAndPlayMedia(String id) async {
    final futures = await Future.wait([
      StreamService.getVideoSource(id),
      StreamService.getVideoExtendedInfo(id),
    ]);

    final source = futures[0];
    final subInfo = futures[1];
    Map<String, dynamic>? subtitleOverride;
    try {
      final overrideDoc = await FirebaseFirestore.instance.collection('subtitle_overrides').doc(id).get();
      if (overrideDoc.exists) subtitleOverride = overrideDoc.data();
    } catch (_) {}

    if (source != null && mounted) {
      final qualitiesList = List<Map<String, dynamic>>.from(source['qualities'] ?? []);
      setState(() {
        _currentQualities = qualitiesList;
      });

      String targetUrl = source['video_url'] ?? '';
      final defaultQuality = RemoteAdminConfig.instance.defaultGlobalQuality;

      if (qualitiesList.isNotEmpty) {
        final preferred = qualitiesList.firstWhere(
          (q) => (q['resolution'] ?? '').toString().contains(defaultQuality),
          orElse: () => qualitiesList.first,
        );
        targetUrl = preferred['url'] ?? targetUrl;
        _activeQuality = preferred['resolution'] ?? defaultQuality;
      }

      _currentStreamUrl = targetUrl;
      _initPlayer(targetUrl);

      final subAr = subtitleOverride?['ar_url']?.toString().isNotEmpty == true
          ? subtitleOverride!['ar_url'].toString()
          : (subInfo?['arTranslationFilePath']?.toString() ?? '');
      final subEn = subtitleOverride?['en_url']?.toString().isNotEmpty == true
          ? subtitleOverride!['en_url'].toString()
          : (subInfo?['enTranslationFilePath']?.toString() ?? '');
      _subtitleOffsetSeconds = int.tryParse((subtitleOverride?['offset_seconds'] ?? 0).toString()) ?? 0;
      _loadSubtitlesPipeline(subAr, subEn);
    }
  }

  void _loadSubtitlesPipeline(String arUrl, String enUrl) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        if (arUrl.isNotEmpty) _loadSubs(arUrl, isSecondary: false);
        if (enUrl.isNotEmpty && AppSettings.instance.enableDualSubtitlesFlag) {
          _loadSubs(enUrl, isSecondary: true);
        }
        if (enUrl.isNotEmpty && AppSettings.instance.skipSensitiveScenes) {
          _inspectEnglishForCensorship(enUrl);
        }
      }
    });
  }

  void _inspectEnglishForCensorship(String enUrl) async {
    try {
      final res = await http.get(Uri.parse(enUrl), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 && mounted) {
        String decodedText;
        try {
          decodedText = utf8.decode(res.bodyBytes);
        } catch (_) {
          decodedText = latin1.decode(res.bodyBytes);
        }
        final parsedEn = _parseSrt(decodedText);
        final detected = ContentFilterEngine.parseSubtitles(parsedEn);
        if (detected.isNotEmpty && mounted) {
          setState(() {
            _sensitiveSegments.addAll(detected);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSubs(String url, {required bool isSecondary}) async {
    List<Subtitle> parsed = [];

    if (!url.startsWith('http')) {
      final file = File(url);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          parsed = _parseSrt(content);
          if (_subtitleOffsetSeconds != 0) parsed = _applySubtitleOffset(parsed, _subtitleOffsetSeconds);
        } catch (_) {}
      }
    } else {
      final cached = SubtitleCache.get(url);
      if (cached != null) {
        parsed = cached;
      } else {
        try {
          final res = await http.get(Uri.parse(url), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 12));
          if (res.statusCode == 200) {
            String decodedText;
            try {
              decodedText = utf8.decode(res.bodyBytes);
            } catch (_) {
              decodedText = latin1.decode(res.bodyBytes);
            }
            parsed = _parseSrt(decodedText);
            if (_subtitleOffsetSeconds != 0) parsed = _applySubtitleOffset(parsed, _subtitleOffsetSeconds);
            SubtitleCache.set(url, parsed);
          }
        } catch (_) {}
      }
    }

    if (mounted && parsed.isNotEmpty) {
      setState(() {
        if (isSecondary) {
          _secondarySubtitles = parsed;
        } else {
          _subtitles = parsed;
        }
      });

      if (AppSettings.instance.skipSensitiveScenes) {
        final detected = ContentFilterEngine.parseSubtitles(parsed);
        if (detected.isNotEmpty && mounted) {
          setState(() {
            _sensitiveSegments.addAll(detected);
          });
        }
      }
    }
  }

  List<Subtitle> _applySubtitleOffset(List<Subtitle> source, int offsetSeconds) {
    final delta = Duration(seconds: offsetSeconds);
    return source.map((s) {
      var start = s.start + delta;
      var end = s.end + delta;
      if (start < Duration.zero) start = Duration.zero;
      if (end < Duration.zero) end = Duration.zero;
      return Subtitle(index: s.index, start: start, end: end, text: s.text);
    }).where((s) => s.end > s.start).toList();
  }

  Future<void> _pickExternalSubtitle(bool isAr) async {
    if (!RemoteAdminConfig.instance.isFeatureEnabled('external_subtitles')) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt'],
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      _externalSubtitlePath = path;
      _subtitleOffsetSeconds = 0;
      await _loadSubs(path, isSecondary: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'تم استيراد ملف الترجمة بنجاح' : 'Subtitle imported successfully')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAr ? 'تعذر استيراد ملف الترجمة' : 'Could not import subtitle')));
    }
  }

  void _showSubtitleOffsetPicker(bool isAr) {
    var value = _subtitleOffsetSeconds.clamp(-10, 10);
    showCupertinoModalPopup(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) => CupertinoActionSheet(
        title: Text(isAr ? 'مزامنة الترجمة (-10 إلى +10 ثوانٍ)' : 'Subtitle sync (-10 to +10 seconds)'),
        message: Column(children: [
          Text('${value >= 0 ? '+' : ''}$value s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          CupertinoSlider(minimum: -10, maximum: 10, divisions: 20, value: value.toDouble(), onChanged: (v) => setLocal(() => value = v.round())),
        ]),
        actions: [
          CupertinoActionSheetAction(child: Text(isAr ? 'تطبيق' : 'Apply'), onPressed: () {
            Navigator.pop(ctx);
            final delta = value - _subtitleOffsetSeconds;
            setState(() => _subtitleOffsetSeconds = value);
            if (_subtitles.isNotEmpty && delta != 0) setState(() => _subtitles = _applySubtitleOffset(_subtitles, delta));
            if (_secondarySubtitles.isNotEmpty && delta != 0) setState(() => _secondarySubtitles = _applySubtitleOffset(_secondarySubtitles, delta));
          }),
        ],
      )),
    );
  }

  List<Subtitle> _parseSrt(String text) {
    final List<Subtitle> list = [];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.trim().split(RegExp(r'\n\s*\n+'));
    int idx = 0;

    for (var block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      int arrowLineIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          arrowLineIdx = i;
          break;
        }
      }
      if (arrowLineIdx == -1) continue;

      final timeParts = lines[arrowLineIdx].split('-->');
      if (timeParts.length != 2) continue;

      final start = _durationFromStr(timeParts[0]);
      final end = _durationFromStr(timeParts[1]);

      final textLines = lines.sublist(arrowLineIdx + 1);
      final rawText = textLines
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .trim();

      if (rawText.isNotEmpty && end > start) {
        list.add(Subtitle(index: idx++, start: start, end: end, text: rawText));
      }
    }

    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  Duration _durationFromStr(String str) {
    try {
      final clean = str.trim().replaceAll(',', '.');
      final parts = clean.split(':');
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final seconds = int.parse(secParts[0]);
      int ms = 0;
      if (secParts.length > 1) {
        String msStr = secParts[1];
        if (msStr.length > 3) {
          msStr = msStr.substring(0, 3);
        } else {
          msStr = msStr.padRight(3, '0');
        }
        ms = int.parse(msStr);
      }
      return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: ms);
    } catch (_) {
      return Duration.zero;
    }
  }

  void _initPlayer(String url, {Duration? startAt, bool isLocal = false}) async {
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    if (mounted) setState(() => _isReady = false);

    final ctrl = isLocal
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: StreamService.stealthHeaders,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
          );

    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.setPlaybackSpeed(_playbackSpeed);

    if (startAt != null) {
      await ctrl.seekTo(startAt);
    } else {
      final savedMs = await LocalStorageService.getPlaybackPosition(_activeMediaId);
      if (savedMs > 0 && savedMs < ctrl.value.duration.inMilliseconds - 5000) {
        await ctrl.seekTo(Duration(milliseconds: savedMs));
      }
    }

    ctrl.play();

    if (mounted) {
      setState(() => _isReady = true);
      _startChromaVisionInspector();
    }

    ctrl.addListener(_videoPlayerListener);
    _startTimer();
  }

  void _startChromaVisionInspector() {
    _chromaScanTimer?.cancel();
    _chromaScanTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!AppSettings.instance.skipSensitiveScenes ||
          _controller == null ||
          !_controller!.value.isPlaying ||
          _isSeekingNow) {
        return;
      }

      try {
        final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;

        final image = await boundary.toImage(pixelRatio: 0.04);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

        if (byteData != null) {
          final isSkinAnomaly = ChromaVisionEngine.analyzeFramePixels(byteData.buffer.asUint8List());

          if (isSkinAnomaly) {
            _consecutiveSkinHits++;
            if (_consecutiveSkinHits >= 3) {
              _triggerChromaEvasion();
            }
          } else {
            _consecutiveSkinHits = 0;
          }
        }
      } catch (_) {}
    });
  }

  void _triggerChromaEvasion() async {
    if (_controller == null || _isSeekingNow) return;
    _isSeekingNow = true;
    _consecutiveSkinHits = 0;

    final curSec = _controller!.value.position.inSeconds;
    final startSec = (curSec - 2).clamp(0, 999999);
    final endSec = curSec + 20;

    final target = Duration(seconds: endSec + 1);
    _controller!.seekTo(target > _controller!.value.duration ? _controller!.value.duration : target);
    HapticFeedback.heavyImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('تم رصد لقطة حساسة وتخطيها ذكياً عبر الرؤية البصرية 🛡️', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: AppColors.primaryDark,
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      await FirebaseFirestore.instance.collection('censored_scenes').doc(_activeMediaId).set({
        'scenes': FieldValue.arrayUnion([{'start': startSec, 'end': endSec}])
      }, SetOptions(merge: true));
    } catch (_) {}

    Future.delayed(const Duration(seconds: 3), () {
      _isSeekingNow = false;
    });
  }

  void _showReportDialog(bool isAr) {
    final reasonCtrl = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isAr ? 'الإبلاغ عن مشكلة ⚠️' : 'Report an Issue ⚠️'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isAr ? 'صف المشكلة (رابط تالف، لقطة لم تُحجب، ترجمة غير متطابقة)' : 'Describe problem (dead link, missed scene, subtitle issue)'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: reasonCtrl,
                placeholder: isAr ? 'تفاصيل البلاغ...' : 'Report details...',
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(child: Text(isAr ? 'إلغاء' : 'Cancel'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: Text(isAr ? 'إرسال' : 'Submit'),
            onPressed: () async {
              if (reasonCtrl.text.trim().isNotEmpty) {
                final pos = _controller?.value.position.inSeconds;
                await CloudSyncService.reportIssue(
                  mediaId: _activeMediaId,
                  title: widget.title,
                  reason: reasonCtrl.text.trim(),
                  positionSec: pos,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isAr ? 'تم إرسال بلاغك للإدارة بنجاح، شكراً لمساعدتك!' : 'Report sent successfully!')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _videoPlayerListener() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;

    if (pos.inSeconds % 5 == 0) {
      LocalStorageService.savePlaybackPosition(
        _activeMediaId,
        pos.inMilliseconds,
        dur.inMilliseconds,
        widget.title,
        widget.poster,
      );
    }

    if (AppSettings.instance.skipSensitiveScenes && _sensitiveSegments.isNotEmpty && !_isSeekingNow) {
      final currentSec = pos.inSeconds;
      for (var seg in _sensitiveSegments) {
        final start = seg['start']!;
        final end = seg['end']!;

        if (currentSec >= start && currentSec < end && _lastSkippedSecond != start) {
          _lastSkippedSecond = start;
          ctrl.seekTo(Duration(seconds: end + 1));
          HapticFeedback.heavyImpact();

          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('تم تجاوز لقطة غير لائقة تلقائياً 🛡️', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                backgroundColor: AppColors.primaryDark,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          break;
        }
      }
    }

    if (_subtitles.isNotEmpty) {
      String matchedText = '';
      for (var s in _subtitles) {
        if (pos >= s.start && pos <= s.end) {
          matchedText = s.text;
          break;
        }
        if (s.start > pos) break;
      }
      if (matchedText != _currentSubText && mounted) {
        setState(() => _currentSubText = matchedText);
      }
    }

    if (AppSettings.instance.enableDualSubtitlesFlag && _secondarySubtitles.isNotEmpty) {
      String matchedText2 = '';
      for (var s in _secondarySubtitles) {
        if (pos >= s.start && pos <= s.end) {
          matchedText2 = s.text;
          break;
        }
        if (s.start > pos) break;
      }
      if (matchedText2 != _currentSecondarySubText && mounted) {
        setState(() => _currentSecondarySubText = matchedText2);
      }
    }

    if (widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length) {
      final remaining = dur.inSeconds - pos.inSeconds;
      if (remaining <= 20 && remaining > 0 && !_showAutoNext) {
        _triggerAutoNext();
      }
    }
  }

  void _triggerAutoNext() {
    _showAutoNext = true;
    _autoNextCountdown = 5;
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_autoNextCountdown > 1) {
        if (mounted) setState(() => _autoNextCountdown--);
      } else {
        t.cancel();
        if (mounted && _showAutoNext) {
          _playNextEpisode();
        }
      }
    });
  }

  void _playNextEpisode() {
    _autoNextTimer?.cancel();
    setState(() => _showAutoNext = false);
    if (_activeEpIndex < widget.episodes.length) {
      final nextEp = widget.episodes[_activeEpIndex];
      _switchEpisode(nextEp, _activeEpIndex + 1);
    }
  }

  void _playPreviousEpisode() {
    _autoNextTimer?.cancel();
    setState(() => _showAutoNext = false);
    if (_activeEpIndex > 1) {
      final prevEp = widget.episodes[_activeEpIndex - 2];
      _switchEpisode(prevEp, _activeEpIndex - 1);
    }
  }

  void _switchEpisode(dynamic epData, int epIdx) async {
    final epId = (epData['nb'] ?? epData['id']).toString();
    setState(() {
      _isReady = false;
      _activeEpIndex = epIdx;
      _activeMediaId = epId;
      _activeHeader = AppSettings.instance.appLanguage == 'ar' ? 'الحلقة $epIdx' : 'Episode $epIdx';
      _showAutoNext = false;
      _subtitles.clear();
      _secondarySubtitles.clear();
      _sensitiveSegments.clear();
      _currentSubText = '';
      _currentSecondarySubText = '';
    });

    _loadLayeredTimestamps();

    final source = await StreamService.getVideoSource(epId);
    final sub = await StreamService.getVideoExtendedInfo(epId);

    await LocalStorageService.markEpisodeWatched(epId);
    widget.onEpisodeChanged?.call(epId);
    _loadWatchedState();

    if (source != null) {
      final qualitiesList = List<Map<String, dynamic>>.from(source['qualities'] ?? []);
      setState(() {
        _currentQualities = qualitiesList;
      });

      String targetUrl = source['video_url'] ?? '';
      final defaultQuality = RemoteAdminConfig.instance.defaultGlobalQuality;

      if (qualitiesList.isNotEmpty) {
        final preferred = qualitiesList.firstWhere(
          (q) => (q['resolution'] ?? '').toString().contains(defaultQuality),
          orElse: () => qualitiesList.first,
        );
        targetUrl = preferred['url'] ?? targetUrl;
        _activeQuality = preferred['resolution'] ?? defaultQuality;
      }

      _currentStreamUrl = targetUrl;
      _initPlayer(targetUrl);
      final path = sub['arTranslationFilePath']?.toString() ?? '';
      final pathEn = sub['enTranslationFilePath']?.toString() ?? '';
      _loadSubtitlesPipeline(path, pathEn);
    }
  }

  void _onDoubleTapSeek(bool isForward) {
    if (_isLocked || _controller == null || !_controller!.value.isInitialized) return;

    final seekStep = AppSettings.instance.seekDuration;
    HapticFeedback.lightImpact();

    setState(() {
      _isDoubleTapForward = isForward;
      _showDoubleTapRipple = true;
      if (_doubleTapTimer != null && _doubleTapTimer!.isActive) {
        _doubleTapAccumulatedSeconds += seekStep;
      } else {
        _doubleTapAccumulatedSeconds = seekStep;
      }
    });

    _doubleTapTimer?.cancel();

    _doubleTapTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _showDoubleTapRipple = false);

        final currentPos = _controller!.value.position;
        final newPos = isForward
            ? currentPos + Duration(seconds: _doubleTapAccumulatedSeconds)
            : currentPos - Duration(seconds: _doubleTapAccumulatedSeconds);

        _controller!.seekTo(newPos < Duration.zero
            ? Duration.zero
            : (newPos > _controller!.value.duration ? _controller!.value.duration : newPos));
      }
    });
  }

  void _toggleScreenOrientation() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  void _showEpisodesDrawer() {
    HapticFeedback.selectionClick();
    final isAr = AppSettings.instance.appLanguage == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: AppSettings.instance.glassFill,
              height: 350,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isAr ? 'قائمة الحلقات' : 'Episode List', style: TextStyle(color: AppSettings.instance.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.episodes.length,
                      itemBuilder: (ctx, i) {
                        final ep = widget.episodes[i];
                        final idx = i + 1;
                        final isCurrent = idx == _activeEpIndex;
                        return FocusBuilder(
                          builder: (context, hasFocus) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isCurrent ? AppColors.primary.withOpacity(0.3) : AppSettings.instance.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasFocus ? AppColors.primary : AppSettings.instance.border,
                                width: hasFocus ? 1.5 : 0.5,
                              ),
                            ),
                            child: ListTile(
                              title: Text(isAr ? 'الحلقة $idx' : 'Episode $idx', style: TextStyle(color: AppSettings.instance.textPrimary, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                              trailing: isCurrent ? const Icon(Icons.play_arrow_rounded, color: AppColors.primary) : null,
                              onTap: () {
                                Navigator.pop(context);
                                _switchEpisode(ep, idx);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _castToTv() async {
    final videoUrl = _currentStreamUrl.isNotEmpty ? _currentStreamUrl : (_controller?.dataSource ?? widget.videoUrl);
    if (videoUrl.isEmpty) return;

    ExternalPlayerService.playInExternalPlayer(
      videoUrl: videoUrl,
      title: widget.title,
      headers: StreamService.stealthHeaders,
    );
  }

  void _startTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying && !_isLocked && !_isSeeking) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _startTimer();
  }

  String _formatTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _chromaScanTimer?.cancel();
    WakelockPlus.disable();
    _autoNextTimer?.cancel();
    _hideTimer?.cancel();
    _doubleTapTimer?.cancel();
    _sleepTimer?.cancel();
    _controller?.removeListener(_videoPlayerListener);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _handleVerticalDrag(DragUpdateDetails details, BoxConstraints constraints) {
    if (_isLocked) return;
    final isRightSide = details.globalPosition.dx > constraints.maxWidth / 2;
    final delta = -details.primaryDelta! / constraints.maxHeight;

    setState(() {
      _showIndicator = true;
      if (isRightSide) {
        _volumeLevel = (_volumeLevel + delta).clamp(0.0, 1.0);
        _controller?.setVolume(_volumeLevel);
        _indicatorIcon = _volumeLevel == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded;
        _indicatorText = '${(_volumeLevel * 100).toInt()}%';
      } else {
        _brightnessLevel = (_brightnessLevel + delta).clamp(0.1, 1.0);
        _indicatorIcon = Icons.brightness_6_rounded;
        _indicatorText = '${(_brightnessLevel * 100).toInt()}%';
      }
    });

    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  void _openSettingsBottomSheet() {
    final settings = AppSettings.instance;
    final isAr = settings.appLanguage == 'ar';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: settings.glassFill,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.isLocalFile) ...[
                      ListTile(
                        leading: const Icon(Icons.open_in_new_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'فتح في مشغل خارجي (VLC / MX)' : 'Open in External Player', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.pop(context);
                          _castToTv();
                        },
                      ),
                      Divider(color: settings.border, height: 1),
                    ],
                    if (RemoteAdminConfig.instance.isFeatureEnabled('external_subtitles')) ...[
                      Divider(color: settings.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_open_rounded, color: AppColors.primary),
                        title: Text(AppLocalization.tr('external_subtitles', settings.appLanguage), style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        onTap: () { Navigator.pop(context); _pickExternalSubtitle(isAr); },
                      ),
                      Divider(color: settings.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.sync_rounded, color: AppColors.primary),
                        title: Text(AppLocalization.tr('subtitle_offset', settings.appLanguage), style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: Text('${_subtitleOffsetSeconds >= 0 ? '+' : ''}${_subtitleOffsetSeconds}s', style: TextStyle(color: settings.textSecondary)),
                        onTap: () { Navigator.pop(context); _showSubtitleOffsetPicker(isAr); },
                      ),
                    ],
                    ListTile(
                      leading: Icon(Icons.report_problem_rounded, color: Colors.amber),
                      title: Text(isAr ? 'الإبلاغ عن خلل في هذا العمل' : 'Report an issue with this media', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(context);
                        _showReportDialog(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.speed_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'سرعة التشغيل' : 'Playback Speed', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text('${_playbackSpeed}x', style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSpeedPicker(isAr);
                      },
                    ),
                    if (!widget.isLocalFile && _currentQualities.isNotEmpty) ...[
                      Divider(color: settings.border, height: 1),
                      ListTile(
                        leading: Icon(Icons.hd_rounded, color: settings.textSecondary),
                        title: Text(isAr ? 'دقة وجودة الفيديو' : 'Video Quality', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: Text(_isAutoQuality ? (isAr ? 'تلقائي (Auto)' : 'Auto') : _activeQuality, style: TextStyle(color: _isAutoQuality ? AppColors.primary : settings.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.pop(context);
                          _showQualityPicker(isAr);
                        },
                      ),
                    ],
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.timer_outlined, color: settings.textSecondary),
                      title: Text(isAr ? 'مؤقت النوم' : 'Sleep Timer', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_sleepMinutesRemaining != null ? '$_sleepMinutesRemaining min' : (isAr ? 'معطل' : 'Off'), style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSleepTimerPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.subtitles_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'الترجمة المزدوجة (عربي + إنجليزي)' : 'Dual Subtitles (AR + EN)', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.enableDualSubtitlesFlag,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateDualSubtitles(v)),
                      ),
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.shield_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'إزالة اللقطات الحساسة تلقائياً' : 'Auto Skip Sensitive Scenes', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: CupertinoSwitch(
                        value: settings.skipSensitiveScenes,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => settings.updateSkipScenes(v)),
                      ),
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.fast_forward_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'فترة تمرير الفيديو' : 'Seek Duration', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(isAr ? '${settings.seekDuration} ثوانٍ' : '${settings.seekDuration}s', style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showSeekPicker(isAr);
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.closed_caption_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'إعدادات ومكان الترجمة' : 'Subtitle Settings & Position', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: settings.textSecondary, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()));
                      },
                    ),
                    Divider(color: settings.border, height: 1),
                    ListTile(
                      leading: Icon(Icons.aspect_ratio_rounded, color: settings.textSecondary),
                      title: Text(isAr ? 'أبعاد الشاشة' : 'Aspect Ratio', style: TextStyle(color: settings.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      trailing: Text(_videoFit == BoxFit.cover ? (isAr ? 'ملء الشاشة' : 'Fit Screen') : (isAr ? 'طبيعي' : 'Original'), style: TextStyle(color: settings.textSecondary, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          _videoFit = _videoFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSeekPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'فترة التقديم والتأخير' : 'Seek Duration'),
        actions: [5, 10, 15, 30].map<Widget>((s) => CupertinoActionSheetAction(
          child: Text(isAr ? '$s ثوانٍ' : '${s}s'),
          onPressed: () {
            AppSettings.instance.updateSeek(s);
            Navigator.pop(context);
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showQualityPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'اختر دقة العرض' : 'Select Quality'),
        actions: [
          ..._currentQualities.map<Widget>((q) {
            final res = q['resolution'] ?? '360p';
            final url = q['url'] ?? '';
            final isSelected = !_isAutoQuality && _activeQuality == res;

            return CupertinoActionSheetAction(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(res),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                  ],
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isAutoQuality = false;
                  _activeQuality = res;
                });
                _currentStreamUrl = url;
                _initPlayer(url, startAt: _controller?.value.position);
              },
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showSpeedPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'سرعة التشغيل' : 'Playback Speed'),
        actions: [0.75, 1.0, 1.25, 1.5, 2.0].map<Widget>((s) => CupertinoActionSheetAction(
          child: Text('${s}x'),
          onPressed: () {
            setState(() => _playbackSpeed = s);
            _controller?.setPlaybackSpeed(s);
            Navigator.pop(context);
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
      ),
    );
  }

  void _showSleepTimerPicker(bool isAr) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(isAr ? 'إيقاف بعد وقت محدد' : 'Sleep Timer'),
        actions: [15, 30, 45, 60].map<Widget>((mins) => CupertinoActionSheetAction(
          child: Text(isAr ? '$mins دقيقة' : '$mins minutes'),
          onPressed: () {
            Navigator.pop(context);
            _sleepTimer?.cancel();
            setState(() => _sleepMinutesRemaining = mins);
            _sleepTimer = Timer(Duration(minutes: mins), () {
              _controller?.pause();
              if (mounted) Navigator.pop(context);
            });
          },
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () {
            _sleepTimer?.cancel();
            setState(() => _sleepMinutesRemaining = null);
            Navigator.pop(context);
          },
          child: Text(isAr ? 'إلغاء المؤقت' : 'Turn Off'),
        ),
      ),
    );
  }

  String _ffmpegQuote(String value) {
    // FFmpegKit receives one command string, so quote paths/URLs safely.
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<void> _takeSceneClip(bool isAr) async {
    if (!RemoteAdminConfig.instance.isFeatureEnabled('clip_share')) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final durationSec = duration.inSeconds;
    if (durationSec <= 0) return;

    var clipLength = 10;
    int start = (controller.value.position - const Duration(seconds: 5))
        .inSeconds
        .clamp(0, durationSec)
        .toInt();

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final int maxStart = (durationSec - clipLength).clamp(0, durationSec).toInt();
          start = start.clamp(0, maxStart).toInt();
          final sliderMax = maxStart > 0 ? maxStart.toDouble() : 1.0;

          return AlertDialog(
            backgroundColor: AppSettings.instance.surface,
            title: Text(
              AppLocalization.tr('clip_share', AppSettings.instance.appLanguage),
              style: TextStyle(
                color: AppSettings.instance.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [5, 10, 15, 30]
                      .where((v) => v <= durationSec)
                      .map(
                        (v) => ChoiceChip(
                          label: Text('$v s'),
                          selected: clipLength == v,
                          onSelected: (_) => setLocal(() {
                            clipLength = v;
                            start = start
                                .clamp(0, (durationSec - v).clamp(0, durationSec))
                                .toInt();
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  '${isAr ? 'البداية' : 'Start'}: ${_formatTime(Duration(seconds: start))}',
                  style: TextStyle(color: AppSettings.instance.textSecondary),
                ),
                Slider(
                  min: 0,
                  max: sliderMax,
                  value: start.toDouble().clamp(0, sliderMax),
                  onChanged: maxStart == 0
                      ? null
                      : (v) => setLocal(() => start = v.round()),
                ),
                Text(
                  '${isAr ? 'النهاية' : 'End'}: ${_formatTime(Duration(seconds: (start + clipLength).clamp(0, durationSec).toInt()))}',
                  style: TextStyle(color: AppSettings.instance.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isAr ? 'إلغاء' : 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'start': start,
                  'end': (start + clipLength).clamp(0, durationSec).toInt(),
                }),
                child: Text(isAr ? 'قص ومشاركة' : 'Trim & Share'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    final startSec = result['start']!;
    final endSec = result['end']!;
    final clipSeconds = endSec - startSec;
    if (clipSeconds <= 0) return;

    // Do not attempt to export an empty/invalid stream.
    final inputUrl = _currentStreamUrl.isNotEmpty
        ? _currentStreamUrl
        : (controller.dataSource.isNotEmpty ? controller.dataSource : widget.videoUrl);
    if (inputUrl.isEmpty) return;

    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/onebr_short_${DateTime.now().millisecondsSinceEpoch}.mp4';

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: AppSettings.instance.surface,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 18),
                Text(
                  isAr ? 'جارٍ قص الفيديو...' : 'Trimming video...',
                  style: TextStyle(color: AppSettings.instance.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  '$clipSeconds ${isAr ? 'ثانية' : 'seconds'}',
                  style: TextStyle(color: AppSettings.instance.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final input = _ffmpegQuote(inputUrl);
      final output = _ffmpegQuote(outputPath);

      // Copy the bundled transparent ONEBR TV watermark to a real file so
      // FFmpegKit can use it as a second input.
      final logoPath = '${dir.path}/onebr_watermark.png';
      final logoData = await rootBundle.load('assets/onebr_watermark.png');
      await File(logoPath).writeAsBytes(logoData.buffer.asUint8List(), flush: true);
      final logo = _ffmpegQuote(logoPath);

      final ffmpegHeaders = !widget.isLocalFile && StreamService.stealthHeaders.isNotEmpty
          ? StreamService.stealthHeaders.entries
              .map((e) => '${e.key}: ${e.value}\r\n')
              .join()
          : '';

      // Re-encode to MP4 so this works even when the source is HLS/other
      // streaming media. This is a real video file, not a screenshot.
      final command = [
        '-y',
        '-ss',
        startSec.toString(),
        if (ffmpegHeaders.isNotEmpty) ...[
          '-headers',
          _ffmpegQuote(ffmpegHeaders),
        ],
        '-i',
        input,
        '-i',
        logo,
        '-t',
        clipSeconds.toString(),
        '-filter_complex',
        '[1:v]scale=iw*0.16:-1[wm];[0:v][wm]overlay=W-w-24:24:format=auto[vout]',
        '-map',
        '[vout]',
        '-map',
        '0:a:0?',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-shortest',
        '-movflags',
        '+faststart',
        output,
      ].join(' ');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      try {
        await File(logoPath).delete();
      } catch (_) {}

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (ReturnCode.isSuccess(returnCode) && await File(outputPath).exists()) {
        final shareUrl = 'https://onebr.tv/short?media=${Uri.encodeComponent(_activeMediaId)}&start=$startSec&end=$endSec';
        await Share.shareXFiles(
          [XFile(outputPath, mimeType: 'video/mp4', name: 'ONEBR_Short.mp4')],
          text: '${widget.title}\n${isAr ? 'مقطع' : 'Short'} $startSec-$endSec s\n$shareUrl',
        );
        HapticFeedback.mediumImpact();
      } else {
        final logs = await session.getOutput() ?? '';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAr
                    ? 'تعذر قص الفيديو. تأكد من أن رابط البث قابل للقراءة.'
                    : 'Could not trim the video. Check that the stream URL is readable.',
              ),
            ),
          );
          debugPrint('FFmpeg clip failed: $logs');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'حدث خطأ أثناء قص الفيديو' : 'Video trimming failed'),
          ),
        );
      }
      debugPrint('Clip error: $e');
    }
  }

  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      if (_controller != null) {
        setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play());
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _onDoubleTapSeek(true);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _onDoubleTapSeek(false);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
               event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final isAr = settings.appLanguage == 'ar';
    final hasPrev = widget.episodes.isNotEmpty && _activeEpIndex > 1;
    final hasNext = widget.episodes.isNotEmpty && _activeEpIndex < widget.episodes.length;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleRemoteKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: (_isReady && _controller != null)
                        ? RepaintBoundary(
                            key: _repaintBoundaryKey,
                            child: AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  FittedBox(
                                    fit: _videoFit,
                                    child: SizedBox(
                                      width: _controller!.value.size.width,
                                      height: _controller!.value.size.height,
                                      child: VideoPlayer(_controller!),
                                    ),
                                  ),

                                  // ONEBR TV watermark shown while watching.
                                  Positioned(
                                    top: 18,
                                    right: 18,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: 0.78,
                                        child: Image.asset(
                                          'assets/onebr_watermark.png',
                                          width: 72,
                                          height: 52,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (_currentSubText.isNotEmpty)
                                    Positioned(
                                      bottom: settings.subBottomPadding,
                                      left: 20.0,
                                      right: 20.0,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: settings.subtitleBackgroundColor,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _currentSubText,
                                            textAlign: TextAlign.center,
                                            textDirection: TextDirection.rtl,
                                            style: TextStyle(
                                              color: settings.subColor,
                                              fontSize: settings.subFontSize,
                                              fontWeight: FontWeight.bold,
                                              shadows: settings.subHasShadow
                                                  ? const [Shadow(blurRadius: 8, color: Colors.black, offset: Offset(1, 1))]
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : const CircularProgressIndicator(color: AppColors.primary),
                  ),

                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _onDoubleTapSeek(false),
                            onVerticalDragUpdate: (d) => _handleVerticalDrag(d, constraints),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _onDoubleTapSeek(true),
                            onVerticalDragUpdate: (d) => _handleVerticalDrag(d, constraints),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_showDoubleTapRipple)
                    Align(
                      alignment: _isDoubleTapForward ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * 0.38,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: _isDoubleTapForward
                              ? const BorderRadius.horizontal(left: Radius.circular(100))
                              : const BorderRadius.horizontal(right: Radius.circular(100)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isDoubleTapForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, size: 40, color: Colors.white),
                            const SizedBox(height: 6),
                            Text('${_doubleTapAccumulatedSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (_showIndicator)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_indicatorIcon, color: Colors.white, size: 28),
                            const SizedBox(width: 10),
                            Text(_indicatorText, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (settings.enableDualSubtitlesFlag && _currentSecondarySubText.isNotEmpty)
                    Positioned(
                      top: 70, left: 20, right: 20,
                      child: Center(
                        child: Text(
                          _currentSecondarySubText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                        ),
                      ),
                    ),

                  if (_showAutoNext && hasNext && !_isLocked)
                    Positioned(
                      bottom: 85, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24, width: 0.5)),
                        child: Row(
                          children: [
                            Text(isAr ? 'الحلقة التالية خلال $_autoNextCountdown ث' : 'Next episode in $_autoNextCountdown s', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              color: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minSize: 0,
                              onPressed: _playNextEpisode,
                              child: Text(isAr ? 'تشغيل الآن' : 'Play Now', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_showControls)
                    Positioned(
                      left: 16,
                      top: MediaQuery.of(context).size.height / 2 - 20,
                      child: IconButton(
                        icon: Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: _isLocked ? AppColors.primary : Colors.white, size: 26),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isLocked = !_isLocked);
                        },
                      ),
                    ),

                  if (_showControls && !_isLocked) ...[
                    Positioned(
                      top: 10, left: 14, right: 14,
                      child: Directionality(
                        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                  if (_activeHeader.isNotEmpty)
                                    Text(_activeHeader, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                if (widget.episodes.isNotEmpty)
                                  IconButton(
                                    tooltip: isAr ? 'قائمة الحلقات' : 'Episodes',
                                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 24),
                                    onPressed: _showEpisodesDrawer,
                                  ),
                                IconButton(
                                  tooltip: isAr ? 'صانع اللقطات' : 'Snapshot',
                                  icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
                                  onPressed: () => _takeSceneClip(isAr),
                                ),
                                if (!widget.isLocalFile)
                                  IconButton(
                                    tooltip: isAr ? 'مشغل خارجي' : 'External Player',
                                    icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                                    onPressed: _castToTv,
                                  ),
                                IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white), onPressed: _openSettingsBottomSheet),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.episodes.isNotEmpty)
                            IconButton(
                              iconSize: 32,
                              icon: Icon(Icons.skip_previous_rounded, color: hasPrev ? Colors.white : Colors.white24),
                              onPressed: hasPrev ? _playPreviousEpisode : null,
                            ),
                          const SizedBox(width: 10),
                          IconButton(
                            iconSize: 32,
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                            onPressed: () {
                              final p = _controller!.value.position - Duration(seconds: settings.seekDuration);
                              _controller!.seekTo(p < Duration.zero ? Duration.zero : p);
                            },
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 54,
                            icon: Icon(_controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                            onPressed: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 32,
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                            onPressed: () {
                              final p = _controller!.value.position + Duration(seconds: settings.seekDuration);
                              _controller!.seekTo(p);
                            },
                          ),
                          const SizedBox(width: 10),
                          if (widget.episodes.isNotEmpty)
                            IconButton(
                              iconSize: 32,
                              icon: Icon(Icons.skip_next_rounded, color: hasNext ? Colors.white : Colors.white24),
                              onPressed: hasNext ? _playNextEpisode : null,
                            ),
                        ],
                      ),
                    ),

                    if (_controller != null && _controller!.value.isInitialized)
                      Positioned(
                        bottom: 12, left: 16, right: 16,
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _controller!,
                          builder: (context, value, child) {
                            final totalMs = value.duration.inMilliseconds.toDouble();
                            final currentMs = _isSeeking
                                ? (_dragPositionMs ?? value.position.inMilliseconds.toDouble())
                                : value.position.inMilliseconds.toDouble();

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: _isSeeking ? 5 : 3,
                                    thumbShape: RoundSliderThumbShape(
                                      enabledThumbRadius: _isSeeking ? 8 : 5,
                                    ),
                                    thumbColor: AppColors.primary,
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: Colors.white24,
                                  ),
                                  child: Slider(
                                    value: currentMs.clamp(0.0, totalMs > 0 ? totalMs : 1.0),
                                    min: 0.0,
                                    max: totalMs > 0 ? totalMs : 1.0,
                                    onChangeStart: (v) {
                                      setState(() {
                                        _isSeeking = true;
                                        _dragPositionMs = v;
                                      });
                                    },
                                    onChanged: (v) {
                                      setState(() {
                                        _dragPositionMs = v;
                                      });
                                    },
                                    onChangeEnd: (v) {
                                      _controller!.seekTo(Duration(milliseconds: v.toInt()));
                                      setState(() {
                                        _isSeeking = false;
                                        _dragPositionMs = null;
                                      });
                                      _startTimer();
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatTime(Duration(milliseconds: currentMs.toInt())),
                                        style: TextStyle(
                                          color: _isSeeking ? AppColors.primary : Colors.white,
                                          fontSize: 11,
                                          fontWeight: _isSeeking ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(_formatTime(value.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                          const SizedBox(width: 14),
                                          InkWell(
                                            onTap: _toggleScreenOrientation,
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.white24, width: 0.8),
                                              ),
                                              child: Icon(
                                                _isLandscape ? Icons.crop_portrait_rounded : Icons.crop_landscape_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  final _alertCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _minVerCtrl = TextEditingController();
  final _apkUrlCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  final _pinnedHeroesCtrl = TextEditingController();
  final _blacklistCtrl = TextEditingController();
  final _popupTitleCtrl = TextEditingController();
  final _popupBodyCtrl = TextEditingController();
  final _popupUrlCtrl = TextEditingController();

  final _socialTelegramCtrl = TextEditingController();
  final _socialWhatsappCtrl = TextEditingController();
  final _socialInstagramCtrl = TextEditingController();
  final _socialFacebookCtrl = TextEditingController();
  final _socialWebsiteCtrl = TextEditingController();
  final _banValueCtrl = TextEditingController();
  final _banReasonCtrl = TextEditingController();
  final _requestFilterCtrl = TextEditingController();
  final _subtitleAdminMediaCtrl = TextEditingController();
  final _subtitleAdminArCtrl = TextEditingController();
  final _subtitleAdminEnCtrl = TextEditingController();
  final _subtitleAdminOffsetCtrl = TextEditingController();
  final _iptvNameCtrl = TextEditingController();
  final _iptvUrlCtrl = TextEditingController();
  final _iptvCategoryCtrl = TextEditingController();

  bool _flagClipShare = true;
  bool _flagExternalSubtitles = true;
  bool _flagSocialLinks = true;
  bool _flagContentRequests = true;
  bool _flagSubtitleManager = true;
  bool _flagDeviceBan = true;
  bool _flagIptvManager = true;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _iptvAdminChannels = [];

  bool _maintenance = false;
  bool _censorActive = true;
  bool _allowDownloads = true;
  String _selectedDefaultQuality = '360p';

  final _mediaIdCtrl = TextEditingController();
  final _startSecCtrl = TextEditingController();
  final _endSecCtrl = TextEditingController();
  List<Map<String, dynamic>> _loadedScenesForMedia = [];
  bool _isSearchingScenes = false;

  int _totalUsersCount = 0;
  int _totalCensoredDocsCount = 0;
  int _totalReportsCount = 0;
  bool _isLoadingStats = true;

  Map<String, int> _serverLatencies = {
    'Cee Stream Primary': -1,
    'Censor Engine API': -1,
    'Firestore Database': -1,
  };
  bool _isTestingPing = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _loadCurrentConfig();
    _loadCloudStats();
    _testServerPings();
    _loadAdvancedData();
  }

  void _loadCurrentConfig() async {
    final doc = await FirebaseFirestore.instance.collection('app_config').doc('global_settings').get();
    if (doc.exists && doc.data() != null) {
      final d = doc.data()!;
      setState(() {
        _maintenance = d['is_maintenance'] ?? false;
        _censorActive = d['censor_enabled'] ?? true;
        _allowDownloads = d['allow_downloads'] ?? true;
        _selectedDefaultQuality = d['default_quality'] ?? '360p';
        _alertCtrl.text = d['global_alert'] ?? '';
        _msgCtrl.text = d['maintenance_msg'] ?? '';
        _minVerCtrl.text = (d['min_version'] ?? 1).toString();
        _apkUrlCtrl.text = d['update_url'] ?? '';
        _customUrlCtrl.text = d['custom_base_url'] ?? '';
        _popupTitleCtrl.text = d['popup_title'] ?? '';
        _popupBodyCtrl.text = d['popup_body'] ?? '';
        _popupUrlCtrl.text = d['popup_action_url'] ?? '';
        final flags = Map<String, dynamic>.from(d['feature_flags'] is Map ? d['feature_flags'] : {});
        _flagClipShare = flags['clip_share'] ?? true;
        _flagExternalSubtitles = flags['external_subtitles'] ?? true;
        _flagSocialLinks = flags['social_links'] ?? true;
        _flagContentRequests = flags['content_requests'] ?? true;
        _flagSubtitleManager = flags['subtitle_manager'] ?? true;
        _flagDeviceBan = flags['device_ban'] ?? true;
        _flagIptvManager = flags['iptv_manager'] ?? true;
        final socials = Map<String, dynamic>.from(d['social_links'] is Map ? d['social_links'] : {});
        _socialTelegramCtrl.text = socials['telegram']?.toString() ?? '';
        _socialWhatsappCtrl.text = socials['whatsapp']?.toString() ?? '';
        _socialInstagramCtrl.text = socials['instagram']?.toString() ?? '';
        _socialFacebookCtrl.text = socials['facebook']?.toString() ?? '';
        _socialWebsiteCtrl.text = socials['website']?.toString() ?? '';

        if (d['pinned_hero_ids'] is List) {
          _pinnedHeroesCtrl.text = (d['pinned_hero_ids'] as List).join(',');
        }
        if (d['blacklisted_ids'] is List) {
          _blacklistCtrl.text = (d['blacklisted_ids'] as List).join(',');
        }
      });
    }
  }

  void _loadCloudStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').count().get();
      final censorSnap = await FirebaseFirestore.instance.collection('censored_scenes').count().get();
      final reportsSnap = await FirebaseFirestore.instance.collection('user_reports').count().get();

      if (mounted) {
        setState(() {
          _totalUsersCount = usersSnap.count ?? 0;
          _totalCensoredDocsCount = censorSnap.count ?? 0;
          _totalReportsCount = reportsSnap.count ?? 0;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  void _testServerPings() async {
    setState(() => _isTestingPing = true);
    final results = <String, int>{};

    final sw1 = Stopwatch()..start();
    try {
      await http.get(Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/1/level/0/videoKind/1/sortParam/desc/pageNumber/0'), headers: StreamService.stealthHeaders).timeout(const Duration(seconds: 5));
      sw1.stop();
      results['Cee Stream Primary'] = sw1.elapsedMilliseconds;
    } catch (_) {
      results['Cee Stream Primary'] = 9999;
    }

    final sw2 = Stopwatch()..start();
    try {
      await http.get(Uri.parse(ContentFilterEngine.serverBaseUrl)).timeout(const Duration(seconds: 5));
      sw2.stop();
      results['Censor Engine API'] = sw2.elapsedMilliseconds;
    } catch (_) {
      results['Censor Engine API'] = 9999;
    }

    final sw3 = Stopwatch()..start();
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('global_settings').get();
      sw3.stop();
      results['Firestore Database'] = sw3.elapsedMilliseconds;
    } catch (_) {
      results['Firestore Database'] = 9999;
    }

    if (mounted) {
      setState(() {
        _serverLatencies = results;
        _isTestingPing = false;
      });
    }
  }

  void _saveGlobalSettings() async {
    final pinnedList = _pinnedHeroesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final blackList = _blacklistCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    await FirebaseFirestore.instance.collection('app_config').doc('global_settings').set({
      'is_maintenance': _maintenance,
      'censor_enabled': _censorActive,
      'allow_downloads': _allowDownloads,
      'default_quality': _selectedDefaultQuality,
      'global_alert': _alertCtrl.text.trim(),
      'maintenance_msg': _msgCtrl.text.trim(),
      'min_version': int.tryParse(_minVerCtrl.text.trim()) ?? 1,
      'update_url': _apkUrlCtrl.text.trim(),
      'custom_base_url': _customUrlCtrl.text.trim(),
      'pinned_hero_ids': pinnedList,
      'blacklisted_ids': blackList,
      'popup_title': _popupTitleCtrl.text.trim(),
      'popup_body': _popupBodyCtrl.text.trim(),
      'popup_action_url': _popupUrlCtrl.text.trim(),
      'feature_flags': {
        'clip_share': _flagClipShare,
        'external_subtitles': _flagExternalSubtitles,
        'social_links': _flagSocialLinks,
        'content_requests': _flagContentRequests,
        'subtitle_manager': _flagSubtitleManager,
        'device_ban': _flagDeviceBan,
        'iptv_manager': _flagIptvManager,
      },
      'social_links': {
        'telegram': _socialTelegramCtrl.text.trim(),
        'whatsapp': _socialWhatsappCtrl.text.trim(),
        'instagram': _socialInstagramCtrl.text.trim(),
        'facebook': _socialFacebookCtrl.text.trim(),
        'website': _socialWebsiteCtrl.text.trim(),
      },
      'last_admin_update': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر كافة التعديلات والإعدادات السحابية لكل المستخدمين! ✅')),
      );
    }
  }

  void _fetchScenesForCurrentMedia() async {
    final id = _mediaIdCtrl.text.trim();
    if (id.isEmpty) return;

    setState(() => _isSearchingScenes = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('censored_scenes').doc(id).get();
      if (doc.exists && doc.data()?['scenes'] != null) {
        final List raw = doc.data()!['scenes'];
        setState(() {
          _loadedScenesForMedia = List<Map<String, dynamic>>.from(raw);
          _isSearchingScenes = false;
        });
      } else {
        setState(() {
          _loadedScenesForMedia = [];
          _isSearchingScenes = false;
        });
      }
    } catch (_) {
      setState(() => _isSearchingScenes = false);
    }
  }

  void _addCustomCensorScene() async {
    final id = _mediaIdCtrl.text.trim();
    final start = int.tryParse(_startSecCtrl.text.trim());
    final end = int.tryParse(_endSecCtrl.text.trim());

    if (id.isEmpty || start == null || end == null) return;

    await FirebaseFirestore.instance.collection('censored_scenes').doc(id).set({
      'scenes': FieldValue.arrayUnion([{'start': start, 'end': end}])
    }, SetOptions(merge: true));

    _startSecCtrl.clear();
    _endSecCtrl.clear();
    _fetchScenesForCurrentMedia();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة المشهد الحساس للعمل $id وتثبيته في السحابة! 🛡️')),
      );
    }
  }

  void _deleteCensorScene(Map<String, dynamic> scene) async {
    final id = _mediaIdCtrl.text.trim();
    if (id.isEmpty) return;

    await FirebaseFirestore.instance.collection('censored_scenes').doc(id).update({
      'scenes': FieldValue.arrayRemove([scene])
    });

    _fetchScenesForCurrentMedia();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف اللقطة المحددة من قاعدة البيانات! 🗑️')),
      );
    }
  }


  Future<void> _loadAdvancedData() async {
    try {
      final req = await FirebaseFirestore.instance.collection('content_requests').orderBy('created_at', descending: true).limit(50).get();
      final iptv = await FirebaseFirestore.instance.collection('iptv_channels').orderBy('name').limit(100).get();
      if (mounted) setState(() {
        _requests = req.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _iptvAdminChannels = iptv.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {}
  }

  Future<void> _saveSubtitleOverride() async {
    final id = _subtitleAdminMediaCtrl.text.trim();
    if (id.isEmpty) return;
    await FirebaseFirestore.instance.collection('subtitle_overrides').doc(id).set({
      'ar_url': _subtitleAdminArCtrl.text.trim(),
      'en_url': _subtitleAdminEnCtrl.text.trim(),
      'offset_seconds': int.tryParse(_subtitleAdminOffsetCtrl.text.trim()) ?? 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعداد الترجمة السحابية')));
  }

  Future<void> _banValue({required bool device}) async {
    final value = _banValueCtrl.text.trim();
    if (value.isEmpty) return;
    final collection = device ? 'banned_devices' : 'banned_users';
    await FirebaseFirestore.instance.collection(collection).doc(device ? value : value.toLowerCase()).set({
      'active': true,
      'reason': _banReasonCtrl.text.trim(),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _banValueCtrl.clear();
    _banReasonCtrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(device ? 'تم حظر معرف الجهاز' : 'تم حظر البريد/المعرف')));
  }

  Future<void> _setRequestStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('content_requests').doc(id).update({'status': status, 'reviewed_at': FieldValue.serverTimestamp()});
    await _loadAdvancedData();
  }

  Future<void> _addIptvChannel() async {
    final name = _iptvNameCtrl.text.trim();
    final url = _iptvUrlCtrl.text.trim();
    final category = _iptvCategoryCtrl.text.trim().isEmpty ? 'General' : _iptvCategoryCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    await FirebaseFirestore.instance.collection('iptv_channels').add({'name': name, 'url': url, 'category': category, 'enabled': true, 'updated_at': FieldValue.serverTimestamp()});
    _iptvNameCtrl.clear(); _iptvUrlCtrl.clear(); _iptvCategoryCtrl.clear();
    await _loadAdvancedData();
  }

  Future<int> _pingUrl(String url) async {
    final sw = Stopwatch()..start();
    try { final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6)); sw.stop(); return r.statusCode >= 200 && r.statusCode < 500 ? sw.elapsedMilliseconds : 9999; } catch (_) { return 9999; }
  }

  Widget _advancedAdminTab(AppSettings s) {
    final flags = [
      ['مشاركة المقاطع', _flagClipShare, (bool v) => _flagClipShare = v],
      ['الترجمات الخارجية', _flagExternalSubtitles, (bool v) => _flagExternalSubtitles = v],
      ['حسابات التواصل', _flagSocialLinks, (bool v) => _flagSocialLinks = v],
      ['طلبات المستخدمين', _flagContentRequests, (bool v) => _flagContentRequests = v],
      ['مدير الترجمات السحابية', _flagSubtitleManager, (bool v) => _flagSubtitleManager = v],
      ['حظر الجهاز / البريد', _flagDeviceBan, (bool v) => _flagDeviceBan = v],
      ['مدير قنوات IPTV', _flagIptvManager, (bool v) => _flagIptvManager = v],
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      _adminCard(s, 'مفاتيح الميزات السحابية', Column(children: flags.map((f) => SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(f[0] as String), value: f[1] as bool, activeColor: AppColors.primary, onChanged: (v) => setState(() => (f[2] as Function(bool))(v)))).toList())),
      const SizedBox(height: 12),
      _adminCard(s, 'حسابات التطبيق الرسمية', Column(children: [
        _adminField(_socialTelegramCtrl, 'Telegram'), _adminField(_socialWhatsappCtrl, 'WhatsApp'), _adminField(_socialInstagramCtrl, 'Instagram'), _adminField(_socialFacebookCtrl, 'Facebook'), _adminField(_socialWebsiteCtrl, 'الموقع الرسمي'),
      ])),
      const SizedBox(height: 12),
      _adminCard(s, 'فحص الروابط المباشر', Column(children: [
        for (final entry in {'Telegram': _socialTelegramCtrl.text, 'WhatsApp': _socialWhatsappCtrl.text, 'Instagram': _socialInstagramCtrl.text, 'Facebook': _socialFacebookCtrl.text, 'Website': _socialWebsiteCtrl.text}.entries.where((e) => e.value.isNotEmpty))
          ListTile(title: Text(entry.key), subtitle: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: FutureBuilder<int>(future: _pingUrl(entry.value), builder: (_, snap) => Text(snap.connectionState == ConnectionState.done ? '${snap.data} ms' : '...'))),
      ])),
      const SizedBox(height: 12),
      _adminCard(s, 'مدير الترجمات السحابية', Column(children: [
        _adminField(_subtitleAdminMediaCtrl, 'Media ID'), _adminField(_subtitleAdminArCtrl, 'AR .srt URL'), _adminField(_subtitleAdminEnCtrl, 'EN .srt URL'), _adminField(_subtitleAdminOffsetCtrl, 'Offset seconds (-10..10)', number: true),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveSubtitleOverride, child: const Text('حفظ إعداد الترجمة'))),
      ])),
      const SizedBox(height: 12),
      _adminCard(s, 'حظر البريد أو الجهاز', Column(children: [
        _adminField(_banValueCtrl, 'Email أو Device ID'), _adminField(_banReasonCtrl, 'سبب الحظر'),
        Row(children: [Expanded(child: ElevatedButton(onPressed: () => _banValue(device: false), child: const Text('حظر البريد/UID'))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => _banValue(device: true), child: const Text('حظر الجهاز')))]),
      ])),
      const SizedBox(height: 12),
      _adminCard(s, 'طلبات المحتوى', Column(children: _requests.isEmpty ? [const Text('لا توجد طلبات محملة')] : _requests.map((r) => ListTile(title: Text('${r['title'] ?? ''}'), subtitle: Text('${r['type'] ?? 'media'} • ${r['status'] ?? 'pending'}'), trailing: PopupMenuButton<String>(onSelected: (v) => _setRequestStatus(r['id'].toString(), v), itemBuilder: (_) => const [PopupMenuItem(value: 'approved', child: Text('موافقة')), PopupMenuItem(value: 'rejected', child: Text('رفض')), PopupMenuItem(value: 'completed', child: Text('تم التنفيذ'))])).toList())),
      const SizedBox(height: 12),
      _adminCard(s, 'إدارة قنوات IPTV', Column(children: [
        _adminField(_iptvNameCtrl, 'اسم القناة'), _adminField(_iptvUrlCtrl, 'رابط البث'), _adminField(_iptvCategoryCtrl, 'التصنيف'),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addIptvChannel, child: const Text('إضافة القناة'))),
        ..._iptvAdminChannels.map((c) => ListTile(title: Text(c['name']?.toString() ?? ''), subtitle: Text('${c['category'] ?? ''} • ${c['url'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Icon(c['enabled'] == false ? Icons.pause_circle : Icons.play_circle, color: c['enabled'] == false ? Colors.orange : Colors.green))),
      ])),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () async { await _loadAdvancedData(); if (mounted) setState(() {}); }, icon: const Icon(Icons.refresh), label: const Text('تحديث لوحة الأمان'))),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveGlobalSettings, child: const Text('حفظ كل الإعدادات السحابية'))),
    ]);
  }

  Widget _adminCard(AppSettings s, String title, Widget child) => Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 2), decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 10), child]));
  Widget _adminField(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label)));

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: const Text('لوحة تحكم الأدمن - ONEBR Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: s.textSecondary,
            tabs: const [
              Tab(icon: Icon(Icons.settings_suggest_rounded, size: 20), text: 'التحكم العام'),
              Tab(icon: Icon(Icons.speed_rounded, size: 20), text: 'السيرفرات والشبكة'),
              Tab(icon: Icon(Icons.shield_rounded, size: 20), text: 'إدارة الحجب'),
              Tab(icon: Icon(Icons.analytics_rounded, size: 20), text: 'الإحصائيات'),
              Tab(icon: Icon(Icons.admin_panel_settings_rounded, size: 20), text: 'الأمان المتقدم'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('حالة السيرفر وقفل التطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('وضع الصيانة (قفل التطبيق عن الجميع)'),
                        subtitle: const Text('يمنع المستخدمين العاديين من الدخول أثناء التحديثات', style: TextStyle(fontSize: 11)),
                        value: _maintenance,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _maintenance = v),
                      ),
                      TextField(
                        controller: _msgCtrl,
                        decoration: const InputDecoration(labelText: 'رسالة الصيانة التي ستظهر للعامة'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('نظام الفلترة والحجب الذكي لجميع المستخدمين'),
                        value: _censorActive,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _censorActive = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('السماح للمستخدمين بتنزيل الفيديوهات'),
                        value: _allowDownloads,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _allowDownloads = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الشريط الإخباري والنافذة المنبثقة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _alertCtrl,
                        decoration: const InputDecoration(labelText: 'شريط تنبيه ملون في أعلى الشاشة الرئيسية'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _popupTitleCtrl,
                        decoration: const InputDecoration(labelText: 'عنوان النافذة المنبثقة الإجبارية'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _popupBodyCtrl,
                        decoration: const InputDecoration(labelText: 'نص الرسالة المنبثقة (اتركها فارغة لتعطيلها)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _popupUrlCtrl,
                        decoration: const InputDecoration(labelText: 'رابط تفاعلي تفتحه الرسالة المنبثقة'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تخصيص الواجهة وقائمة الحظر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pinnedHeroesCtrl,
                        decoration: const InputDecoration(labelText: 'معرفات بنر الهيرو المتحرك مفصولة بفواصل (123,456)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _blacklistCtrl,
                        decoration: const InputDecoration(labelText: 'قائمة الأعمال المحظورة مفصولة بفواصل (Blacklist IDs)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _minVerCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'أدنى رقم إصدار مطلوب (Force Update)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _apkUrlCtrl,
                        decoration: const InputDecoration(labelText: 'رابط الـ APK المباشر للتحديث الإجباري'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    onPressed: _saveGlobalSettings,
                    child: const Text('حفظ ونشر التعديلات فوراً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  ),
                ),
              ],
            ),

            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('سرعة استجابة السيرفرات (Ping Latency)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                            onPressed: _isTestingPing ? null : _testServerPings,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._serverLatencies.entries.map((e) {
                        final ms = e.value;
                        final isDown = ms == 9999 || ms < 0;
                        final color = isDown ? Colors.redAccent : (ms < 350 ? Colors.greenAccent : Colors.amber);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: s.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: color.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              Icon(isDown ? Icons.cancel_rounded : Icons.check_circle_rounded, color: color, size: 20),
                              const SizedBox(width: 10),
                              Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              Text(
                                isDown ? 'غير متصل (Offline)' : '${ms} ms',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تبديل رابط السيرفر الأساسي (Dynamic CDN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customUrlCtrl,
                        decoration: const InputDecoration(labelText: 'رابط بديل لـ cee.buzz في حال تم حجبه'),
                      ),
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('الجودة الافتراضية المفروضة للبث'),
                        trailing: DropdownButton<String>(
                          value: _selectedDefaultQuality,
                          dropdownColor: s.surface,
                          items: ['240p', '360p', '480p', '720p', '1080p']
                              .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedDefaultQuality = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إضافة أو حذف لقطات عمل معين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mediaIdCtrl,
                              decoration: const InputDecoration(labelText: 'معرف العمل (Media ID)'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppColors.primary),
                            onPressed: _fetchScenesForCurrentMedia,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _startSecCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'البداية (ثوانٍ)'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: _endSecCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'النهاية (ثوانٍ)'))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                          onPressed: _addCustomCensorScene,
                          child: const Text('إضافة المشهد لقاعدة البيانات السحابية', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _isSearchingScenes
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.primary)))
                    : (_loadedScenesForMedia.isEmpty
                        ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد لقطات محفوظة لهذا المعرف أو ابحث أولاً', style: TextStyle(color: s.textSecondary, fontSize: 12))))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('اللقطات الحالية المفهرسة (${_loadedScenesForMedia.length}):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 8),
                              ..._loadedScenesForMedia.map<Widget>((sc) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.border, width: 0.5)),
                                  child: ListTile(
                                    leading: const Icon(Icons.cut_rounded, color: Colors.amber),
                                    title: Text('من ${sc['start']} ث إلى ${sc['end']} ث (${(sc['end'] - sc['start'])} ثانية)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                                      onPressed: () => _deleteCensorScene(sc),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          )),
              ],
            ),

            _isLoadingStats
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border, width: 0.5)),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_done_rounded, color: AppColors.primary, size: 40),
                            const SizedBox(height: 10),
                            const Text('إحصائيات المنصة السحابية المباشرة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Divider(color: s.border, height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Text('$_totalUsersCount', style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('المستخدمين المسجلين', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text('$_totalCensoredDocsCount', style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('أعمال مفهرسة للحجب', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text('$_totalReportsCount', style: const TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('بلاغات المشاكل', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton(
                        color: s.surface,
                        borderRadius: BorderRadius.circular(14),
                        onPressed: _loadCloudStats,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded, size: 20),
                            SizedBox(width: 6),
                            Text('تحديث الإحصائيات الآن', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
            _advancedAdminTab(s),
          ],
        ),
      ),
    );
  }
}

class SubtitleSettingsScreen extends StatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  State<SubtitleSettingsScreen> createState() => _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState extends State<SubtitleSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'إعدادات الترجمة' : 'Subtitle Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: s.textPrimary)),
          leading: IconButton(
            icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 28, color: s.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                color: Colors.black,
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: (s.subBottomPadding / 90) * 60 + 10,
                    left: 20, right: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: s.subtitleBackgroundColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isAr ? 'معاينة موقع ولون وخلفية الترجمة\nLive Subtitle Preview' : 'Live Subtitle Preview\nمعاينة الترجمة الحية',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: s.subColor,
                            fontSize: s.subFontSize,
                            fontWeight: FontWeight.bold,
                            shadows: s.subHasShadow ? [const Shadow(blurRadius: 10, color: Colors.black)] : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.border, width: 0.5),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text(isAr ? 'خلفية الترجمة' : 'Subtitle Background', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(isAr ? 'شفاف، شبه شفاف، غامق' : 'Transparent, Semi, Dark', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                    trailing: CupertinoSlidingSegmentedControl<String>(
                      groupValue: s.subBackgroundMode,
                      children: {
                        'transparent': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'شفاف' : 'Clear', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                        'semi': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'شبه شفاف' : 'Semi', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                        'dark': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(isAr ? 'غامق' : 'Dark', style: TextStyle(color: s.textPrimary, fontSize: 11))),
                      },
                      onValueChanged: (val) {
                        if (val != null) setState(() => s.updateSubStyle(bgMode: val));
                      },
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'موقع الترجمة من أسفل الفيديو' : 'Bottom Offset', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Slider(
                      value: s.subBottomPadding,
                      min: 10.0,
                      max: 90.0,
                      activeColor: AppColors.primary,
                      inactiveColor: s.border,
                      onChanged: (v) => setState(() => s.updateSubStyle(bottomPadding: v)),
                    ),
                    trailing: Text('${s.subBottomPadding.toInt()} dp', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'حجم خط الترجمة' : 'Font Size', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: DropdownButton<double>(
                      dropdownColor: s.surface,
                      value: s.subFontSize,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 14.0, child: Text(isAr ? 'صغير' : 'Small', style: TextStyle(color: s.textPrimary))),
                        DropdownMenuItem(value: 18.0, child: Text(isAr ? 'متوسط' : 'Medium', style: TextStyle(color: s.textPrimary))),
                        DropdownMenuItem(value: 22.0, child: Text(isAr ? 'كبير' : 'Large', style: TextStyle(color: s.textPrimary))),
                      ],
                      onChanged: (v) => setState(() => s.updateSubStyle(size: v)),
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'لون الخط' : 'Text Color', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _colorBubble(Colors.white, s.subColor == Colors.white, () => setState(() => s.updateSubStyle(color: Colors.white))),
                        _colorBubble(Colors.yellow, s.subColor == Colors.yellow, () => setState(() => s.updateSubStyle(color: Colors.yellow))),
                        _colorBubble(const Color(0xFF00F0FF), s.subColor == const Color(0xFF00F0FF), () => setState(() => s.updateSubStyle(color: const Color(0xFF00F0FF)))),
                      ],
                    ),
                  ),
                  Divider(color: s.border, height: 1),
                  ListTile(
                    title: Text(isAr ? 'ظل حواف الخط' : 'Text Shadow', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    trailing: CupertinoSwitch(
                      value: s.subHasShadow,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => s.updateSubStyle(shadow: v)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              color: s.surface,
              borderRadius: BorderRadius.circular(14),
              onPressed: () => setState(() => s.resetSubtitles()),
              child: Text(isAr ? 'إعادة ضبط الترجمة الافتراضية' : 'Reset to Default', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorBubble(Color c, bool isSelected, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: AppColors.primary, width: 2.5) : null,
        ),
      ),
    );
  }
}


class ContentRequestScreen extends StatefulWidget {
  const ContentRequestScreen({super.key});
  @override State<ContentRequestScreen> createState() => _ContentRequestScreenState();
}
class _ContentRequestScreenState extends State<ContentRequestScreen> {
  final title = TextEditingController(); final notes = TextEditingController(); String type = 'movie';
  Future<void> _send() async {
    if (title.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('content_requests').add({'title': title.text.trim(), 'type': type, 'notes': notes.text.trim(), 'status': 'pending', 'uid': FirebaseAuth.instance.currentUser?.uid, 'email': FirebaseAuth.instance.currentUser?.email, 'created_at': FieldValue.serverTimestamp()});
    if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب إلى لوحة الأمان'))); }
  }
  @override Widget build(BuildContext context) { final s=AppSettings.instance; final ar=s.appLanguage=='ar'; return Directionality(textDirection: ar?TextDirection.rtl:TextDirection.ltr, child: Scaffold(backgroundColor:s.bg, appBar:AppBar(title:Text(ar?'طلب محتوى':'Content Request')), body:ListView(padding:const EdgeInsets.all(16), children:[TextField(controller:title, decoration:InputDecoration(labelText:ar?'اسم الفيلم أو المسلسل':'Title')), const SizedBox(height:10), DropdownButtonFormField<String>(value:type, items:const [DropdownMenuItem(value:'movie',child:Text('Movie / فيلم')),DropdownMenuItem(value:'series',child:Text('Series / مسلسل'))], onChanged:(v){if(v!=null)setState(()=>type=v);}, decoration:InputDecoration(labelText:ar?'النوع':'Type')), const SizedBox(height:10), TextField(controller:notes,maxLines:4,decoration:InputDecoration(labelText:ar?'ملاحظات':'Notes')), const SizedBox(height:16), ElevatedButton(onPressed:_send, child:Text(ar?'إرسال الطلب':'Send Request'))])); }
}

class SocialLinksScreen extends StatelessWidget {
  const SocialLinksScreen({super.key});
  @override Widget build(BuildContext context) { final s=AppSettings.instance; final ar=s.appLanguage=='ar'; final links=RemoteAdminConfig.instance.socialLinks.entries.where((e)=>e.value.isNotEmpty).toList(); return Directionality(textDirection:ar?TextDirection.rtl:TextDirection.ltr, child:Scaffold(backgroundColor:s.bg, appBar:AppBar(title:Text(AppLocalization.tr('social_accounts',s.appLanguage))), body:links.isEmpty ? Center(child:Text(ar?'لم تتم إضافة حسابات رسمية بعد':'No official accounts configured',style:TextStyle(color:s.textSecondary))) : ListView(padding:const EdgeInsets.all(16), children:links.map((e)=>Card(color:s.surface,child:ListTile(leading:Icon(_socialIcon(e.key),color:AppColors.primary),title:Text(e.key,style:TextStyle(color:s.textPrimary)),subtitle:Text(e.value, maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:s.textSecondary)),onTap:()=>launchUrl(Uri.parse(e.value),mode:LaunchMode.externalApplication)))).toList()))); }
  static IconData _socialIcon(String k) { switch(k){case 'telegram': return Icons.send_rounded; case 'whatsapp': return Icons.chat_rounded; case 'instagram': return Icons.camera_alt_rounded; case 'facebook': return Icons.facebook_rounded; default:return Icons.language_rounded;} }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _completed = [];
  List<Map<String, dynamic>> _watchlist = [];
  StreamSubscription? _dlSub;

  int _statMinutes = 0;
  int _statEpisodes = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);

    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        _loadData();
      }
    });

    _loadData();

    _dlSub = BackgroundDownloadService.progressStream.stream.listen((data) async {
      final String taskId = data[0];
      final int status = data[1];
      final int progress = data[2];

      if (mounted) {
        bool itemFound = false;
        for (var item in _completed) {
          if (item['taskId'] == taskId) {
            item['status'] = status;
            item['progress'] = progress;
            if (status == 3) {
              item['isCompleted'] = true;
            }
            itemFound = true;
            break;
          }
        }

        if (!itemFound) {
          final list = await LocalStorageService.getList('downloaded_works_list');
          setState(() {
            _completed = list;
          });
        } else {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _loadData() async {
    final downloads = await LocalStorageService.getList('downloaded_works_list');
    final wl = await LocalStorageService.getList('user_watchlist');
    final prefs = await SharedPreferences.getInstance();
    final curP = prefs.getString('current_active_profile') ?? 'default';

    if (mounted) {
      setState(() {
        _completed = downloads;
        _watchlist = wl;
        _statMinutes = prefs.getInt('stats_minutes_$curP') ?? 0;
        _statEpisodes = prefs.getInt('stats_episodes_$curP') ?? 0;
      });
    }
  }

  void _cleanCache() async {
    try {
      final tempDir = Directory.systemTemp;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppSettings.instance.appLanguage == 'ar' ? 'تم تفريغ الذاكرة المؤقتة بنجاح' : 'Cache cleared successfully')));
    } catch (_) {}
  }

  void _showAddProfileDialog(bool isAr) {
    final s = AppSettings.instance;
    final ctrl = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(isAr ? 'إضافة بروفايل جديد' : 'Add New Profile'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: isAr ? 'اسم الملف الشخصي' : 'Profile Name',
            style: TextStyle(color: s.textPrimary),
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: Text(isAr ? 'إلغاء' : 'Cancel')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                AppSettings.instance.addProfile(ctrl.text.trim());
                Navigator.pop(context);
              }
            },
            child: Text(isAr ? 'إضافة' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn(bool isAr) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '598398160963-7qus9g8t7kaniqh5offjhbqe2snk9471.apps.googleusercontent.com',
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        AppSettings.instance.login(
          user.displayName ?? (isAr ? 'مستخدم' : 'User'),
          user.email ?? '',
        );
        await _fetchWatchlistFromCloud(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'فشل تسجيل الدخول بـ Google: $e' : 'Google sign in failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleEmailAuth({
    required bool isRegister,
    required String email,
    required String password,
    required String name,
    required bool isAr,
  }) async {
    try {
      UserCredential userCredential;
      if (isRegister) {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        if (name.isNotEmpty) {
          await userCredential.user?.updateDisplayName(name.trim());
        }
      } else {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
      }

      final user = userCredential.user;
      if (user != null) {
        AppSettings.instance.login(
          user.displayName ?? (name.isNotEmpty ? name : (isAr ? 'مستخدم' : 'User')),
          user.email ?? email,
        );
        await _fetchWatchlistFromCloud(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'خطأ في المصادقة: $e' : 'Authentication error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _fetchWatchlistFromCloud(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('profiles')
          .doc(AppSettings.instance.activeProfile)
          .get();
      if (doc.exists && doc.data()?['watchlist'] != null) {
        final cloudList = List<Map<String, dynamic>>.from(doc.data()!['watchlist']);
        await LocalStorageService.setList('user_watchlist', cloudList);
        _loadData();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _showAuthDialog(bool isAr) {
    final s = AppSettings.instance;
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool isRegisterMode = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setMState) => Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: s.glassFill,
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isRegisterMode ? (isAr ? 'إنشاء حساب جديد' : 'Create New Account') : (isAr ? 'تسجيل الدخول' : 'Sign In'),
                            style: TextStyle(color: s.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: s.textPrimary),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (isRegisterMode) ...[
                        CupertinoTextField(
                          controller: nameCtrl,
                          placeholder: isAr ? 'الاسم' : 'Name',
                          style: TextStyle(color: s.textPrimary),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.border, width: 0.5)),
                        ),
                        const SizedBox(height: 10),
                      ],

                      CupertinoTextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        placeholder: isAr ? 'البريد الإلكتروني' : 'Email Address',
                        style: TextStyle(color: s.textPrimary),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.border, width: 0.5)),
                      ),
                      const SizedBox(height: 10),

                      CupertinoTextField(
                        controller: passCtrl,
                        obscureText: true,
                        placeholder: isAr ? 'كلمة المرور' : 'Password',
                        style: TextStyle(color: s.textPrimary),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.border, width: 0.5)),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () async {
                            if (emailCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) return;
                            Navigator.pop(ctx);
                            await _handleEmailAuth(
                              isRegister: isRegisterMode,
                              email: emailCtrl.text.trim(),
                              password: passCtrl.text.trim(),
                              name: nameCtrl.text.trim(),
                              isAr: isAr,
                            );
                          },
                          child: Text(
                            isRegisterMode ? (isAr ? 'إنشاء حساب' : 'Register') : (isAr ? 'تسجيل الدخول' : 'Sign In'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: () => setMState(() => isRegisterMode = !isRegisterMode),
                        child: Text(
                          isRegisterMode
                              ? (isAr ? 'لديك حساب بالفعل؟ تسجيل الدخول' : 'Already have an account? Sign In')
                              : (isAr ? 'ليس لديك حساب؟ إنشاء حساب جديد' : "Don't have an account? Register"),
                          style: TextStyle(color: s.textSecondary, fontSize: 12),
                        ),
                      ),

                      Divider(color: s.border, height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          color: s.surface,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleGoogleSignIn(isAr);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 28),
                              const SizedBox(width: 6),
                              Text(
                                isAr ? 'متابعة باستخدام Google' : 'Continue with Google',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: s.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final isAr = s.appLanguage == 'ar';
    final count = MediaQuery.of(context).size.width > 700 ? 5 : 3;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: s.bg,
        appBar: AppBar(
          title: Text(isAr ? 'الحساب والمكتبة' : 'Profile & Library', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: s.textPrimary)),
          actions: [
            IconButton(
              tooltip: isAr ? 'تفريغ الكاش' : 'Clear Cache',
              icon: Icon(Icons.delete_sweep_rounded, color: s.textSecondary),
              onPressed: _cleanCache,
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: s.textSecondary,
            tabs: [
              Tab(text: isAr ? 'التنزيلات' : 'Downloads'),
              Tab(text: isAr ? 'المفضلة' : 'Watchlist'),
              Tab(text: isAr ? 'الإحصائيات' : 'Stats'),
              Tab(text: isAr ? 'الإعدادات' : 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _completed.isEmpty
                ? Center(child: Text(isAr ? 'لا توجد تنزيلات حالياً' : 'No downloads yet', style: TextStyle(color: s.textSecondary)))
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _completed.length,
                    itemBuilder: (ctx, i) {
                      final it = _completed[i];
                      final filePath = it['path'] ?? '';
                      final file = File(filePath);
                      final bool fileExists = file.existsSync() && file.lengthSync() > 1024 * 1024;
                      final int progress = (it['progress'] is num) ? (it['progress'] as num).toInt() : 0;
                      final int status = (it['status'] is num) ? (it['status'] as num).toInt() : 0;

                      final bool isCompleted = fileExists && (it['isCompleted'] == true || status == 3 || progress >= 100);
                      final bool isFailed = (status == 4 || status == 5) || (status == 3 && !fileExists);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: s.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: s.border, width: 0.5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: it['poster'].toString().isNotEmpty
                                        ? CachedNetworkImage(imageUrl: it['poster'], width: 50, height: 70, fit: BoxFit.cover)
                                        : Container(width: 50, height: 70, color: s.surfaceLight),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(it['title'] ?? '', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                        const SizedBox(height: 6),
                                        Text(
                                          isCompleted
                                              ? (isAr ? 'جاهز للمشاهدة بدون إنترنت' : 'Ready to watch offline')
                                              : (isFailed
                                                  ? (isAr ? 'فشل التنزيل أو لم يكتمل' : 'Download failed')
                                                  : (isAr ? 'جاري التحميل ($progress%)' : 'Downloading ($progress%)')),
                                          style: TextStyle(
                                            color: isCompleted
                                                ? Colors.greenAccent
                                                : (isFailed ? Colors.redAccent : s.textSecondary),
                                            fontSize: 11,
                                            fontWeight: (isCompleted || isFailed) ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCompleted)
                                    IconButton(
                                      icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 30),
                                      onPressed: () {
                                        final subPath = it['subPath']?.toString() ?? '';
                                        if (file.existsSync()) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PlayerScreen(
                                                mediaId: (it['nb'] ?? it['id'] ?? '').toString(),
                                                title: it['title'] ?? '',
                                                videoUrl: filePath,
                                                subtitleUrl: subPath,
                                                qualities: const [],
                                                isLocalFile: true,
                                                poster: it['poster'] ?? '',
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(isAr ? 'الملف غير موجود في الذاكرة' : 'File not found on device')),
                                          );
                                        }
                                      },
                                    ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, color: s.textSecondary),
                                    onPressed: () async {
                                      final taskId = it['taskId']?.toString();
                                      if (taskId != null) {
                                        try {
                                          await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
                                        } catch (_) {}
                                      }
                                      if (file.existsSync()) {
                                        try {
                                          file.deleteSync();
                                        } catch (_) {}
                                      }
                                      final subFile = File(it['subPath']?.toString() ?? '');
                                      if (subFile.existsSync()) {
                                        try {
                                          subFile.deleteSync();
                                        } catch (_) {}
                                      }
                                      await LocalStorageService.removeItem('downloaded_works_list', it['nb']?.toString() ?? '', idField: 'nb');
                                      _loadData();
                                    },
                                  ),
                                ],
                              ),
                              if (!isCompleted && !isFailed) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (progress / 100.0).clamp(0.0, 1.0),
                                    backgroundColor: Colors.white12,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),

            _watchlist.isEmpty
                ? Center(child: Text(isAr ? 'لم تقم بحفظ أي عمل بعد' : 'Watchlist is empty', style: TextStyle(color: s.textSecondary)))
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, childAspectRatio: 0.58, crossAxisSpacing: 10, mainAxisSpacing: 12),
                    itemCount: _watchlist.length,
                    itemBuilder: (ctx, i) {
                      final item = _watchlist[i];
                      final poster = StreamService.extractPoster(item);
                      return FocusBuilder(
                        builder: (context, hasFocus) => InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaDetailScreen(media: item))).then((_) => _loadData()),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              border: Border.all(color: hasFocus ? AppColors.primary : Colors.transparent, width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              child: poster.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
                                  : Container(color: s.surface),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 40),
                      const SizedBox(height: 10),
                      Text(isAr ? 'إحصائيات الملف: ${s.activeProfile}' : 'Stats for: ${s.activeProfile}', style: TextStyle(color: s.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      Divider(color: s.border, height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$_statMinutes', style: TextStyle(color: s.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(isAr ? 'دقيقة مشاهدة' : 'Minutes Watched', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('$_statEpisodes', style: TextStyle(color: s.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(isAr ? 'حلقة مكتملة' : 'Completed Eps', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 24, backgroundColor: AppColors.primary, child: Icon(Icons.person_rounded, color: Colors.white)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.userName ?? (isAr ? 'مستخدم زائر' : 'Guest User'), style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(s.userEmail ?? (isAr ? 'المزامنة السحابية غير مفعّلة' : 'Sync disabled'), style: TextStyle(color: s.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minSize: 0,
                        onPressed: s.userName == null ? () => _showAuthDialog(isAr) : () => setState(() => s.logout()),
                        child: Text(s.userName == null ? (isAr ? 'تسجيل' : 'Login') : (isAr ? 'خروج' : 'Logout'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Text(isAr ? 'إدارة الملفات الشخصية' : 'Profile Management', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ...s.userProfiles.map<Widget>((p) => ChoiceChip(
                      label: Text(p, style: TextStyle(color: s.activeProfile == p ? Colors.white : s.textPrimary)),
                      selected: s.activeProfile == p,
                      selectedColor: AppColors.primary,
                      backgroundColor: s.surface,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          s.switchProfile(p);
                          _loadData();
                        });
                      },
                    )).toList(),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      backgroundColor: s.surface,
                      label: Text(isAr ? 'إضافة بروفايل' : 'Add Profile', style: TextStyle(color: s.textPrimary)),
                      onPressed: () => _showAddProfileDialog(isAr),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Container(
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'التنبيه الذكي للمسلسلات' : 'Smart Series Alerts', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(isAr ? 'إرسال إشعارات لحظية عند نزول حلقات جديدة' : 'Push notifications when new episodes arrive', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        trailing: CupertinoSwitch(
                          value: s.smartNotifications,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() => s.updateSmartNotifications(v)),
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'التنزيل الذكي للحلقات' : 'Smart Episode Downloads', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(isAr ? 'تنزيل الحلقة التالية ومسح المنتهية تلقائياً' : 'Auto download next episode & clean watched', style: TextStyle(color: s.textSecondary, fontSize: 11)),
                        trailing: CupertinoSwitch(
                          value: s.autoSmartDownload,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() => s.updateSmartDownload(v)),
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'لغة التطبيق' : 'App Language', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: DropdownButton<String>(
                          dropdownColor: s.surface,
                          value: s.appLanguage,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(value: 'ar', child: Text('العربية', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(color: s.textPrimary))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => s.updateLanguage(v));
                          },
                        ),
                      ),
                      Divider(color: s.border, height: 1),
                      ListTile(
                        leading: const Icon(Icons.text_fields_rounded, color: AppColors.primary),
                        title: Text(isAr ? 'خط التطبيق' : 'App Font', style: TextStyle(color: s.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: DropdownButton<String>(
                          dropdownColor: s.surface,
                          value: s.selectedFont,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(value: 'iPhone', child: Text('iPhone (Apple San Francisco)', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Cairo', child: Text('Cairo', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Tajawal', child: Text('Tajawal', style: TextStyle(color: s.textPrimary))),
                            DropdownMenuItem(value: 'Almarai', child: Text('Almarai', style: TextStyle(color: s.textPrimary))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => s.updateFont(v));
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                if (RemoteAdminConfig.instance.isFeatureEnabled('social_links')) ListTile(leading: const Icon(Icons.share_rounded, color: AppColors.primary), title: Text(AppLocalization.tr('social_accounts', s.appLanguage), style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SocialLinksScreen()))),
                if (RemoteAdminConfig.instance.isFeatureEnabled('content_requests')) ListTile(leading: const Icon(Icons.add_comment_rounded, color: AppColors.primary), title: Text(AppLocalization.tr('content_request', s.appLanguage), style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentRequestScreen()))),
                ListTile(leading: const Icon(Icons.dark_mode_rounded, color: AppColors.primary), title: Text('Instant Theme Mode', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)), trailing: DropdownButton<String>(value: s.themeMode, dropdownColor: s.surface, underline: const SizedBox(), items: const [DropdownMenuItem(value:'dark',child:Text('Dark')),DropdownMenuItem(value:'light',child:Text('Light')),DropdownMenuItem(value:'system',child:Text('System'))], onChanged:(v){if(v!=null)setState(()=>s.updateThemeMode(v));})),
                const SizedBox(height: 18),
                Text(isAr ? 'وضع المحتوى' : 'Content Mode', style: TextStyle(color: s.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.border, width: 0.5)),
                  child: Column(
                    children: [
                      RadioListTile<int>(
                        title: Text(isAr ? 'الافتراضي (الكل)' : 'Default (All Content)', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                        value: 0,
                        groupValue: s.appFilterMode,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFilterMode(v));
                        },
                      ),
                      Divider(color: s.border, height: 1),
                      RadioListTile<int>(
                        title: Text(isAr ? 'الوضع العائلي' : 'Family Mode', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                        value: 1,
                        groupValue: s.appFilterMode,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFilterMode(v));
                        },
                      ),
                      Divider(color: s.border, height: 1),
                      RadioListTile<int>(
                        title: Text(isAr ? 'وضع الأطفال' : 'Kids Mode', style: TextStyle(color: s.textPrimary, fontWeight: FontWeight.w600)),
                        value: 2,
                        groupValue: s.appFilterMode,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          if (v != null) setState(() => s.updateFilterMode(v));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FocusBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool hasFocus) builder;
  const FocusBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return builder(context, hasFocus);
        },
      ),
    );
  }
}
