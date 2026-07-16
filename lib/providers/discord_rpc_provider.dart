import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/providers/incognito_mode_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/discord/discord_ipc_client.dart';
import 'package:fladder/util/localization_helper.dart';

const String _discordAppId = String.fromEnvironment('DISCORD_APP_ID', defaultValue: '1527384570679398492');

const int _activityTypeListening = 2;
const int _activityTypeWatching = 3;

const Duration _reconnectCooldown = Duration(seconds: 20);

final discordRpcProvider = Provider<DiscordRpcService>((ref) {
  final service = DiscordRpcService(ref);
  ref.onDispose(service.dispose);
  service.init();
  return service;
});

class DiscordRpcService {
  DiscordRpcService(this.ref);

  final Ref ref;

  static final Logger _log = Logger('DiscordRPC');

  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  DiscordIpcClient? _client;
  Timer? _debounce;
  DateTime? _lastConnectAttempt;
  bool _hasActivity = false;
  bool _updating = false;
  bool _updateQueued = false;

  bool _supportsActivityType = true;

  String? _lastActivityKey;
  int _lastStartMs = 0;
  DateTime? _idleSince;

  void init() {
    if (!supported) return;

    ref.listen(playBackModel, (_, __) => _schedule());
    ref.listen(mediaPlaybackProvider, (_, __) => _schedule());
    ref.listen(playbackRateProvider, (_, __) => _schedule());
    ref.listen(incognitoProvider, (_, __) => _schedule());
    ref.listen(clientSettingsProvider.select((value) => value.discordRichPresence), (_, __) => _schedule());

    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _update);
  }

  Future<void> _update() async {
    if (_updating) {
      _updateQueued = true;
      return;
    }
    _updating = true;
    try {
      await _pushPresence();
    } finally {
      _updating = false;
      if (_updateQueued) {
        _updateQueued = false;
        _schedule();
      }
    }
  }

  Future<void> _pushPresence() async {
    final enabled =
        ref.read(clientSettingsProvider.select((value) => value.discordRichPresence)) && !ref.read(incognitoProvider);

    if (!enabled) {
      await _clearPresence(disconnect: true);
      return;
    }

    final model = ref.read(playBackModel);
    final playback = ref.read(mediaPlaybackProvider);
    final active = model != null && playback.state != VideoPlayerState.disposed && !playback.errorPlaying;

    if (active) _idleSince = null;

    final activity = active ? _buildActivity(model, playback) : _buildIdleActivity();
    if (activity == null) {
      await _clearPresence();
      return;
    }

    final timestamps = activity['timestamps'] as Map<String, dynamic>?;
    final startMs = timestamps?['start'] as int? ?? 0;
    final activityKey = jsonEncode({...activity, 'timestamps': null});
    if (_hasActivity && activityKey == _lastActivityKey && (startMs - _lastStartMs).abs() < 3000) {
      return;
    }

    if (!await _ensureConnected()) return;

    final response = await _client?.setActivity(
      _supportsActivityType ? activity : ({...activity}..remove('type')),
    );

    if (response == null && _client?.connected != true) return;

    if (response?['evt'] == 'ERROR') {
      _log.fine('Discord rejected activity: ${response?['data']}');
      if (_supportsActivityType && activity.containsKey('type')) {
        _supportsActivityType = false;
        await _client?.setActivity({...activity}..remove('type'));
      }
    }

    _hasActivity = true;
    _lastActivityKey = activityKey;
    _lastStartMs = startMs;
  }

  Map<String, dynamic> _buildIdleActivity() {
    final l10n = ref.read(localizationContextProvider)?.localized;
    final idleSince = _idleSince ??= DateTime.now();
    return {
      'details': _clampText(l10n?.idling ?? 'Idling'),
      'timestamps': {'start': idleSince.millisecondsSinceEpoch},
      'assets': {
        'large_image': 'fladder_icon_512',
        'large_text': 'Fladder',
      },
    };
  }

  Map<String, dynamic>? _buildActivity(PlaybackModel model, MediaPlaybackModel playback) {
    final l10n = ref.read(localizationContextProvider)?.localized;
    final item = model.item;

    final int type;
    final String? details;
    String? state;
    String? largeText;

    switch (item) {
      case EpisodeModel episode:
        type = _activityTypeWatching;
        details = episode.seriesName ?? episode.name;
        final seasonEpisode =
            l10n != null ? episode.seasonEpisodeLabel(l10n) : 'S${episode.season} - E${episode.episodeRange}';
        state = episode.name.isNotEmpty ? '$seasonEpisode · ${episode.name}' : seasonEpisode;
        largeText = episode.seriesName != null && episode.name.isNotEmpty ? episode.name : null;
      case AudioModel audio:
        type = _activityTypeListening;
        details = audio.name;
        state = audio.artistsLabel.isNotEmpty ? audio.artistsLabel : audio.albumArtists.map((e) => e.name).join(', ');
        largeText = audio.albumLabel();
      default:
        type = _activityTypeWatching;
        details = item.name;
        final year = item.overview.yearAired ?? item.overview.productionYear;
        state = [
          if (year != null) year.toString(),
          if (item.overview.genres.isNotEmpty) item.overview.genres.take(2).join(', '),
        ].join(' · ');
    }

    final playing = playback.playing;
    if (!playing) {
      final paused = l10n?.paused ?? 'Paused';
      state = state.isNotEmpty ? '$paused · $state' : paused;
    }

    final poster = item.getPosters?.primary?.path ?? item.images?.primary?.path;
    final largeImage = poster != null && poster.isNotEmpty && poster.length <= 256 ? poster : 'fladder_icon_512';

    final activity = <String, dynamic>{
      'type': type,
      if (_clampText(details) != null) 'details': _clampText(details),
      if (_clampText(state) != null) 'state': _clampText(state),
      if (playing) ..._timestamps(playback),
      'assets': {
        'large_image': largeImage,
        if (_clampText(largeText ?? item.name) != null) 'large_text': _clampText(largeText ?? item.name),
        'small_image': playing ? 'play' : 'pause',
        if (l10n != null) 'small_text': playing ? _clampText(details) : l10n.paused,
      },
    };

    return activity;
  }

  Map<String, dynamic> _timestamps(MediaPlaybackModel playback) {
    final rate = ref.read(playbackRateProvider).clamp(0.25, 4.0);
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - (playback.position.inMilliseconds / rate).round();
    final end = playback.duration > Duration.zero ? start + (playback.duration.inMilliseconds / rate).round() : null;
    return {
      'timestamps': {
        'start': start,
        if (end != null) 'end': end,
      },
    };
  }

  String? _clampText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length == 1) return '$trimmed ';
    return trimmed.length > 128 ? trimmed.substring(0, 128) : trimmed;
  }

  Future<bool> _ensureConnected() async {
    final client = _client;
    if (client != null && client.connected) return true;

    final lastAttempt = _lastConnectAttempt;
    if (lastAttempt != null && DateTime.now().difference(lastAttempt) < _reconnectCooldown) {
      return false;
    }
    _lastConnectAttempt = DateTime.now();

    _client ??= DiscordIpcClient(clientId: _discordAppId);
    _hasActivity = false;
    return await _client!.connect();
  }

  Future<void> _clearPresence({bool disconnect = false}) async {
    if (_client?.connected == true && _hasActivity) {
      await _client?.setActivity(null);
    }
    _hasActivity = false;
    _lastActivityKey = null;
    if (disconnect) {
      await _client?.close();
      _client = null;
      _lastConnectAttempt = null;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _client?.close();
    _client = null;
  }
}
