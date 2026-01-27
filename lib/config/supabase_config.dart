class SupabaseConfig {
  static const String url = 'https://yfanvvndqcixwdlhedqo.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlmYW52dm5kcWNpeHdkbGhlZHFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1MzUyNDQsImV4cCI6MjA4NTExMTI0NH0.hlq7HmLNDmf70LZChjFiORBnTJJXAsJ_zt9YCt9W5i8';

  // Backend server base URL (Vercel deployment)
  // Override with: --dart-define=BACKEND_BASE_URL=https://your-url/api
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://cricket-dash.vercel.app/api',
  );
}
