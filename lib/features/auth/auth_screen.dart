import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/repositories/user_data_repository.dart';

class AuthScreen extends StatefulWidget {
  final String? initialMode; // ✅ Add this
  const AuthScreen({
    super.key,
    this.initialMode, // ✅ Add this
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
  
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  // ✅ Only essential field for sign-up
  final _fullName = TextEditingController();

  bool _obscure = true;
  bool _isBusy = false;
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    // ✅ MOVE THIS HERE (from dispose)
    _isSignUp = widget.initialMode == 'signup'; // true if signup, false otherwise
  }
  
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _isBusy = true);

    try {
      final auth = FirebaseAuth.instance;
      final userDataRepo = UserDataRepository();
      UserCredential cred;

      if (_isSignUp) {
        // Create account
        cred = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );

        final user = cred.user;
        if (user != null) {
          // Update Firebase Auth profile
          await user.updateDisplayName(_fullName.text.trim());

          // Initialize user profile in new structure
          await userDataRepo.initializeUserProfile(
            userId: user.uid,
            email: user.email ?? '',
            displayName: _fullName.text.trim(),
          );

          // Build keyword array for mentions (if you use chat)
          List<String> keywords(String s) {
            final base = s.trim().toLowerCase();
            final parts = base.split(RegExp(r'[\s,_\-]+')).where((e) => e.isNotEmpty).toList();
            return {base, ...parts}.toList();
          }

          // ✅ Store minimal profile info - user can complete profile later
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('profile')
              .doc('info')
              .set({
            'uid': user.uid,
            'email': user.email,
            'name': _fullName.text.trim(),
            'name_keywords': keywords(_fullName.text),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            // ✅ Optional fields set to empty - can be filled in profile later
            'phone': '',
            'company': '',
            'role': '',
            'address': '',
          }, SetOptions(merge: true));
        }
      } else {
        // Sign in
        cred = await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );

        // Initialize profile if this is first login after migration
        final user = cred.user;
        if (user != null) {
          await userDataRepo.initializeUserProfile(
            userId: user.uid,
            email: user.email ?? '',
            displayName: user.displayName,
          );
        }
      }

      if (!mounted) return;

      // Navigate to dashboard
      Navigator.pushNamedAndRemoveUntil(
        context,
        Paths.dashboard,
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyAuthError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email to reset password')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyAuthError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'That email is already in use.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isSignUp ? 'Create Account' : 'Login';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back to welcome',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(
              context,
              Paths.welcome,
              (route) => false,
            );
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 16),

                      // ✅ SIMPLIFIED: Only Full Name for sign-up
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _fullName,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(),
                            helperText: 'How should we address you?',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // --- EMAIL / PASSWORD ---
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          helperText: _isSignUp ? 'Minimum 6 characters' : null,
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password is required';
                          if (v.length < 6) return 'Minimum 6 characters';
                          return null;
                        },
                      ),

                      // ✅ NEW: Helpful message for sign-up
                      if (_isSignUp) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You can add company, phone & other details in your profile later',
                                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!_isSignUp)
                            TextButton(
                              onPressed: _isBusy ? null : _forgotPassword,
                              child: const Text('Forgot password?'),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: _isBusy ? null : () => setState(() => _isSignUp = !_isSignUp),
                            child: Text(_isSignUp ? 'Have an account? Login' : 'Create account'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isBusy ? null : _submit,
                          child: _isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_isSignUp ? 'Create Account' : 'Login'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}