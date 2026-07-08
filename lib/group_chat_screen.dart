import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// Group chat: 3+ people and at most one AI robot. Works like the 1-on-1 partner
// chat (live WebSocket + a safety poll), but bubbles are labelled with the
// sender's name, robot replies are marked, and each message is shaped by the
// sender's per-group share preference (done on the server). The robot replies
// only when someone mentions it by name.
// ---------------------------------------------------------------------------

// The three share modes, reused by the create screen and group settings.
const groupShareLabels = {
  1: 'Original + correction card',
  2: 'Corrected sentence only',
  3: 'Original message only',
};

class GroupChatScreen extends StatefulWidget {
  final Map<String, dynamic> group; // needs at least groupId + name

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  late final int _groupId;
  int _myUserId = 0;
  bool _loading = true;
  bool _sending = false;
  bool _fetching = false;
  Timer? _pollTimer;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _wsConnecting = false;
  Set<String> _savedKeys = {};

  String get _title => (widget.group['name'] ?? 'Group').toString();

  @override
  void initState() {
    super.initState();
    _groupId = widget.group['groupId'] as int;
    _open();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId') ?? 0;
    _savedKeys = await loadSavedCorrectionKeys();
    await _fetchNew();
    if (!mounted) return;
    setState(() => _loading = false);
    _startSafetyPoll();
    _connectWs();
  }

  int get _lastId => _messages.isEmpty ? 0 : _messages.last['id'] as int;

  // --- live delivery (same pattern as the partner chat) --------------------
  Future<void> _connectWs() async {
    if (!mounted || _wsConnecting) return;
    _wsConnecting = true;
    try {
      final uri = await groupSocketUri(_groupId);
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (!mounted) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _reconnectAttempts = 0;
      _wsSub = channel.stream.listen(
        _onWsData,
        onError: (_) => _onWsClosed(),
        onDone: _onWsClosed,
        cancelOnError: true,
      );
    } catch (_) {
      _onWsClosed();
    } finally {
      _wsConnecting = false;
    }
  }

  void _onWsClosed() {
    _wsSub?.cancel();
    _wsSub = null;
    _channel = null;
    if (!mounted) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    _reconnectAttempts++;
    final secs = (1 << (_reconnectAttempts - 1)).clamp(1, 30);
    _reconnectTimer = Timer(Duration(seconds: secs), () {
      if (mounted && _channel == null) _connectWs();
    });
  }

  void _onWsData(dynamic data) {
    if (!mounted) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = m['id'] as int?;
    if (id == null || _messages.any((e) => e['id'] == id)) return;
    setState(() => _messages.add(m));
    _scrollToBottom();
  }

  void _startSafetyPoll() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _fetchNew());
  }

  Future<void> _fetchNew() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final res = await fetchGroupMessages(_groupId, _lastId);
      if (!mounted || res['ok'] != true) return;
      final incoming = List<Map<String, dynamic>>.from(res['messages'] ?? []);
      // Dedupe against anything the socket already delivered.
      final fresh =
          incoming.where((m) => !_messages.any((e) => e['id'] == m['id']));
      if (fresh.isNotEmpty) {
        setState(() => _messages.addAll(fresh));
        _scrollToBottom();
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await sendGroupMessage(_groupId, text);
    if (!mounted) return;
    if (res['ok'] == true) {
      _controller.clear();
      await _fetchNew(); // picks up my message (and a robot reply, if any)
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['error'] ?? 'Could not send.') as String)),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Group settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(group: widget.group)),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text('Say hi to the group!',
                              style: TextStyle(color: AppColors.tipText)),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) => _messageBlock(i),
                        ),
                ),
                _inputBar(),
              ],
            ),
    );
  }

  Widget _messageBlock(int i) {
    final m = _messages[i];
    final mine = (m['senderId'] as int) == _myUserId;
    final isRobot = m['isRobot'] == true;
    final corrected = (m['corrected'] ?? '') as String;
    final understood = m['understood'] != false;
    final name = (m['senderName'] ?? '') as String;
    // "Looks good" and the card follow the same per-group sharing rule as the
    // 1-on-1 chat: always on your own message, and on someone else's only if
    // they chose mode 1. Never on a robot message (it isn't coached).
    final sharesCoaching = mine || (m['senderPref'] ?? 1) == 1;
    // Only show a name label when the sender differs from the previous message,
    // to avoid repeating it in a run.
    final prev = i > 0 ? _messages[i - 1] : null;
    final showName = !mine &&
        name.isNotEmpty &&
        (prev == null ||
            prev['senderId'] != m['senderId'] ||
            (prev['isRobot'] == true) != isRobot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showName) _senderLabel(name, isRobot),
        _bubble(m['text'] as String, mine, isRobot),
        if (!isRobot && corrected.isNotEmpty)
          _correctionCard(
              m['text'] as String, corrected, (m['why'] ?? '') as String, mine),
        if (!isRobot && sharesCoaching && corrected.isEmpty && understood)
          _looksGoodNote(mine),
      ],
    );
  }

  Widget _senderLabel(String name, bool isRobot) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 6, bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRobot)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.smart_toy, size: 13, color: AppColors.navy),
                ),
              Text(name,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy)),
            ],
          ),
        ),
      );

  Widget _bubble(String text, bool mine, bool isRobot) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? AppColors.navy : AppColors.gold,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: mine ? Colors.white : AppColors.body,
              fontSize: 16,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _looksGoodNote(bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: const Padding(
        padding: EdgeInsets.only(left: 18, right: 18, bottom: 8, top: 2),
        child: Text(
          '✓ Looks good!',
          style: TextStyle(color: AppColors.correctionGreen, fontSize: 15),
        ),
      ),
    );
  }

  Future<void> _toggleSave(
      String original, String correction, String why) async {
    final nowSaved = await toggleSavedCorrection(original, correction, why);
    if (!mounted) return;
    setState(() {
      final key = correctionKey(original, correction);
      if (nowSaved) {
        _savedKeys.add(key);
      } else {
        _savedKeys.remove(key);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowSaved
            ? 'Saved to your review list'
            : 'Removed from your review list'),
      ),
    );
  }

  List<InlineSpan> _diffSpans(String original, String correction) {
    final spans = <InlineSpan>[];
    for (final s in wordDiff(original, correction)) {
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

  Widget _correctionCard(
      String original, String correction, String why, bool mine) {
    final maxW = MediaQuery.of(context).size.width * 0.88;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.only(left: 14, right: 14, top: 2, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    onTap: () => _toggleSave(original, correction, why),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        _savedKeys
                                .contains(correctionKey(original, correction))
                            ? Icons.bookmark
                            : Icons.bookmark_border,
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
                      color: AppColors.body, fontSize: 15, height: 1.55),
                  children: _diffSpans(original, correction),
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
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.pageBg,
          border:
              Border(top: BorderSide(color: AppColors.borderTint, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.navy,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: AppColors.yellow, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group settings: members, the robot, and this user's own per-group share
// preference (what the others see of their messages).
// ---------------------------------------------------------------------------
class GroupSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupSettingsScreen({super.key, required this.group});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  int _pref = 1;
  List<Map<String, dynamic>> _members = [];
  bool _hasRobot = false;
  String _robotName = '';

  int get _groupId => widget.group['groupId'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await groupInfo(_groupId);
    if (!mounted) return;
    if (res['ok'] == true) {
      final g = res['group'] as Map<String, dynamic>;
      setState(() {
        _pref = (g['myPref'] ?? 1) as int;
        _members = List<Map<String, dynamic>>.from(g['members'] ?? []);
        _hasRobot = g['hasRobot'] == true;
        _robotName = (g['robotName'] ?? '') as String;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _choose(int pref) async {
    if (_saving) return;
    setState(() {
      _pref = pref;
      _saving = true;
    });
    final res = await setGroupSharePref(_groupId, pref);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((res['error'] ?? 'Could not save.') as String)),
      );
    }
  }

  String _memberName(Map m) {
    final d = (m['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (m['username'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text((widget.group['name'] ?? 'Group').toString())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('MEMBERS',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.tipText)),
                ),
                if (_hasRobot)
                  ListTile(
                    leading: const CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.navy,
                      child: Icon(Icons.smart_toy,
                          size: 18, color: Colors.white),
                    ),
                    title: Text('$_robotName (robot)'),
                    subtitle: const Text('Replies when you mention its name'),
                  ),
                ..._members.map(
                  (m) => ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.gold,
                      child: Text(
                        _memberName(m).isNotEmpty
                            ? _memberName(m)[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppColors.body,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(_memberName(m)),
                  ),
                ),
                const Divider(height: 24),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text('WHAT THE GROUP SEES OF YOUR MESSAGES',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.tipText)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'You always still see your own correction card either way.',
                    style: TextStyle(color: AppColors.tipText, fontSize: 13),
                  ),
                ),
                for (final entry in groupShareLabels.entries)
                  _prefTile(entry.key, entry.value),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _prefTile(int value, String label) {
    final selected = _pref == value;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.navy : AppColors.tipText,
      ),
      title: Text(label),
      onTap: () => _choose(value),
    );
  }
}
