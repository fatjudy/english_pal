import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      home: SetupScreen(),
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
  final ScrollController _scrollController = ScrollController(); 
  bool _isMiaTyping = false;
  String summary = '';
  String palName = 'Mia';
  List<String> personality = [];
  List<String> hobbies = [];
  List<String> topics = [];
  String level = 'Intermediate';
  String get _backendUrl =>
      kIsWeb ? 'http://127.0.0.1:8000/chat' : 'http://10.0.2.2:8000/chat';
  
  final List<Map<String, dynamic>> messages = [
    {'text': "Hi! I'm Mia. How's your day going?", 'isUser': false},
  ];

  @override
  void initState() {
    super.initState();
    _loadChat();
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
    palName = prefs.getString('palName') ?? 'Mia';
    personality = prefs.getStringList('personality') ?? [];
    hobbies = prefs.getStringList('hobbies') ?? [];
    topics = prefs.getStringList('topics') ?? [];
    level = prefs.getString('level') ?? 'Intermediate';
    final savedMessages = prefs.getString('messages');
    final savedSummary = prefs.getString('summary');

    if (savedMessages != null) {
      final decoded = jsonDecode(savedMessages) as List;
      setState(() {
        messages.clear();
        messages.addAll(decoded.cast<Map<String, dynamic>>());
      });
    }
    else {
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
    _scrollToBottom();
  }

  Future<void> _saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('messages', jsonEncode(messages));
    await prefs.setString('summary', summary);
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

  Future<void> _resetApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SetupScreen()),
      (route) => false,
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
  
    Widget _looksGoodNote() {
    return const Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: 16, bottom: 8),
        child: Text(
          '✓ Looks good!',
          style: TextStyle(color: Colors.green, fontSize: 12),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Mia is typing…'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English Pal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Start over',
            onPressed: _resetApp,
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
                        _correctionCard(message['correction']),
                      if (message['isUser'] == true &&
                          message['checked'] == true &&
                          message['correction'] == '')
                        _looksGoodNote(),                      
                    ],
                  ),
              ],
            ),
          ),
          if (_isMiaTyping) _typingIndicator(),
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

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final PageController _pageController = PageController();
  final List<String> _personalityOptions = [
    'Friendly', 'Funny', 'Calm & Patient', 'Encouraging', 'Curious',
    'Witty', 'Chatty', 'Gentle', 'Enthusiastic', 'Thoughtful',
  ];
  final Set<String> _selectedPersonalities = {};

  final List<String> _hobbyOptions = [
    'Sports', 'Music', 'Movies & TV', 'Gaming', 'Cooking', 'Travel',
    'Books', 'Art', 'Technology', 'Nature', 'Fitness', 'Pets',
    'Photography', 'Science',
  ];
  final Set<String> _selectedHobbies = {};

  final List<String> _topicOptions = [
    'Daily life', 'Work/Career', 'Travel English', 'Job interviews',
    'Small talk', 'Hobbies', 'News', 'Food', 'Culture', 'Studying abroad',
    'Shopping', 'Health',
  ];
  final Set<String> _selectedTopics = {};

  String _selectedLevel = 'Intermediate';

  Widget _chipSection(String label, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
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

  Widget _nextButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed: () {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        child: const Text('Next'),
      ),
    );
  }

  Widget _wizardPage(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('palName', _nameController.text);
    await prefs.setStringList('personality', _selectedPersonalities.toList());
    await prefs.setStringList('hobbies', _selectedHobbies.toList());
    await prefs.setStringList('topics', _selectedTopics.toList());
    await prefs.setString('level', _selectedLevel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your pal')),
      body: PageView(
        controller: _pageController,
        children: [
          _wizardPage([
            const SizedBox(height: 20),
            const Text('What would you like to name your pal?'),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'e.g. Mia, Leo, Aria...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _chipSection('Pick a few personality traits:', _personalityOptions,
                _selectedPersonalities),
            _nextButton(),
          ]),
          _wizardPage([
            const SizedBox(height: 20),
            _chipSection("What are your pal's hobbies?", _hobbyOptions,
                _selectedHobbies),
            _nextButton(),
          ]),
          _wizardPage([
            const SizedBox(height: 20),
            _chipSection('What do you want to talk about?', _topicOptions,
                _selectedTopics),
            _nextButton(),
          ]),
          _wizardPage([
            const SizedBox(height: 20),
            const Text('Your English level:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final level in ['Beginner', 'Intermediate', 'Advanced'])
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
              child: ElevatedButton(
                onPressed: () async {
                  await _saveSettings();
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ChatScreen()),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Start', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}