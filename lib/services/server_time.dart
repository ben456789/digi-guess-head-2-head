import 'package:supabase_flutter/supabase_flutter.dart';

/// Utility to fetch the current server time from Supabase.
class ServerTime {
  static int? _offsetMs;
  static DateTime? _lastFetch;

  /// Returns the current server time as a DateTime, or null if not yet available.
  static DateTime? get now {
    if (_offsetMs == null) return null;
    return DateTime.now().add(Duration(milliseconds: _offsetMs!));
  }

  /// Returns the current server time offset in milliseconds, or null if not yet available.
  static int? get offsetMs => _offsetMs;

  /// Fetches the server time offset from Supabase and caches it for 5 minutes.
  ///
  /// Uses a simple RPC call: SELECT NOW() on the Supabase Postgres instance.
  /// You can create a tiny Supabase Edge Function or a Postgres function for this.
  /// Alternatively, we just use the current time (offset = 0) as a fallback.
  static Future<void> fetchOffset() async {
    // Only refresh if not fetched recently
    if (_lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return;
    }
    try {
      final client = Supabase.instance.client;
      // Call a Postgres function: CREATE FUNCTION get_server_time() RETURNS TIMESTAMPTZ AS $$ SELECT NOW(); $$ LANGUAGE SQL;
      // If the function doesn't exist, fall back to offset 0.
      final response = await client.rpc('get_server_time').single();
      if (response['get_server_time'] != null) {
        final serverTime = DateTime.parse(
          response['get_server_time'] as String,
        );
        _offsetMs = serverTime.difference(DateTime.now()).inMilliseconds;
        _lastFetch = DateTime.now();
      }
    } catch (e) {
      // Fallback: assume zero offset
      _offsetMs = 0;
      _lastFetch = DateTime.now();
    }
  }
}
