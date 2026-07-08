import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'friends_screen.dart';
import 'partner_chat_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';

// ---------------------------------------------------------------------------
// The app's home hub. A bottom bar splits it into four tabs:
//   0. AI Bots  — the AI pals you created (opens the AI ChatScreen)
//   1. Friends  — your real human friends (each opens a PartnerChatScreen)
//   2. Groups   — group chats (placeholder for now)
//   3. Settings — the settings list (moved here from the app-bar icon)
// Reached after log in / setup.
// ---------------------------------------------------------------------------

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  int _tab = 0;

  // Keys so the shell's app-bar actions can refresh the relevant tab after
  // adding a friend / creating a group.
  final _friendsKey = GlobalKey<_FriendsTabState>();
  final _groupsKey = GlobalKey<_GroupsTabState>();

  static const _titles = ['AI Bots', 'Friends', 'Groups', 'Settings'];

  // App-bar actions depend on the current tab.
  List<Widget>? _actions() {
    if (_tab == 1) {
      return [
        IconButton(
          icon: const Icon(Icons.person_add_alt),
          tooltip: 'Add friend',
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()));
            _friendsKey.currentState?.reload();
          },
        ),
      ];
    }
    if (_tab == 2) {
      return [
        IconButton(
          icon: const Icon(Icons.group_add),
          tooltip: 'New group',
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
            _groupsKey.currentState?.reload();
          },
        ),
      ];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: _actions(),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const _AiBotsTab(),
          _FriendsTab(key: _friendsKey),
          _GroupsTab(key: _groupsKey),
          const SettingsBody(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.navy,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            label: 'AI Bots',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            label: 'Groups',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 0 — the AI pals you created. Currently just your one pal (Mia).
// ---------------------------------------------------------------------------
class _AiBotsTab extends StatefulWidget {
  const _AiBotsTab();

  @override
  State<_AiBotsTab> createState() => _AiBotsTabState();
}

class _AiBotsTabState extends State<_AiBotsTab> {
  String _palName = 'Mia';
  String _aiPreview = 'Your AI pal — always here';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final aiPreview = await loadAiChatPreview();
    if (!mounted) return;
    setState(() {
      _palName = prefs.getString('palName') ?? 'Mia';
      _aiPreview =
          aiPreview.isNotEmpty ? aiPreview : 'Your AI pal — always here';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _chatTile(
            avatar: palAvatar(radius: 24),
            title: _palName,
            subtitle: _aiPreview,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChatScreen()));
              _load(); // refresh Mia's preview after chatting
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — your real human friends and the chats you have with them.
// ---------------------------------------------------------------------------
class _FriendsTab extends StatefulWidget {
  const _FriendsTab({super.key});

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Public so the shell can refresh after a friend is added.
  void reload() => _load();

  Future<void> _load() async {
    final res = await loadConversations();
    if (!mounted) return;
    final list = res['ok'] == true
        ? List<Map<String, dynamic>>.from(res['conversations'] ?? [])
        : <Map<String, dynamic>>[];
    // Mark each chat unread if the newest message is newer than what we've seen
    // on this device and it wasn't one we sent.
    for (final c in list) {
      final convId = c['conversationId'];
      final lastId = (c['lastId'] ?? 0) as int;
      if (convId != null && lastId > 0 && c['lastMine'] != true) {
        final seen = await loadLastSeen(convId as int);
        c['unread'] = lastId > seen;
      } else {
        c['unread'] = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _friends = list;
      _loading = false;
    });
  }

  String _name(Map f) {
    final d = (f['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (f['username'] ?? '').toString();
  }

  // The one-line message preview under a friend's name.
  String _preview(Map f) {
    final text = (f['lastText'] ?? '').toString();
    if (text.isEmpty) return 'Tap to start chatting';
    return f['lastMine'] == true ? 'You: $text' : text;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _friends.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No friends yet. Tap the person icon above to find and '
                    'add friends to chat with.',
                    style: TextStyle(color: AppColors.tipText),
                  ),
                ),
              ],
            )
          : ListView(
              children: _friends
                  .map(
                    (f) => _chatTile(
                      avatar: _friendAvatar(f),
                      title: _name(f),
                      subtitle: _preview(f),
                      time: relativeTime((f['lastTime'] ?? '') as String),
                      unread: f['unread'] == true,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartnerChatScreen(friend: f),
                          ),
                        );
                        _load(); // clear unread + refresh preview on return
                      },
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _friendAvatar(Map f) => CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.navy,
        child: Text(
          _name(f).isNotEmpty ? _name(f)[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );
}

// ---------------------------------------------------------------------------
// Tab 2 — group chats you belong to. The + in the app bar creates a new one.
// ---------------------------------------------------------------------------
class _GroupsTab extends StatefulWidget {
  const _GroupsTab({super.key});

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Public so the shell can refresh after a group is created.
  void reload() => _load();

  Future<void> _load() async {
    final res = await loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = res['ok'] == true
          ? List<Map<String, dynamic>>.from(res['groups'] ?? [])
          : [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _groups.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No groups yet. Tap the + above to start a group chat with '
                    '3 or more people — a robot can join too.',
                    style: TextStyle(color: AppColors.tipText),
                  ),
                ),
              ],
            )
          : ListView(
              children: _groups.map((g) {
                final last = (g['lastText'] ?? '').toString();
                return _chatTile(
                  avatar: const CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.navy,
                    child: Icon(Icons.groups, color: Colors.white),
                  ),
                  title: (g['name'] ?? 'Group').toString(),
                  subtitle: last.isEmpty ? 'Tap to start chatting' : last,
                  time: relativeTime((g['lastTime'] ?? '') as String),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupChatScreen(group: g),
                      ),
                    );
                    _load(); // refresh preview on return
                  },
                );
              }).toList(),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chat-row widgets, used by the AI Bots and Friends tabs.
// ---------------------------------------------------------------------------
Widget _chatTile({
  required Widget avatar,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  String time = '',
  bool unread = false,
}) {
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: avatar,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: unread ? AppColors.body : AppColors.tipText,
        fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
    trailing: _trailing(time, unread),
    onTap: onTap,
  );
}

// Right side of a chat row: a relative time on top and, when there are unread
// messages, a small navy dot beneath it.
Widget _trailing(String time, bool unread) {
  if (time.isEmpty && !unread) {
    return const Icon(Icons.chevron_right, color: AppColors.tipText);
  }
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (time.isNotEmpty)
        Text(time,
            style: TextStyle(
              fontSize: 12,
              color: unread ? AppColors.navy : AppColors.tipText,
              fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
            )),
      const SizedBox(height: 4),
      if (unread)
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
        )
      else
        const SizedBox(height: 10),
    ],
  );
}
