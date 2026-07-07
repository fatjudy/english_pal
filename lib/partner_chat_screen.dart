import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// One-on-one chat with a human friend. Loads the conversation, shows the
// message history, and lets you send messages. New replies are pulled with the
// refresh button for now — Piece 3 adds automatic polling. (Correction cards
// come in Phase 3.)
// ---------------------------------------------------------------------------

class PartnerChatScreen extends StatefulWidget {
  final Map<String, dynamic> friend;

  const PartnerChatScreen({super.key, required this.friend});

  @override
  State<PartnerChatScreen> createState() => _PartnerChatScreenState();
}

class _PartnerChatScreenState extends State<PartnerChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  int? _conversationId;
  int _myUserId = 0;
  bool _loading = true;
  bool _sending = false;
  bool _fetching = false; // guards against overlapping fetches
  Timer? _pollTimer;
  String? _error;

  String get _name {
    final d = (widget.friend['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (widget.friend['username'] ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Ask the server for new messages every 2 seconds while this chat is open, so
  // replies appear on their own. Cancelled in dispose when we leave the screen.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _fetchNew());
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId') ?? 0;
    final res = await openConversation(widget.friend['userId'] as int);
    if (!mounted) return;
    if (res['ok'] != true) {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? 'Could not open the chat.') as String;
      });
      return;
    }
    _conversationId = res['conversationId'] as int;
    await _fetchNew();
    if (!mounted) return;
    setState(() => _loading = false);
    _startPolling();
  }

  int get _lastId => _messages.isEmpty ? 0 : _messages.last['id'] as int;

  Future<void> _fetchNew() async {
    if (_conversationId == null || _fetching) return;
    _fetching = true;
    try {
      final res = await fetchPartnerMessages(_conversationId!, _lastId);
      if (!mounted || res['ok'] != true) return;
      final incoming = List<Map<String, dynamic>>.from(res['messages'] ?? []);
      if (incoming.isNotEmpty) {
        setState(() => _messages.addAll(incoming));
        _scrollToBottom();
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _conversationId == null || _sending) return;
    setState(() => _sending = true);
    final res = await sendPartnerMessage(_conversationId!, text);
    if (!mounted) return;
    if (res['ok'] == true) {
      _controller.clear();
      await _fetchNew(); // picks up my message (and any replies)
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
        title: Text(_name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for new messages',
            onPressed: _loading ? null : _fetchNew,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.tipText)),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Text('Say hi to $_name!',
                                  style: const TextStyle(
                                      color: AppColors.tipText)),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final m = _messages[i];
                                return _bubble(m['text'] as String,
                                    (m['senderId'] as int) == _myUserId);
                              },
                            ),
                    ),
                    _inputBar(),
                  ],
                ),
    );
  }

  Widget _bubble(String text, bool mine) {
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

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.pageBg,
          border: Border(
              top: BorderSide(color: AppColors.borderTint, width: 0.5)),
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
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
