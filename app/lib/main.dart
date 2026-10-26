import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/client_home.dart';
import 'screens/driver_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const ZemiApp());
}

class ZemiApp extends StatelessWidget {
  const ZemiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Zemi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B7A3E)),
          useMaterial3: true,
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, _) {
          if (db.auth.currentSession == null) return const AuthScreen();
          return FutureBuilder<Map<String, dynamic>?>(
            // Clé sur l'utilisateur pour recharger le rôle après connexion.
            key: ValueKey(db.auth.currentUser!.id),
            future: db.from('profiles').select('role').eq('id', db.auth.currentUser!.id).maybeSingle(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final role = snap.data?['role'];
              if (role == 'driver') return const DriverHome();
              if (role == 'client') return const ClientHome();
              return const AuthScreen(); // profil manquant : recommencer l'inscription
            },
          );
        },
      );
}
