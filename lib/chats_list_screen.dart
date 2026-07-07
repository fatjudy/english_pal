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
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final res = await loadFriends();
    if (!mounted) return;
    setState(() {
      _palName = prefs.getString('palName') ?? 'Mia';
      _friends = res['ok'] == true
          ? List<Map<String, dynamic>>.from(res['friends'] ?? [])
          : [];
      _loading = false;
    });
  }

  String _name(Map f) {
    final d = (f['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (f['username'] ?? '').toString();
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
                    subtitle: 'Your AI pal — always here',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ChatScreen())),
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
                        subtitle: '@${f['username']}',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartnerChatScreen(friend: f),
                          ),
                        ),
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
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: avatar,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right, color: AppColors.tipText),
      onTap: onTap,
    );
  }
}
