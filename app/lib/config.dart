// Valeurs fournies au lancement :
// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Rayon de recherche par défaut (mètres) et maximum proposé à l'utilisateur.
const defaultRadiusM = 1000;
const smallRadiusM = 500;

/// Centre de repli (Cotonou) si la localisation est refusée.
const fallbackLat = 6.3703;
const fallbackLng = 2.3912;
