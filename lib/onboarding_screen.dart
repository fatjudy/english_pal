import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Welcome / onboarding screen — a 4-slide carousel that ends on sign up / log in.
//
// This screen INVERTS the usual layout: navy is the background (the canvas),
// and yellow/gold are the accents. The spec gives this screen its own yellow
// and gold hexes (lighter than the chat's), so the tokens live here locally
// instead of touching the shared AppColors used everywhere else.
// ---------------------------------------------------------------------------

class _Onb {
  static const navy = Color(0xFF233A66); // page background, text on yellow
  static const navyLight = Color(0xFF2C4676); // faint top-right circle
  static const navyDark = Color(0xFF1E3358); // faint bottom-left circle
  static const yellow = Color(0xFFFFE0A6); // hero circles, button, active dot
  static const gold = Color(0xFFF2D79A); // tutor bubble in slide-2 preview
  static const goldText = Color(0xFF4A3A17); // text on the gold tutor bubble
  static const goldAccent = Color(0xFFE8C583); // correction card left border
  static const white = Color(0xFFFFFFFF); // headlines, user bubble, card
  static const bodyText = Color(0xFFC6D2E6); // body text on navy
  static const dotInactive = Color(0xFF41527A); // inactive page dots

  // Correction signal colors (same universal red/green as the chat).
  static const deletionRed = Color(0xFFC0392B);
  static const correctionGreen = Color(0xFF2E7D32);
  static const tipIcon = Color(0xFFD7A859);
  static const tipText = Color(0xFF6B6862);
}

class OnboardingScreen extends StatefulWidget {
  /// Called when the user taps "Sign up" on the last slide.
  final VoidCallback? onSignUp;

  /// Called when the user taps the "Log in" link on the last slide.
  final VoidCallback? onLogin;

  const OnboardingScreen({super.key, this.onSignUp, this.onLogin});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  // "Swipe to start" hint on slide 1 — hidden for good after the first swipe.
  bool _showHint = true;

  static const int _slideCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool onLastSlide = _page == _slideCount - 1;

    return Scaffold(
      backgroundColor: _Onb.navy,
      body: SafeArea(
        child: Stack(
          children: [
            // Faint decorative circles behind everything.
            _bgCircle(
              top: -40,
              right: -40,
              size: 160,
              color: _Onb.navyLight,
            ),
            _bgCircle(
              bottom: 70,
              left: -50,
              size: 130,
              color: _Onb.navyDark,
            ),

            // Slides + bottom chrome.
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() {
                      _page = i;
                      if (i > 0) _showHint = false;
                    }),
                    children: [
                      _slideGreeting(),
                      _slideChat(),
                      _slideCorrection(),
                      _slideSignUp(),
                    ],
                  ),
                ),

                // Dots (left) + Start button (right). Hidden on the last slide,
                // where the in-slide "Sign up" button takes over.
                if (!onLastSlide) _bottomChrome(),
              ],
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

  // --- shared slide skeleton ------------------------------------------------

  /// The shared column: optional big title, a flexing central visual, a
  /// headline, and one line of body text.
  Widget _slide({
    String? title,
    required Widget visual,
    required String headline,
    required String body,
    Widget? footer,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          if (title != null)
            Text(
              title,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: _Onb.yellow,
              ),
            ),
          // The visual flexes to fill available height so slides stay balanced.
          Expanded(child: Center(child: visual)),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _Onb.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              height: 1.5,
              color: _Onb.bodyText,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 28),
            footer,
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// A yellow circle with a navy icon inside and a soft translucent halo.
  Widget _heroIcon(IconData icon, {required double circle, required double glyph}) {
    return Container(
      width: circle,
      height: circle,
      decoration: BoxDecoration(
        color: _Onb.yellow,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x26FFE0A6), // rgba(255,224,166,0.15)
            blurRadius: 0,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Icon(icon, size: glyph, color: _Onb.navy),
    );
  }

  // --- slide 1: greeting + meet the AI -------------------------------------

  Widget _slideGreeting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The three components (title, photo, text block) sit in a band that
          // spans 60% of the slide height, centered — ~20% empty above/below.
          return Center(
            child: SizedBox(
              height: constraints.maxHeight * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Hi there!',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: _Onb.yellow,
                    ),
                  ),
                  _heroIcon(Icons.smart_toy_outlined, circle: 140, glyph: 66),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Meet your English partner',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _Onb.white,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'A friendly AI that chats with you anytime, at your own pace.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.5,
                          color: _Onb.bodyText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- slide 2: chat freely (mini chat preview) ----------------------------

  Widget _slideChat() {
    return _slide(
      visual: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _previewBubble(
            text: 'What did you do this weekend?',
            isUser: false,
          ),
          const SizedBox(height: 10),
          _previewBubble(
            text: 'I go to the beach with friends!',
            isUser: true,
          ),
        ],
      ),
      headline: 'Chat about anything',
      body: 'No scripts, no pressure. Talk about your day, hobbies, or plans.',
    );
  }

  Widget _previewBubble({required String text, required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isUser ? _Onb.white : _Onb.gold,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 17,
            height: 1.45,
            color: isUser ? _Onb.navy : _Onb.goldText,
          ),
        ),
      ),
    );
  }

  // --- slide 3: the correction feature -------------------------------------

  Widget _slideCorrection() {
    return _slide(
      visual: _correctionCard(),
      headline: 'Improve as you go',
      body:
          'I gently correct your English and explain why — no red pen, no judgment.',
    );
  }

  Widget _correctionCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: const BoxDecoration(
        color: _Onb.white,
        border: Border(
          left: BorderSide(color: _Onb.goldAccent, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x38000000), // rgba(0,0,0,0.22)
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row.
          Row(
            children: const [
              Icon(Icons.check, size: 15, color: _Onb.navy),
              SizedBox(width: 5),
              Text(
                'Correction',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _Onb.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // Corrected sentence: "I go→went to the beach with friends!"
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 15,
                height: 1.55,
                color: Color(0xFF2A2A2A),
              ),
              children: const [
                TextSpan(text: 'I '),
                TextSpan(
                  text: 'go',
                  style: TextStyle(
                    color: _Onb.deletionRed,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                TextSpan(text: ' '),
                TextSpan(
                  text: 'went',
                  style: TextStyle(
                    color: _Onb.correctionGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' to the beach with friends!'),
              ],
            ),
          ),
          const SizedBox(height: 7),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0E6D0)),
          const SizedBox(height: 7),
          // Tip row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.lightbulb_outline, size: 14, color: _Onb.tipIcon),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  "Past tense: 'go' → 'went'.",
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: _Onb.tipText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- slide 4: sign up / log in (the close) -------------------------------

  Widget _slideSignUp() {
    return _slide(
      visual: _heroIcon(Icons.auto_awesome, circle: 110, glyph: 52),
      headline: 'Ready to start?',
      body: 'Create an account to save your progress and streaks.',
      footer: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // Stays visually active; wires up when the next page exists.
              onPressed: widget.onSignUp ?? () {},
              style: FilledButton.styleFrom(
                backgroundColor: _Onb.yellow,
                foregroundColor: _Onb.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Sign up'),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: widget.onLogin,
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 15, color: _Onb.bodyText),
                children: const [
                  TextSpan(text: 'Already have an account? '),
                  TextSpan(
                    text: 'Log in',
                    style: TextStyle(
                      color: _Onb.yellow,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- bottom chrome: page-dots (left) + swipe hint (right) ----------------

  Widget _bottomChrome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: List.generate(_slideCount, (i) {
              final bool active = i == _page;
              return Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(right: i == _slideCount - 1 ? 0 : 7),
                decoration: BoxDecoration(
                  color: active ? _Onb.yellow : _Onb.dotInactive,
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
          // "Swipe to start →" — only on slide 1, fades out after first swipe.
          AnimatedOpacity(
            opacity: _showHint ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: const _SwipeHint(),
          ),
        ],
      ),
    );
  }
}

// A small "Swipe to start →" cue with a gently nudging arrow.
class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _dx =
      Tween<double>(begin: 0, end: 4).animate(
    CurvedAnimation(parent: _nudge, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Swipe to start',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _Onb.yellow,
          ),
        ),
        const SizedBox(width: 4),
        AnimatedBuilder(
          animation: _dx,
          builder: (context, child) => Transform.translate(
            offset: Offset(_dx.value, 0),
            child: child,
          ),
          child: const Icon(
            Icons.arrow_forward,
            size: 16,
            color: _Onb.yellow,
          ),
        ),
      ],
    );
  }
}
