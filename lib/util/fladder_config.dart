/// Runtime + compile-time configuration for this Ptaki Cinéma build.
///
/// Resolution order for every value:
///   1. `config/config.json` (web/Docker only, injected by docker-entrypoint.sh)
///   2. a `--dart-define` supplied at build time
///   3. the branded default baked in below
///
/// This lets the same source tree produce the self-hosted web image (configured
/// through Docker env vars) and the pre-configured mobile/desktop apps that are
/// handed to users, who then only ever type a username and a password.
class FladderConfig {
  static FladderConfig _instance = FladderConfig._();
  FladderConfig._();

  // ---- compile-time defaults (override with --dart-define) ----
  static const String _envBaseUrl =
      String.fromEnvironment('FLADDER_BASE_URL', defaultValue: 'https://jellyfin.ptaki.dev');
  static const String _envSeerrBaseUrl =
      String.fromEnvironment('FLADDER_SEERR_BASE_URL', defaultValue: 'https://reqcinema.ptaki.dev');

  /// Display name of the application, used wherever the app names itself.
  /// Kept here rather than read from `packageInfo` because on web Flutter
  /// derives that from the pubspec package name (`fladder`).
  static const String appName = String.fromEnvironment('FLADDER_APP_NAME', defaultValue: 'Ptaki Cinéma');

  /// GPLv3 section 5(a): a modified work must carry prominent notices
  /// stating that it was changed, and the date of the change.
  static const String modificationNotice = String.fromEnvironment(
    'FLADDER_MODIFICATION_NOTICE',
    defaultValue: 'Custom build for Ptaki Cinéma by Xertien — modified from Fladder, 2026',
  );

  static String? _clean(String? value) => (value == null || value.isEmpty) ? null : value;

  static String? get baseUrl => _instance._baseUrl ?? _clean(_envBaseUrl);
  static set baseUrl(String? value) => _instance._baseUrl = _clean(value);
  String? _baseUrl;

  static String? get seerrBaseUrl => _instance._seerrBaseUrl ?? _clean(_envSeerrBaseUrl);
  static set seerrBaseUrl(String? value) => _instance._seerrBaseUrl = _clean(value);
  String? _seerrBaseUrl;

  static void fromJson(Map<String, dynamic> json) => _instance = FladderConfig._fromJson(json);

  factory FladderConfig._fromJson(Map<String, dynamic> json) {
    final config = FladderConfig._();
    config._baseUrl = _clean(json['baseUrl'] as String?);
    config._seerrBaseUrl = _clean(json['seerrBaseUrl'] as String?);
    return config;
  }
}
