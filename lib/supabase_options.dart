/// Supabase configuration for the application.
///
/// Replace the placeholder values below with your actual Supabase project
/// credentials. You can find these in your Supabase dashboard:
///   https://supabase.com/dashboard → Select Project → Settings → API
///
/// Required:
///   - [supabaseUrl]: Your project URL (e.g. https://xyzcompany.supabase.co)
///   - [supabaseAnonKey]: Your project's anon/public API key
class SupabaseOptions {
  // ──────────────────────────────────────────────────────────────────────────
  // 🔑  ADD YOUR SUPABASE CONNECTION STRINGS HERE
  // ──────────────────────────────────────────────────────────────────────────

  /// Your Supabase project URL.
  /// Found at: Supabase Dashboard → Settings → API → Project URL
  static const String supabaseUrl = 'https://cqkkpgkmsqmksctpuacc.supabase.co';

  /// Your Supabase anonymous (public) key.
  /// Found at: Supabase Dashboard → Settings → API → Project API keys → anon / public
  static const String supabaseAnonKey =
      'sb_publishable_1N7u2WS4G_5qdmRrVRQwhg_I5_LzK9w';
}
