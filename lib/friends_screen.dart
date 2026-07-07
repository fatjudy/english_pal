import 'package:flutter/material.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// Friends screen (Phase 1 of partner chat). Search users by username, send /
// accept / decline friend requests, and see your friends list. Reached from
// Settings → Friends. Requires being logged in (the API calls carry the token).
// ---------------------------------------------------------------------------

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incoming = [];
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await loadFriends();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['ok'] == true) {
        _friends = List<Map<String, dynamic>>.from(res['friends'] ?? []);
        _incoming = List<Map<String, dynamic>>.from(res['incoming'] ?? []);
      }
    });
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final res = await searchFriends(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = res['ok'] == true
          ? List<Map<String, dynamic>>.from(res['results'] ?? [])
          : [];
    });
  }

  Future<void> _add(int userId) async {
    await sendFriendRequest(userId);
    await _search(); // refresh the result's status → "Requested"
    await _load();
  }

  Future<void> _respond(int requesterId, bool accept) async {
    await respondFriendRequest(requesterId, accept);
    await _load();
    if (_searchController.text.trim().isNotEmpty) await _search();
  }

  String _name(Map u) {
    final d = (u['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (u['username'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Search bar.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                          hintText: 'Search by username',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _searching ? null : _search,
                      child: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search),
                    ),
                  ],
                ),

                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Search results'),
                  ..._results.map(_resultTile),
                ],

                if (_incoming.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Requests'),
                  ..._incoming.map(_incomingTile),
                ],

                const SizedBox(height: 24),
                _sectionTitle('Your friends'),
                if (_friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No friends yet. Search a username above to add someone.',
                      style: TextStyle(color: AppColors.tipText),
                    ),
                  )
                else
                  ..._friends.map(_friendTile),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy),
        ),
      );

  Widget _avatar(Map u) => CircleAvatar(
        backgroundColor: AppColors.gold,
        child: Text(
          _name(u).isNotEmpty ? _name(u)[0].toUpperCase() : '?',
          style: const TextStyle(
              color: AppColors.navy, fontWeight: FontWeight.w700),
        ),
      );

  Widget _resultTile(Map<String, dynamic> u) {
    final status = u['status'] as String;
    Widget trailing;
    switch (status) {
      case 'friends':
        trailing = const Text('Friends ✓',
            style: TextStyle(color: AppColors.correctionGreen));
        break;
      case 'pending_out':
        trailing =
            const Text('Requested', style: TextStyle(color: AppColors.tipText));
        break;
      case 'pending_in':
        trailing = FilledButton(
          onPressed: () => _respond(u['userId'] as int, true),
          child: const Text('Accept'),
        );
        break;
      default:
        trailing = FilledButton(
          onPressed: () => _add(u['userId'] as int),
          child: const Text('Add'),
        );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _avatar(u),
      title: Text(_name(u)),
      subtitle: Text('@${u['username']}'),
      trailing: trailing,
    );
  }

  Widget _incomingTile(Map<String, dynamic> u) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _avatar(u),
        title: Text(_name(u)),
        subtitle: Text('@${u['username']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _respond(u['userId'] as int, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => _respond(u['userId'] as int, true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

  Widget _friendTile(Map<String, dynamic> u) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _avatar(u),
        title: Text(_name(u)),
        subtitle: Text('@${u['username']}'),
      );
}
