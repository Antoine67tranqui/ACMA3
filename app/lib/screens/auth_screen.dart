import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  bool _signUp = false;
  bool _driver = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_signUp) {
        final res = await db.auth.signUp(email: _email.text.trim(), password: _password.text);
        final uid = res.user?.id;
        if (uid == null || res.session == null) {
          throw const AuthException('Confirmez votre e-mail puis connectez-vous.');
        }
        await db.from('profiles').insert({
          'id': uid,
          'role': _driver ? 'driver' : 'client',
          'full_name': _name.text.trim(),
          'phone': _phone.text.trim(),
        });
        if (_driver) {
          await db.from('drivers').insert({'id': uid, 'plate': _plate.text.trim()});
        }
      } else {
        await db.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("Impossible de terminer l'opération. Réessayez.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Zemi', style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 4),
                    const Text('Trouvez un zémidjan près de vous'),
                    const SizedBox(height: 24),
                    if (_signUp) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Client')),
                          ButtonSegment(value: true, label: Text('Zémidjan')),
                        ],
                        selected: {_driver},
                        onSelectionChanged: (s) => setState(() => _driver = s.first),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Nom complet'),
                          validator: _required),
                      TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Téléphone'),
                          validator: _required),
                      if (_driver)
                        TextFormField(
                            controller: _plate,
                            decoration: const InputDecoration(labelText: 'Plaque de la moto'),
                            validator: _required),
                    ],
                    TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: _required),
                    TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Mot de passe (6+ caractères)'),
                        validator: (v) => (v ?? '').length < 6 ? '6 caractères minimum' : null),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_signUp ? 'Créer mon compte' : 'Se connecter'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _signUp = !_signUp),
                      child: Text(_signUp ? 'J\'ai déjà un compte' : 'Créer un compte'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
