import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'setup_flow_screen.dart';
import 'email_auth_screen.dart';
import 'chats_list_screen.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Navy / gold (bold) palette (see UI design spec).
class AppColors {
  static const navy = Color(0xFF233A66); // header, user bubbles, send button
  static const yellow = Color(0xFFFFD691); // avatar fill, send icon, top border
  static const gold = Color(0xFFFFD691); // bot bubbles, correction accent, tips
  static const coral = Color(0xFFFF6E80); // punchy accent, used sparingly
  static const white = Color(0xFFFFFFFF); // correction box, input field
  static const pageBg = Color(0xFFFBF6EC); // app background
  static const borderTint = Color(0xFFE3D4B5); // hairline borders on light

  static const body = Color(0xFF2A2A2A); // body text on light surfaces
  static const divider = Color(0xFFF0E6D0); // correction box divider
  static const avatarIcon = Color(0xFF233A66); // robot icon (navy)

  // Correction signal colors (universal red/green, full strength here).
  static const deletionRed = Color(0xFFC0392B);
  static const correctionGreen = Color(0xFF2E7D32);
  static const tipIcon = Color(0xFFD7A859); // gold lightbulb
  static const tipText = Color(0xFF6B6862);
}

// The pal's profile picture. Swap assets/pal_avatar.png with your own image
// (same filename) to change it — no code change needed.
Widget palAvatar({double radius = 16}) {
  return CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.yellow,
    backgroundImage: const AssetImage('assets/pal_avatar.png'),
  );
}

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  final String timeZoneName =
      (await FlutterTimezone.getLocalTimezone()).identifier;
  tz.setLocalLocation(tz.getLocation(timeZoneName));
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings settings =
      InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: _onNotificationTap,
  );
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'english_pal_channel',
    'Chat reminders',
    description: 'Reminders from your English pal',
    importance: Importance.high,
  );
  final androidImpl = notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);
  await androidImpl?.requestNotificationsPermission();
}

Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  String? id = prefs.getString('deviceId');
  if (id == null) {
    final rng = Random.secure();
    id = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    await prefs.setString('deviceId', id);
  }
  return id;
}

// The one place the backend address lives. In Australia, change ONLY this
// line to the Render URL (e.g. 'https://english-pal-backend.onrender.com').
String get backendBase =>
    kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';

// The WebSocket address for live partner-chat delivery — same host as
// backendBase but the ws:// scheme (wss:// once the backend is on https).
String get backendWsBase =>
    backendBase.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

// The live channel URL for one conversation, carrying the auth token.
Future<Uri> partnerSocketUri(int conversationId) async {
  final token = await _authToken();
  return Uri.parse('$backendWsBase/ws/$conversationId?token=$token');
}

// --- cloud storage helpers (best-effort: offline just falls back to local) ---

Future<void> saveProfileToCloud(Map<String, dynamic> profile) async {
  try {
    final deviceId = await getDeviceId();
    await http
        .post(
          Uri.parse('$backendBase/profile/save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deviceId': deviceId, ...profile}),
        )
        .timeout(const Duration(seconds: 6));
  } catch (e) {
    // Offline or server down — the local copy is still saved, so ignore.
  }
}

Future<void> saveChatToCloud(List messages, String summary) async {
  try {
    final deviceId = await getDeviceId();
    await http
        .post(
          Uri.parse('$backendBase/chat/save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(
              {'deviceId': deviceId, 'messages': messages, 'summary': summary}),
        )
        .timeout(const Duration(seconds: 6));
  } catch (e) {
    // Offline — local copy still saved.
  }
}

Future<Map<String, dynamic>?> loadProfileFromCloud() async {
  try {
    final deviceId = await getDeviceId();
    final response = await http
        .post(
          Uri.parse('$backendBase/profile/load'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deviceId': deviceId}),
        )
        .timeout(const Duration(seconds: 6));
    final data = jsonDecode(response.body);
    return data['profile']; // null if the server has nothing for us yet
  } catch (e) {
    return null; // offline — caller falls back to local
  }
}

Future<Map<String, dynamic>?> loadChatFromCloud() async {
  try {
    final deviceId = await getDeviceId();
    final response = await http
        .post(
          Uri.parse('$backendBase/chat/load'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deviceId': deviceId}),
        )
        .timeout(const Duration(seconds: 6));
    final data = jsonDecode(response.body);
    return data['chat'];
  } catch (e) {
    return null;
  }
}

// --- authentication (real accounts, for partner chat) ---------------------

// "Continue with email". mode is 'login' or 'signup' (from the toggle), so the
// backend enforces the chosen intent. Returns the decoded JSON, e.g.
// {ok: true, token, user} or {ok: false, error: '...'}.
Future<Map<String, dynamic>> continueWithEmail({
  required String email,
  required String password,
  required String mode,
}) async {
  try {
    final response = await http
        .post(
          Uri.parse('$backendBase/auth/continue'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(
              {'email': email, 'password': password, 'mode': mode}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body) as Map<String, dynamic>;
  } catch (e) {
    return {'ok': false, 'error': 'Could not reach the server. Please try again.'};
  }
}

// Persist the logged-in account on the phone so later features (partner chat)
// can use the token and know who the user is.
Future<void> saveAuth(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('authToken', data['token'] as String);
  final user = data['user'] as Map<String, dynamic>;
  await prefs.setInt('userId', user['userId'] as int);
  await prefs.setString('username', user['username'] as String);
  await prefs.setString('displayName', (user['displayName'] ?? '') as String);
  await prefs.setInt('partnerViewPref', (user['partnerViewPref'] ?? 1) as int);
}

// --- friends (partner chat) -----------------------------------------------

Future<String> _authToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('authToken') ?? '';
}

// Shared POST for the /friends/* endpoints: attaches the auth token and decodes
// the JSON reply (or a friendly error on network failure).
Future<Map<String, dynamic>> _friendsPost(
    String path, Map<String, dynamic> body) async {
  try {
    final token = await _authToken();
    final response = await http
        .post(
          Uri.parse('$backendBase$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token, ...body}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body) as Map<String, dynamic>;
  } catch (e) {
    return {'ok': false, 'error': 'Could not reach the server. Please try again.'};
  }
}

Future<Map<String, dynamic>> searchFriends(String query) =>
    _friendsPost('/friends/search', {'query': query});

Future<Map<String, dynamic>> sendFriendRequest(int targetUserId) =>
    _friendsPost('/friends/request', {'targetUserId': targetUserId});

Future<Map<String, dynamic>> respondFriendRequest(
        int requesterId, bool accept) =>
    _friendsPost('/friends/respond', {'requesterId': requesterId, 'accept': accept});

Future<Map<String, dynamic>> loadFriends() => _friendsPost('/friends/list', {});

// --- partner messaging -----------------------------------------------------

Future<Map<String, dynamic>> openConversation(int friendUserId) =>
    _friendsPost('/conversation/open', {'friendUserId': friendUserId});

Future<Map<String, dynamic>> sendPartnerMessage(int conversationId, String text) =>
    _friendsPost('/message/send',
        {'conversationId': conversationId, 'text': text});

Future<Map<String, dynamic>> fetchPartnerMessages(int conversationId, int sinceId) =>
    _friendsPost('/message/fetch',
        {'conversationId': conversationId, 'sinceId': sinceId});

// The Chats home list: friends enriched with their last message + its id.
Future<Map<String, dynamic>> loadConversations() =>
    _friendsPost('/conversation/list', {});

// The last message in the AI (Mia) chat, for its Chats-list preview. Reads the
// same locally-saved history the AI chat uses ({text, isUser} maps). Returns an
// empty string if there's no history yet.
Future<String> loadAiChatPreview() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('messages');
  if (saved == null) return '';
  final list = jsonDecode(saved) as List;
  if (list.isEmpty) return '';
  final last = list.last as Map;
  final text = (last['text'] ?? '').toString();
  if (text.isEmpty) return '';
  return last['isUser'] == true ? 'You: $text' : text;
}

// --- unread tracking (local per-device) ------------------------------------
// We remember, on the phone, the id of the newest message we've shown for each
// conversation. A conversation is "unread" when the server's latest id is newer
// than that AND the latest message isn't one we sent.

Future<int> loadLastSeen(int conversationId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('seen_conv_$conversationId') ?? 0;
}

Future<void> saveLastSeen(int conversationId, int lastId) async {
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getInt('seen_conv_$conversationId') ?? 0;
  if (lastId > current) {
    await prefs.setInt('seen_conv_$conversationId', lastId);
  }
}

// A short "how long ago" label for chat list timestamps. Input is the ISO UTC
// string the backend stores; empty string returns empty.
String relativeTime(String isoUtc) {
  if (isoUtc.isEmpty) return '';
  // The backend stores naive UTC (no 'Z'); add one so it's parsed as UTC and
  // not misread as local time.
  final normalized =
      (isoUtc.endsWith('Z') || isoUtc.contains('+')) ? isoUtc : '${isoUtc}Z';
  final then = DateTime.tryParse(normalized);
  if (then == null) return '';
  final diff = DateTime.now().difference(then.toLocal());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}

// --- partner-view preference (what your chat partner sees of your messages) --
// 1 = your original + your correction card, 2 = corrected sentence only,
// 3 = original only. Sender always still sees their own card either way.

Future<int> loadPartnerViewPref() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('partnerViewPref') ?? 1;
}

// Saves the preference on the server (stamped onto future messages) and mirrors
// it locally. Returns the backend reply.
Future<Map<String, dynamic>> setPartnerViewPref(int pref) async {
  final res = await _friendsPost('/prefs/partner-view', {'pref': pref});
  if (res['ok'] == true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('partnerViewPref', pref);
  }
  return res;
}

// --- group chat ------------------------------------------------------------
// Mirrors the partner-chat helpers. A group has 3+ participants and at most one
// robot; each member has a per-group share pref (1 card / 2 corrected /
// 3 original), the same three modes as 1-on-1.

// The live channel URL for one group, carrying the auth token.
Future<Uri> groupSocketUri(int groupId) async {
  final token = await _authToken();
  return Uri.parse('$backendWsBase/ws/group/$groupId?token=$token');
}

Future<Map<String, dynamic>> createGroup({
  required String name,
  required List<int> memberUserIds,
  required bool addRobot,
  Map<String, dynamic>? robot,
  required int sharePref,
}) =>
    _friendsPost('/group/create', {
      'name': name,
      'memberUserIds': memberUserIds,
      'addRobot': addRobot,
      'robot': ?robot,
      'sharePref': sharePref,
    });

Future<Map<String, dynamic>> loadGroups() => _friendsPost('/group/list', {});

Future<Map<String, dynamic>> groupInfo(int groupId) =>
    _friendsPost('/group/info', {'groupId': groupId});

Future<Map<String, dynamic>> fetchGroupMessages(int groupId, int sinceId) =>
    _friendsPost('/group/messages/fetch',
        {'groupId': groupId, 'sinceId': sinceId});

Future<Map<String, dynamic>> sendGroupMessage(int groupId, String text) =>
    _friendsPost('/group/message/send', {'groupId': groupId, 'text': text});

Future<Map<String, dynamic>> setGroupSharePref(int groupId, int pref) =>
    _friendsPost('/group/prefs', {'groupId': groupId, 'pref': pref});

// The robot's persona for a new group, taken from the local pal profile so the
// group robot matches the user's own Mia.
Future<Map<String, dynamic>> loadRobotConfig() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'name': prefs.getString('palName') ?? 'Mia',
    'personality': prefs.getStringList('personality') ?? [],
    'hobbies': prefs.getStringList('hobbies') ?? [],
    'topics': prefs.getStringList('topics') ?? [],
    'level': prefs.getString('level') ?? 'Intermediate',
  };
}

// --- saved corrections storage (shared by the AI chat and partner chat) ----

String correctionKey(String original, String correction) =>
    '$original|||$correction';

Future<Set<String>> loadSavedCorrectionKeys() async {
  final prefs = await SharedPreferences.getInstance();
  final List list =
      jsonDecode(prefs.getString('saved_corrections') ?? '[]') as List;
  return {
    for (final e in list)
      correctionKey(e['original'] as String, e['correction'] as String),
  };
}

// Add or remove a correction in the on-device saved list. Returns true if it is
// now saved (false if it was just removed).
Future<bool> toggleSavedCorrection(
    String original, String correction, String why) async {
  final prefs = await SharedPreferences.getInstance();
  final List<dynamic> list =
      jsonDecode(prefs.getString('saved_corrections') ?? '[]') as List<dynamic>;
  final already = list.any(
      (e) => e['original'] == original && e['correction'] == correction);
  if (already) {
    list.removeWhere(
        (e) => e['original'] == original && e['correction'] == correction);
  } else {
    list.add({
      'original': original,
      'correction': correction,
      'why': why,
      'savedAt': DateTime.now().toIso8601String(),
    });
  }
  await prefs.setString('saved_corrections', jsonEncode(list));
  return !already;
}

Future<String> fetchOpener(String topic) async {
  final prefs = await SharedPreferences.getInstance();
  final url = '$backendBase/opener';
  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'topic': topic,
        'palName': prefs.getString('palName') ?? 'Mia',
        'personality': prefs.getStringList('personality') ?? [],
        'hobbies': prefs.getStringList('hobbies') ?? [],
        'topics': prefs.getStringList('topics') ?? [],
        'level': prefs.getString('level') ?? 'Intermediate',
      }),
    );
    final data = jsonDecode(response.body);
    return data['message'];
  } catch (e) {
    return topic == 'Surprise me'
        ? 'Hey! Got a minute to chat?'
        : 'Hey! Want to chat about $topic?';
  }
}

Future<void> scheduleNotification(int id, int hour, int minute,
    String palName, String opener, String topic) async {
  final now = tz.TZDateTime.now(tz.local);
  var scheduledDate =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  final MessagingStyleInformation styleInfo = MessagingStyleInformation(
    const Person(name: 'You'),
    conversationTitle: palName,
    messages: [
      Message(opener, DateTime.now(), Person(name: palName)),
    ],
  );

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'english_pal_channel',
    'Chat reminders',
    channelDescription: 'Reminders from your English pal',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: styleInfo,
  );
  final NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await notificationsPlugin.zonedSchedule(
    id: id,
    scheduledDate: scheduledDate,
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    title: palName,
    body: opener,
    matchDateTimeComponents: DateTimeComponents.time,
    payload: opener,
  );
}

Future<void> _onNotificationTap(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_opener', response.payload ?? '');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();

  final launchDetails =
      await notificationsPlugin.getNotificationAppLaunchDetails();
  if (launchDetails?.didNotificationLaunchApp ?? false) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'pending_opener', launchDetails!.notificationResponse?.payload ?? '');
  }

  runApp(const MyApp());
}

// Replace the whole nav stack with the Chats home (used after log in / setup).
void _openHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const ChatsListScreen()),
    (route) => false,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _isSetUp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('palName') != null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.pageBg,
        // Base type scale (shared 6-level scale: 36/26/24/18/17/15). Sizes only —
        // colors are merged from the default, so text colors are preserved.
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 17),
          bodyMedium: TextStyle(fontSize: 17),
          bodySmall: TextStyle(fontSize: 15),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 18),
          labelLarge: TextStyle(fontSize: 17),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
            textStyle:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          side: const BorderSide(color: AppColors.borderTint),
          selectedColor: AppColors.gold,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.navy,
          titleTextStyle: TextStyle(fontSize: 17, color: AppColors.body),
          subtitleTextStyle: TextStyle(fontSize: 15, color: AppColors.tipText),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
        ),
      ),
      home: FutureBuilder<bool>(
        future: _isSetUp(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data!) return const ChatsListScreen();
          // New users see the welcome/onboarding carousel first; both
          // Sign up and Log in open the login page.
          return Builder(
            builder: (context) {
              void openLogin() => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (loginCtx) {
                        // After a successful log in / sign up: existing users
                        // (who already have a pal) go to chat; brand-new users
                        // do the 3-page pal setup first.
                        Future<void> afterAuth() async {
                          final prefs = await SharedPreferences.getInstance();
                          if (!loginCtx.mounted) return;
                          if (prefs.getString('palName') != null) {
                            _openHome(loginCtx);
                          } else {
                            Navigator.of(loginCtx).push(
                              MaterialPageRoute(
                                builder: (_) => AccountSetupScreen(
                                  onDone: () => _openHome(loginCtx),
                                ),
                              ),
                            );
                          }
                        }

                        return LoginScreen(
                          // Google sign-in is a later phase (needs Firebase).
                          onGoogle: () =>
                              ScaffoldMessenger.of(loginCtx).showSnackBar(
                            const SnackBar(
                              content: Text('Google sign-in is coming soon — '
                                  'please use email for now.'),
                            ),
                          ),
                          // Continue with email → log in, or auto-create the
                          // account if the email is new.
                          onEmail: () => Navigator.of(loginCtx).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  EmailAuthScreen(onSuccess: afterAuth),
                            ),
                          ),
                        );
                      },
                    ),
                  );
              return OnboardingScreen(
                onSignUp: openLogin,
                onLogin: openLogin,
              );
            },
          );
        },
      ),
    );
  }
}

// ---- word-level diff for showing corrections (track-changes style) ----

enum DiffOp { equal, delete, insert }

class DiffSeg {
  final DiffOp op;
  final String text;
  DiffSeg(this.op, this.text);
}

// Normalize a word for comparison: lowercase, drop punctuation, so that
// "yesterday." and "Yesterday" count as the same word.
String _normWord(String w) => w.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');

// Compare the original and corrected sentences word by word using a classic
// longest-common-subsequence diff. Returns a list of segments marked equal,
// delete (in original only) or insert (in correction only).
List<DiffSeg> wordDiff(String oldText, String newText) {
  final a = oldText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final b = newText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final n = a.length, m = b.length;

  // dp[i][j] = length of LCS of a[i:] and b[j:]
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (_normWord(a[i]) == _normWord(b[j])) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  final segs = <DiffSeg>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (_normWord(a[i]) == _normWord(b[j])) {
      segs.add(DiffSeg(DiffOp.equal, b[j]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      segs.add(DiffSeg(DiffOp.delete, a[i]));
      i++;
    } else {
      segs.add(DiffSeg(DiffOp.insert, b[j]));
      j++;
    }
  }
  while (i < n) {
    segs.add(DiffSeg(DiffOp.delete, a[i]));
    i++;
  }
  while (j < m) {
    segs.add(DiffSeg(DiffOp.insert, b[j]));
    j++;
  }
  return segs;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});


  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController(); 
  bool _isMiaTyping = false;
  String summary = '';
  String palName = 'Mia';
  List<String> personality = [];
  List<String> hobbies = [];
  List<String> topics = [];
  String level = 'Intermediate';
  // Keys of corrections already saved, so each card's bookmark can show
  // filled (saved) vs. outline (not saved) without an async lookup per build.
  Set<String> _savedKeys = {};
  String get _backendUrl => '$backendBase/chat';
  
  final List<Map<String, dynamic>> messages = [
    {'text': "Hi! I'm Mia. How's your day going?", 'isUser': false},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingOpener();
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    final userMessage = {'text': text, 'isUser': true, 'correction': '', 'checked': false};
    setState(() {
      messages.add(userMessage);
      _isMiaTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    final recent = messages.length > 16
        ? messages.sublist(messages.length - 16)
        : messages;

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'summary': summary,
          'palName': palName,
          'personality': personality,
          'hobbies': hobbies,
          'topics': topics,
          'level': level,
          'messages': [
            for (final m in recent)
              {
                'role': m['isUser'] == true ? 'user' : 'model',
                'text': m['text'],
              },
          ],
        }),
      );

        final data = jsonDecode(response.body);
        summary = data['summary'];

      setState(() {
        userMessage['correction'] = data['correction'];
        userMessage['why'] = data['why'] ?? '';
        userMessage['understood'] = data['understood'] ?? true;
        userMessage['checked'] = true;
        messages.add({'text': data['reply'], 'isUser': false});
        _isMiaTyping = false;
      });
    _scrollToBottom();
    } catch (e) {
      setState(() {
        messages.add({
          'text': "Sorry, I couldn't reach the server. Is the backend running?",
          'isUser': false,
        });
        _isMiaTyping = false;
      });
    }
    _saveChat();
  }

  Future<void> _loadChat() async {
    final prefs = await SharedPreferences.getInstance();

    // Profile: prefer the cloud copy; fall back to what's on the phone.
    final cloudProfile = await loadProfileFromCloud();
    if (cloudProfile != null) {
      palName = cloudProfile['palName'] ?? 'Mia';
      personality = List<String>.from(cloudProfile['personality'] ?? []);
      hobbies = List<String>.from(cloudProfile['hobbies'] ?? []);
      topics = List<String>.from(cloudProfile['topics'] ?? []);
      level = cloudProfile['level'] ?? 'Intermediate';
    } else {
      palName = prefs.getString('palName') ?? 'Mia';
      personality = prefs.getStringList('personality') ?? [];
      hobbies = prefs.getStringList('hobbies') ?? [];
      topics = prefs.getStringList('topics') ?? [];
      level = prefs.getString('level') ?? 'Intermediate';
    }

    // Chat history: prefer the cloud copy; fall back to local.
    final cloudChat = await loadChatFromCloud();
    List? messagesList;
    String? savedSummary;
    if (cloudChat != null) {
      messagesList = cloudChat['messages'] as List;
      savedSummary = cloudChat['summary'] as String;
    } else {
      final savedMessages = prefs.getString('messages');
      if (savedMessages != null) {
        messagesList = jsonDecode(savedMessages) as List;
      }
      savedSummary = prefs.getString('summary');
    }

    if (messagesList != null) {
      final loaded = messagesList;
      setState(() {
        messages.clear();
        messages.addAll(loaded.cast<Map<String, dynamic>>());
      });
    } else {
      setState(() {
        messages.clear();
        messages.add({
          'text': "Hi! I'm $palName. How's your day going?",
          'isUser': false,
        });
      });
    }
    if (savedSummary != null) {
      summary = savedSummary;
    }
    await _loadSavedKeys();
    await _checkPendingOpener();
    _scrollToBottom();
  }

  // Build the key used to tell whether a correction is already saved.
  String _correctionKey(String original, String correction) =>
      '$original|||$correction';

  // Refresh the in-memory set of saved-correction keys from storage. Called on
  // load and whenever we return from Settings (where items may be removed).
  Future<void> _loadSavedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final List list =
        jsonDecode(prefs.getString('saved_corrections') ?? '[]') as List;
    setState(() {
      _savedKeys = {
        for (final e in list)
          _correctionKey(e['original'] as String, e['correction'] as String),
      };
    });
  }

  // Re-read the pal's profile (e.g. after the user edits it in Settings) so the
  // chat uses the new name/personality right away.
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      palName = prefs.getString('palName') ?? 'Mia';
      personality = prefs.getStringList('personality') ?? [];
      hobbies = prefs.getStringList('hobbies') ?? [];
      topics = prefs.getStringList('topics') ?? [];
      level = prefs.getString('level') ?? 'Intermediate';
    });
    await _loadSavedKeys();
  }

  Future<void> _checkPendingOpener() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pending_opener');
    if (pending != null && pending.isNotEmpty) {
      setState(() {
        messages.add({'text': pending, 'isUser': false});
      });
      await prefs.remove('pending_opener');
      await _saveChat();
      _scrollToBottom();
    }
  }

  Future<void> _saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('messages', jsonEncode(messages));
    await prefs.setString('summary', summary);
    await saveChatToCloud(messages, summary);
  }

  Widget _messageBubble(String text, bool isUser) {
    final maxW = MediaQuery.of(context).size.width * 0.82;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isUser ? AppColors.navy : AppColors.gold,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Toggle whether this correction is saved: tap the bookmark to add it to the
  // on-device "saved_corrections" list, tap again to remove it.
  Future<void> _toggleSaveCorrection(
      String original, String correction, String why) async {
    final prefs = await SharedPreferences.getInstance();

    // Read the existing list — the same JSON round-trip schedules use.
    final List<dynamic> list =
        jsonDecode(prefs.getString('saved_corrections') ?? '[]')
            as List<dynamic>;
    final key = _correctionKey(original, correction);
    final bool isSaved = _savedKeys.contains(key);

    if (isSaved) {
      list.removeWhere((e) =>
          e['original'] == original && e['correction'] == correction);
    } else {
      list.add({
        'original': original,
        'correction': correction,
        'why': why,
        'savedAt': DateTime.now().toIso8601String(),
      });
    }
    await prefs.setString('saved_corrections', jsonEncode(list));

    // Update the in-memory set so the bookmark icon flips right away.
    setState(() {
      if (isSaved) {
        _savedKeys.remove(key);
      } else {
        _savedKeys.add(key);
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isSaved
            ? 'Removed from your review list'
            : 'Saved to your review list'),
      ),
    );
  }

  Widget _correctionCard(String original, String correction, String why) {
    final segs = wordDiff(original, correction);
    final bool saved = _savedKeys.contains(_correctionKey(original, correction));
    final spans = <InlineSpan>[];
    for (final s in segs) {
      switch (s.op) {
        case DiffOp.equal:
          spans.add(TextSpan(text: '${s.text} '));
          break;
        case DiffOp.delete:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
              color: AppColors.deletionRed,
              decoration: TextDecoration.lineThrough,
            ),
          ));
          break;
        case DiffOp.insert:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
              color: AppColors.correctionGreen,
              fontWeight: FontWeight.w600,
            ),
          ));
          break;
      }
    }

    final maxW = MediaQuery.of(context).size.width * 0.88;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(
                left: BorderSide(color: AppColors.gold, width: 3),
                top: BorderSide(color: AppColors.borderTint, width: 0.5),
                right: BorderSide(color: AppColors.borderTint, width: 0.5),
                bottom: BorderSide(color: AppColors.borderTint, width: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x14233A66), // navy at ~8% opacity
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check, size: 15, color: AppColors.navy),
                    const SizedBox(width: 4),
                    const Text(
                      'CORRECTION',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: AppColors.navy,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () =>
                          _toggleSaveCorrection(original, correction, why),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          saved ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 15,
                      height: 1.55,
                    ),
                    children: spans,
                  ),
                ),
                if (why.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  const Divider(
                      height: 1, thickness: 0.5, color: AppColors.divider),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          size: 14, color: AppColors.tipIcon),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          why,
                          style: const TextStyle(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            color: AppColors.tipText,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _looksGoodNote() {
    return const Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: 18, bottom: 8, top: 2),
        child: Text(
          '✓ Looks good!',
          style: TextStyle(color: AppColors.correctionGreen, fontSize: 15),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: const BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Text(
            '$palName is typing…',
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 12,
        title: Row(
          children: [
            palAvatar(radius: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    palName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'always here to help',
                    style: TextStyle(color: AppColors.gold, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              await _loadProfile();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
              child: ListView(
                controller: _scrollController,
                children: [
                for (final message in messages)
                  Column(
                    children: [
                      _messageBubble(
                        message['text'],
                        message['isUser'],
                      ),
                      if (message['isUser'] == true &&
                          message['correction'] != null &&
                          message['correction'] != '')
                        _correctionCard(message['text'],
                            message['correction'], message['why'] ?? ''),
                      if (message['isUser'] == true &&
                          message['checked'] == true &&
                          message['correction'] == '' &&
                          message['understood'] != false)
                        _looksGoodNote(),
                    ],
                  ),
              ],
            ),
          ),
          if (_isMiaTyping) _typingIndicator(),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.pageBg,
              border: Border(
                top: BorderSide(color: AppColors.yellow, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(
                            color: AppColors.body, fontSize: 17),
                        decoration: InputDecoration(
                          hintText: 'Type in English…',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                                color: AppColors.borderTint, width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                                color: AppColors.navy, width: 1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Material(
                        color: AppColors.navy,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _sendMessage,
                          child: const Icon(Icons.send,
                              color: AppColors.yellow, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared option lists, used by both the setup wizard and the edit screen so
// they can never drift apart.
const List<String> kPersonalityOptions = [
  'Friendly', 'Funny', 'Calm & Patient', 'Encouraging', 'Curious',
  'Witty', 'Chatty', 'Gentle', 'Enthusiastic', 'Thoughtful',
];
const List<String> kHobbyOptions = [
  'Sports', 'Music', 'Movies & TV', 'Gaming', 'Cooking', 'Travel',
  'Books', 'Art', 'Technology', 'Nature', 'Fitness', 'Pets',
  'Photography', 'Science',
];
const List<String> kTopicOptions = [
  'Daily life', 'Work/Career', 'Travel English', 'Job interviews',
  'Small talk', 'Hobbies', 'News', 'Food', 'Culture', 'Studying abroad',
  'Shopping', 'Health',
];
const List<String> kLevelOptions = ['Beginner', 'Intermediate', 'Advanced'];

class EditPalScreen extends StatefulWidget {
  const EditPalScreen({super.key});

  @override
  State<EditPalScreen> createState() => _EditPalScreenState();
}

class _EditPalScreenState extends State<EditPalScreen> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedPersonalities = {};
  final Set<String> _selectedHobbies = {};
  final Set<String> _selectedTopics = {};
  String _selectedLevel = 'Intermediate';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('palName') ?? '';
      _selectedPersonalities.addAll(prefs.getStringList('personality') ?? []);
      _selectedHobbies.addAll(prefs.getStringList('hobbies') ?? []);
      _selectedTopics.addAll(prefs.getStringList('topics') ?? []);
      _selectedLevel = prefs.getString('level') ?? 'Intermediate';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _nameController.text.trim().isEmpty
        ? 'Mia'
        : _nameController.text.trim();
    await prefs.setString('palName', name);
    await prefs.setStringList('personality', _selectedPersonalities.toList());
    await prefs.setStringList('hobbies', _selectedHobbies.toList());
    await prefs.setStringList('topics', _selectedTopics.toList());
    await prefs.setString('level', _selectedLevel);
    await saveProfileToCloud({
      'palName': name,
      'personality': _selectedPersonalities.toList(),
      'hobbies': _selectedHobbies.toList(),
      'topics': _selectedTopics.toList(),
      'level': _selectedLevel,
    });
  }

  Widget _chipSection(String label, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (isSelected) {
                  setState(() {
                    if (isSelected) {
                      selected.add(option);
                    } else {
                      selected.remove(option);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit your pal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Your pal's name:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Mia, Leo, Aria...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _chipSection(
                      'Personality:', kPersonalityOptions, _selectedPersonalities),
                  _chipSection('Hobbies:', kHobbyOptions, _selectedHobbies),
                  _chipSection(
                      'Topics to talk about:', kTopicOptions, _selectedTopics),
                  const Text('English level:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final level in kLevelOptions)
                        ChoiceChip(
                          label: Text(level),
                          selected: _selectedLevel == level,
                          onSelected: (isSelected) {
                            setState(() {
                              _selectedLevel = level;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await _save();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Saved!')),
                        );
                        Navigator.pop(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('Save', style: TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsBody(),
    );
  }
}

// The settings list on its own, so it can be shown either as its own screen
// (above) or embedded as the 4th tab in the home bottom bar.
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Edit your pal'),
            subtitle: const Text('Name, personality, hobbies, topics, level'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EditPalScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('What friends see'),
            subtitle: const Text('Choose what a friend sees when you message'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PartnerViewScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Saved corrections'),
            subtitle: const Text('Review corrections you bookmarked'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SavedCorrectionsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Scheduled messages'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ScheduleScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Start over'),
            subtitle: const Text('Clear everything and set up a new pal'),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (setupCtx) => AccountSetupScreen(
                    onDone: () => _openHome(setupCtx),
                  ),
                ),
                (route) => false,
              );
            },
          ),
        ],
    );
  }
}

// Lets the user choose what their chat partner sees of the messages they send.
// The user always still sees their own private correction card regardless.
class PartnerViewScreen extends StatefulWidget {
  const PartnerViewScreen({super.key});

  @override
  State<PartnerViewScreen> createState() => _PartnerViewScreenState();
}

class _PartnerViewScreenState extends State<PartnerViewScreen> {
  int _pref = 1;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await loadPartnerViewPref();
    if (!mounted) return;
    setState(() {
      _pref = p;
      _loading = false;
    });
  }

  Future<void> _choose(int pref) async {
    if (_saving) return;
    setState(() {
      _pref = pref;
      _saving = true;
    });
    final res = await setPartnerViewPref(pref);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['error'] ?? 'Could not save.') as String)),
      );
    }
  }

  Widget _option(int value, String title, String subtitle) {
    final selected = _pref == value;
    return ListTile(
      onTap: _saving ? null : () => _choose(value),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.navy : AppColors.tipText,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What friends see')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'When you send a message in a friend chat, this is what your '
                    'friend sees. You always still see your own correction card.',
                    style: TextStyle(color: AppColors.tipText, height: 1.4),
                  ),
                ),
                _option(1, 'Original + correction card',
                    'Your friend sees what you typed and your correction.'),
                _mode1Preview(),
                _option(2, 'Corrected only',
                    'Your friend sees just your polished sentence.'),
                _option(3, 'Original only',
                    'Your friend sees only what you typed, no correction.'),
              ],
            ),
    );
  }

  // A small "this is what it looks like" example under the first option — a
  // sample incoming bubble plus the correction card, built from the same styling
  // the real chat uses. Only mode 1 shows a card, so only this option needs one.
  Widget _mode1Preview() {
    const original = 'I go beach yesterday';
    const corrected = 'I went to the beach yesterday';
    const why = 'Past tense';
    final spans = <InlineSpan>[];
    for (final s in wordDiff(original, corrected)) {
      switch (s.op) {
        case DiffOp.equal:
          spans.add(TextSpan(text: '${s.text} '));
          break;
        case DiffOp.delete:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
                color: AppColors.deletionRed,
                decoration: TextDecoration.lineThrough),
          ));
          break;
        case DiffOp.insert:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
                color: AppColors.correctionGreen,
                fontWeight: FontWeight.w600),
          ));
          break;
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(56, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your friend sees:',
              style: TextStyle(fontSize: 12, color: AppColors.tipText)),
          const SizedBox(height: 6),
          // sample incoming bubble (your message, as the friend receives it)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(original,
                  style: TextStyle(color: AppColors.body, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 4),
          // sample correction card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(
                left: BorderSide(color: AppColors.gold, width: 3),
                top: BorderSide(color: AppColors.borderTint, width: 0.5),
                right: BorderSide(color: AppColors.borderTint, width: 0.5),
                bottom: BorderSide(color: AppColors.borderTint, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check, size: 13, color: AppColors.navy),
                    SizedBox(width: 4),
                    Text('CORRECTION',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: AppColors.navy)),
                  ],
                ),
                const SizedBox(height: 5),
                Text.rich(TextSpan(
                    style: const TextStyle(
                        color: AppColors.body, fontSize: 14, height: 1.5),
                    children: spans)),
                const SizedBox(height: 5),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 13, color: AppColors.tipIcon),
                    SizedBox(width: 4),
                    Text(why,
                        style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppColors.tipText)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SavedCorrectionsScreen extends StatefulWidget {
  const SavedCorrectionsScreen({super.key});

  @override
  State<SavedCorrectionsScreen> createState() => _SavedCorrectionsScreenState();
}

class _SavedCorrectionsScreenState extends State<SavedCorrectionsScreen> {
  List<Map<String, dynamic>> _saved = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('saved_corrections') ?? '[]';
    final List decoded = jsonDecode(raw) as List;
    setState(() {
      // Newest first.
      _saved = decoded.cast<Map<String, dynamic>>().reversed.toList();
      _loading = false;
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _saved.remove(item));
    // Persist the remaining list (stored oldest-first, so reverse back).
    await prefs.setString(
        'saved_corrections', jsonEncode(_saved.reversed.toList()));
  }

  // Build the same colored track-changes spans the chat correction card uses.
  List<InlineSpan> _diffSpans(String original, String correction) {
    final segs = wordDiff(original, correction);
    final spans = <InlineSpan>[];
    for (final s in segs) {
      switch (s.op) {
        case DiffOp.equal:
          spans.add(TextSpan(text: '${s.text} '));
          break;
        case DiffOp.delete:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
              color: AppColors.deletionRed,
              decoration: TextDecoration.lineThrough,
            ),
          ));
          break;
        case DiffOp.insert:
          spans.add(TextSpan(
            text: '${s.text} ',
            style: const TextStyle(
              color: AppColors.correctionGreen,
              fontWeight: FontWeight.w600,
            ),
          ));
          break;
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved corrections')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _saved.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No saved corrections yet.\n\nTap the bookmark on a '
                      'correction card in chat to save it here for review.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.tipText, fontSize: 15),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _saved.length,
                  itemBuilder: (context, i) {
                    final item = _saved[i];
                    final why = (item['why'] ?? '') as String;
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        border: Border(
                          left: BorderSide(color: AppColors.gold, width: 3),
                          top: BorderSide(
                              color: AppColors.borderTint, width: 0.5),
                          right: BorderSide(
                              color: AppColors.borderTint, width: 0.5),
                          bottom: BorderSide(
                              color: AppColors.borderTint, width: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                color: AppColors.body,
                                fontSize: 15,
                                height: 1.55,
                              ),
                              children: _diffSpans(
                                item['original'] as String,
                                item['correction'] as String,
                              ),
                            ),
                          ),
                          if (why.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            const Divider(
                                height: 1,
                                thickness: 0.5,
                                color: AppColors.divider),
                            const SizedBox(height: 7),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lightbulb_outline,
                                    size: 14, color: AppColors.tipIcon),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    why,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.tipText,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _delete(item),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Remove'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.tipText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final List<Map<String, dynamic>> schedules = [];
  final TextEditingController _topicController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('schedules');
    if (saved == null) return;
    final List decoded = jsonDecode(saved) as List;
    final String palName = prefs.getString('palName') ?? 'Mia';
    setState(() {
      schedules.clear();
      schedules.addAll(decoded.cast<Map<String, dynamic>>());
    });
    for (final s in schedules) {
      await scheduleNotification(
          s['id'], s['hour'], s['minute'], palName, s['opener'], s['topic']);
    }
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedules', jsonEncode(schedules));
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    await notificationsPlugin.cancel(id: schedule['id']);
    setState(() {
      schedules.remove(schedule);
    });
    await _saveSchedules();
  }

  Future<void> _addSchedule() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    _topicController.clear();
    final String? topic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What topic?'),
        content: TextField(
          controller: _topicController,
          decoration: const InputDecoration(
            hintText: 'e.g. Food — or leave blank for random',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _topicController.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (topic == null) return;

    final int id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    final String finalTopic = topic.isEmpty ? 'Surprise me' : topic;
    final String opener = await fetchOpener(finalTopic);
    final prefs = await SharedPreferences.getInstance();
    final String palName = prefs.getString('palName') ?? 'Mia';

    setState(() {
      schedules.add({
        'id': id,
        'hour': time.hour,
        'minute': time.minute,
        'time': time.format(context),
        'topic': finalTopic,
        'opener': opener,
      });
    });
    await _saveSchedules();
    await scheduleNotification(
        id, time.hour, time.minute, palName, opener, finalTopic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled messages')),
      body: schedules.isEmpty
          ? const Center(child: Text('No schedules yet. Tap + to add one.'))
          : ListView(
              children: [
                for (final schedule in schedules)
                  ListTile(
                    leading: const Icon(Icons.notifications),
                    title: Text(schedule['time']),
                    subtitle: Text(schedule['topic']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSchedule(schedule),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSchedule,
        child: const Icon(Icons.add),
      ),
    );
  }
}