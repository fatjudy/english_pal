import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'
    show
        kPersonalityOptions,
        kHobbyOptions,
        kLevelOptions,
        saveProfileToCloud;

// ---------------------------------------------------------------------------
// Account setup — the 3-page flow a new user completes after "Create account".
//
//   1. Name + personality
//   2. Topics the pal loves talking about
//   3. English level (with a short explanation of each)
//
// Follows the welcome/login spec: navy canvas, yellow accents, Roboto scale.
// On finish it saves the profile and calls onDone (→ chat).
// ---------------------------------------------------------------------------

class _S {
  static const navy = Color(0xFF233A66);
  static const navyLight = Color(0xFF2C4676);
  static const navyDark = Color(0xFF1E3358);
  static const yellow = Color(0xFFFFE0A6);
  static const white = Color(0xFFFFFFFF);
  static const bodyText = Color(0xFFC6D2E6);
  static const dotInactive = Color(0xFF41527A);
}

// Short, friendly explanation shown under each level.
const Map<String, String> _levelBlurbs = {
  'Beginner':
      'Just starting out — simple words, short sentences, and lots of encouragement.',
  'Intermediate':
      'You can chat about everyday things but want to get smoother and more confident.',
  'Advanced':
      'Comfortable and fluent — polishing nuance, idioms, and natural phrasing.',
};

class AccountSetupScreen extends StatefulWidget {
  /// Called after the profile is saved (navigate to the chat).
  final VoidCallback onDone;

  const AccountSetupScreen({super.key, required this.onDone});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final PageController _controller = PageController();
  final TextEditingController _nameController = TextEditingController();
  int _page = 0;

  final Set<String> _personalities = {};
  final Set<String> _interests = {};
  String _level = 'Intermediate';

  static const int _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;

  void _next() => _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

  void _back() {
    if (_page == 0) {
      Navigator.of(context).maybePop();
    } else {
      _controller.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    final name =
        _nameController.text.trim().isEmpty ? 'Mia' : _nameController.text.trim();
    final interests = _interests.toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('palName', name);
    await prefs.setStringList('personality', _personalities.toList());
    // The 3-page flow has no separate "hobbies" page, so the pal's chosen
    // topics serve as both its hobbies and the conversation topics.
    await prefs.setStringList('hobbies', interests);
    await prefs.setStringList('topics', interests);
    await prefs.setString('level', _level);
    await saveProfileToCloud({
      'palName': name,
      'personality': _personalities.toList(),
      'hobbies': interests,
      'topics': interests,
      'level': _level,
    });
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _S.navy,
      body: SafeArea(
        child: Stack(
          children: [
            _bgCircle(top: -40, right: -40, size: 160, color: _S.navyLight),
            _bgCircle(bottom: 70, left: -50, size: 130, color: _S.navyDark),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _pageName(),
                  _pageInterests(),
                  _pageLevel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- shared frame ---------------------------------------------------------

  Widget _frame({
    required String title,
    required String subtitle,
    required Widget content,
    required Widget button,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        // Header: back button + step dots.
        Row(
          children: [
            _iconBtn(Icons.arrow_back, _back),
            const Spacer(),
            _stepDots(),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: _S.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 17, height: 1.5, color: _S.bodyText),
        ),
        const SizedBox(height: 28),
        Expanded(child: SingleChildScrollView(child: content)),
        const SizedBox(height: 12),
        button,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _stepDots() {
    return Row(
      children: List.generate(_pageCount, (i) {
        final bool active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? 22 : 7,
          height: 7,
          margin: EdgeInsets.only(right: i == _pageCount - 1 ? 0 : 6),
          decoration: BoxDecoration(
            color: active ? _S.yellow : _S.dotInactive,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: _S.bodyText, size: 22),
      splashRadius: 22,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  // --- reusable pieces ------------------------------------------------------

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _S.yellow : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          // Always a yellow frame, to keep the palette consistent.
          border: Border.all(color: _S.yellow, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? _S.navy : _S.bodyText,
          ),
        ),
      ),
    );
  }

  Widget _chipWrap(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final o in options)
          _chip(o, selected.contains(o), () {
            setState(() {
              if (selected.contains(o)) {
                selected.remove(o);
              } else {
                selected.add(o);
              }
            });
          }),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _S.yellow,
          foregroundColor: _S.navy,
          disabledBackgroundColor: _S.yellow.withValues(alpha: 0.35),
          disabledForegroundColor: _S.navy.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  // --- page 1: name + personality ------------------------------------------

  Widget _pageName() {
    return _frame(
      title: 'Create your pal',
      subtitle: 'Give your AI partner a name and a personality.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Name',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _S.white,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: _S.navy, fontSize: 17),
            decoration: InputDecoration(
              hintText: 'e.g. Mia, Leo, Aria…',
              hintStyle: TextStyle(color: _S.navy.withValues(alpha: 0.4)),
              filled: true,
              fillColor: _S.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _S.yellow, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Personality',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _S.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick a few traits.',
            style: TextStyle(fontSize: 15, color: _S.bodyText),
          ),
          const SizedBox(height: 14),
          _chipWrap(kPersonalityOptions, _personalities),
        ],
      ),
      button: _primaryButton('Next', _nameOk ? _next : null),
    );
  }

  // --- page 2: topics the pal loves ----------------------------------------

  Widget _pageInterests() {
    return _frame(
      title: 'What do you both love?',
      subtitle: 'Pick the topics your pal enjoys chatting about.',
      content: _chipWrap(kHobbyOptions, _interests),
      button: _primaryButton('Next', _next),
    );
  }

  // --- page 3: english level -----------------------------------------------

  Widget _pageLevel() {
    return _frame(
      title: 'Your English level',
      subtitle: 'This helps your pal match how it talks to you.',
      content: Column(
        children: [
          for (final level in kLevelOptions)
            _levelCard(level, _levelBlurbs[level] ?? '', _level == level, () {
              setState(() => _level = level);
            }),
        ],
      ),
      button: _primaryButton('Start chatting', _finish),
    );
  }

  Widget _levelCard(String level, String desc, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _S.yellow.withValues(alpha: 0.10) : _S.navyLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _S.yellow : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? _S.yellow : _S.dotInactive,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _S.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: _S.bodyText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- background decoration ------------------------------------------------

  Widget _bgCircle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
