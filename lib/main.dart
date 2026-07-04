import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String summary = '';

  final List<Map<String, dynamic>> messages = [
    {'text': 'Hi! I am Mia. How was your weekend?', 'isUser': false},
    {'text': 'It was great, thanks! I went hiking.', 'isUser': true},
    {'text': 'Nice! Did you go alone or with friends?', 'isUser': false},
  ];

  Future<void> _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    final userMessage = {'text': text, 'isUser': true, 'correction': ''};
    setState(() {
      messages.add(userMessage);
    });
    _controller.clear();

    final recent = messages.length > 16
        ? messages.sublist(messages.length - 16)
        : messages;

    final response = await http.post(
      Uri.parse('http://127.0.0.1:8000/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'summary': summary,
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
      messages.add({'text': data['reply'], 'isUser': false});
    });
    }

  Widget _messageBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      ),
    );
  }

  Widget _correctionCard(String correction) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(right: 12, bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('Correction: $correction'),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English Pal'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
                        _correctionCard(message['correction']),
                    ],
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}