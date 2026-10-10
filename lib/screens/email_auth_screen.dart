import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/email_auth_validation.dart';

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key, this.linkCurrentAccount = false});

  /// When true, creates an email credential linked to the signed-in Firebase
  /// user so the current UID and its backend credits remain unchanged.
  final bool linkCurrentAccount;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirmation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _creating = widget.linkCurrentAccount;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    return EmailAuthValidation.password(value, forRegistration: _creating);
  }

  String? _validateConfirmation(String? value) {
    return EmailAuthValidation.confirmation(value, _password.text);
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await AuthService.instance.createEmailAccount(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await AuthService.instance.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final error = EmailAuthValidation.email(_email.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordResetEmail(_email.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) =>
      EmailAuthValidation.messageForError(error);

  @override
  Widget build(BuildContext context) {
    final linking = widget.linkCurrentAccount;
    final title = linking
        ? 'Save your studio'
        : _creating
        ? 'Create account'
        : 'Sign in with Email';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0B12),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      linking
                          ? 'Add an email and password to keep this same account, credits, and creations.'
                          : 'Use your email to securely access your VYRO account.',
                      style: const TextStyle(
                        color: Color(0xFFAAA2B3),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: EmailAuthValidation.email,
                      decoration: _decoration(
                        'Email address',
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      textInputAction: _creating
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: [
                        _creating
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      validator: _validatePassword,
                      decoration:
                          _decoration(
                            'Password',
                            Icons.lock_outline_rounded,
                          ).copyWith(
                            helperText: _creating
                                ? 'At least 8 characters and one number.'
                                : null,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                      onFieldSubmitted: _creating ? null : (_) => _submit(),
                    ),
                    if (_creating) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !_busy,
                        obscureText: !_showConfirmation,
                        textInputAction: TextInputAction.done,
                        validator: _validateConfirmation,
                        decoration:
                            _decoration(
                              'Confirm password',
                              Icons.lock_outline_rounded,
                            ).copyWith(
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _showConfirmation = !_showConfirmation,
                                ),
                                icon: Icon(
                                  _showConfirmation
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFFFA6B8)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 21,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                linking
                                    ? 'Link email to this account'
                                    : _creating
                                    ? 'Create account'
                                    : 'Sign in',
                              ),
                      ),
                    ),
                    if (!linking && !_creating)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    if (!linking) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                        child: Text(
                          _creating
                              ? 'Already have an account? Sign in'
                              : 'New to VYRO? Create an account',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: const Color(0xFF17131F),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF3A3145)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF3A3145)),
    ),
  );
}
