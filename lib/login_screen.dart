import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Login / sign-up screen — the second onboarding page.
//
// Follows the welcome screen's inverted palette (navy canvas, yellow accents)
// and Roboto type scale. Layout top→bottom: profile photo, login options,
// sign-in / create-account link, terms & policy.
//
// Colors mirror docs/welcome_onboarding_spec.md (kept local, same as the
// onboarding screen, because this screen uses the lighter yellow).
// ---------------------------------------------------------------------------

class _L {
  static const navy = Color(0xFF233A66);
  static const navyLight = Color(0xFF2C4676);
  static const navyDark = Color(0xFF1E3358);
  static const yellow = Color(0xFFFFE0A6);
  static const white = Color(0xFFFFFFFF);
  static const bodyText = Color(0xFFC6D2E6);
  static const googleBlue = Color(0xFF4285F4);
}

class LoginScreen extends StatelessWidget {
  final VoidCallback? onGoogle;
  final VoidCallback? onEmail;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

  const LoginScreen({
    super.key,
    this.onGoogle,
    this.onEmail,
    this.onTerms,
    this.onPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _L.navy,
      body: SafeArea(
        child: Stack(
          children: [
            // Same faint decorative circles as the welcome screen.
            _bgCircle(top: -40, right: -40, size: 160, color: _L.navyLight),
            _bgCircle(bottom: 70, left: -50, size: 130, color: _L.navyDark),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Push the group down toward the middle (larger below than
                  // above) rather than clustering it at the top.
                  const Spacer(flex: 3),

                  // 1. Profile photo (same haloed yellow hero as the welcome page).
                  _heroIcon(Icons.smart_toy_outlined, circle: 96, glyph: 46),
                  const SizedBox(height: 26),
                  const Text(
                    'Welcome to English Pal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: _L.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Log in to save your progress and streaks.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      color: _L.bodyText,
                    ),
                  ),

                  const SizedBox(height: 44),

                  // 2. Login options. Each one both logs in and, if the
                  // account is new, creates it — so there's no separate
                  // "create account" step.
                  _googleButton(),
                  const SizedBox(height: 14),
                  _emailButton(),

                  const Spacer(flex: 4),

                  // 4. Terms & policy.
                  _termsText(),
                  const SizedBox(height: 12),
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

  // --- profile photo --------------------------------------------------------

  Widget _heroIcon(IconData icon, {required double circle, required double glyph}) {
    return Container(
      width: circle,
      height: circle,
      decoration: const BoxDecoration(
        color: _L.yellow,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x26FFE0A6), // rgba(255,224,166,0.15)
            blurRadius: 0,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Icon(icon, size: glyph, color: _L.navy),
    );
  }

  // --- login option buttons -------------------------------------------------

  /// Primary: Continue with Google — light button (navy text on white).
  Widget _googleButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onGoogle ?? () {},
        style: FilledButton.styleFrom(
          backgroundColor: _L.white,
          foregroundColor: _L.navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'G',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _L.googleBlue,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Continue with Google',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// Secondary: Continue with email — outlined in yellow.
  Widget _emailButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onEmail ?? () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: _L.yellow,
          side: const BorderSide(color: _L.yellow, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.mail_outline, size: 20, color: _L.yellow),
            SizedBox(width: 10),
            Text(
              'Continue with email',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // --- terms & policy -------------------------------------------------------
  //
  // "Terms of Service" / "Privacy Policy" are styled as links but not tappable
  // yet (onTerms / onPrivacy unused for now). When wiring real URLs, convert
  // this to a StatefulWidget so a TapGestureRecognizer can be created and
  // disposed properly.

  Widget _termsText() {
    return Text.rich(
      textAlign: TextAlign.center,
      TextSpan(
        style: const TextStyle(fontSize: 15, height: 1.5, color: _L.bodyText),
        children: const [
          TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: TextStyle(color: _L.yellow, fontWeight: FontWeight.w500),
          ),
          TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(color: _L.yellow, fontWeight: FontWeight.w500),
          ),
          TextSpan(text: '.'),
        ],
      ),
    );
  }
}
