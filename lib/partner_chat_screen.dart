import 'package:flutter/material.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// One-on-one chat with a human friend. Placeholder for now — Phase 2 builds the
// real messaging here (send/fetch messages + correction cards for both people).
// ---------------------------------------------------------------------------

class PartnerChatScreen extends StatelessWidget {
  final Map<String, dynamic> friend;

  const PartnerChatScreen({super.key, required this.friend});

  String get _name {
    final d = (friend['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (friend['username'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Messaging your friends is coming in the next step.\n\n'
            'This is where your two-person chat — with correction cards for '
            'both of you — will live.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.tipText, fontSize: 15, height: 1.5),
          ),
        ),
      ),
    );
  }
}
