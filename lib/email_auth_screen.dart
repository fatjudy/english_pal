import 'package:flutter/material.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// "Continue with email" screen. A Log in / Create account toggle at the top
// lets the user pick their intent; the backend /auth/continue endpoint enforces
// it (log in requires an existing account; create requires a new email). On
// success it stores the token, then calls onSuccess.
//
// Same inverted palette as the login screen (navy canvas, yellow accents).
// ---------------------------------------------------------------------------

class _A {
  static const navy = Color(0xFF233A66);
  static const navyLight = Color(0xFF2C4676);
  static const yellow = Color(0xFFFFE0A6);
  static const white = Color(0xFFFFFFFF);
  static const bodyText = Color(0xFFC6D2E6);
  static const error = Color(0xFFFF6E80);
}

class EmailAuthScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const EmailAuthScreen({super.key, required this.onSuccess});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  String _mode = 'login'; // 'login' or 'signup'
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result =
        await continueWithEmail(email: email, password: password, mode: _mode);

    if (!mounted) return;

    if (result['ok'] == true) {
      await saveAuth(result);
      if (!mounted) return;
      widget.onSuccess();
    } else {
      setState(() {
        _loading = false;
        _error = (result['error'] ?? 'Something went wrong.') as String;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signup = _mode == 'signup';
    return Scaffold(
      backgroundColor: _A.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _A.bodyText,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Continue with email',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700, color: _A.white),
              ),
              const SizedBox(height: 20),

              // Log in / Create account toggle.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _A.navyLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: _segment('Log in', 'login')),
                    Expanded(child: _segment('Create account', 'signup')),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                signup
                    ? 'Create an account with your email and a password.'
                    : 'Log in with your email and password.',
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: _A.bodyText),
              ),
              const SizedBox(height: 20),
              _field(_email, 'Email', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _field(_password, 'Password', obscure: true),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: _A.error, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _A.yellow,
                    foregroundColor: _A.navy,
                    disabledBackgroundColor: _A.yellow.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _A.navy),
                        )
                      : Text(
                          signup ? 'Create account' : 'Log in',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(String label, String mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: _loading
          ? null
          : () => setState(() {
                _mode = mode;
                _error = null;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _A.yellow : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? _A.navy : _A.bodyText,
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: !obscure,
      style: const TextStyle(color: _A.navy, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: _A.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _A.yellow, width: 2),
        ),
      ),
    );
  }
}
