import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'friends_screen.dart';
import 'partner_chat_screen.dart';

// ---------------------------------------------------------------------------
// The app's home hub: a list of all your chats. The first entry is your AI pal
// (opens the existing AI ChatScreen); the rest are your human friends (each
// opens a PartnerChatScreen). Reached after log in / setup.
// ---------------------------------------------------------------------------

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _palName = 'Mia';
  String _aiPreview = 'Your AI pal — always here';
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final aiPreview = await loadAiChatPreview();
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
      _palName = prefs.getString('palName') ?? 'Mia';
      _aiPreview =
          aiPreview.isNotEmpty ? aiPreview : 'Your AI pal — always here';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Friends',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()));
              _load(); // a friend may have been added
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  // Your AI pal — always available.
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
                  const Divider(height: 1),
                  if (_friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No friends yet. Tap the person icon above to find and '
                        'add friends to chat with.',
                        style: TextStyle(color: AppColors.tipText),
                      ),
                    )
                  else
                    ..._friends.map(
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
                    ),
                ],
              ),
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
}
