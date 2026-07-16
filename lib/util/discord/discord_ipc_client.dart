import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

class DiscordIpcClient {
  DiscordIpcClient({required this.clientId});

  final String clientId;

  static final Logger _log = Logger('DiscordRPC');

  static const int _opHandshake = 0;
  static const int _opFrame = 1;
  static const int _opClose = 2;
  static const int _opPing = 3;
  static const int _opPong = 4;

  _DiscordTransport? _transport;
  Future<void> _requestLock = Future.value();
  int _nonce = 0;

  bool get connected => _transport != null;

  Future<bool> connect() async {
    if (connected) return true;

    final transport = await _openTransport();
    if (transport == null) {
      _log.fine('Discord IPC not found, is Discord running?');
      return false;
    }

    try {
      _transport = transport;
      await _write(_opHandshake, {'v': 1, 'client_id': clientId});
      final response = await _readFrame().timeout(const Duration(seconds: 5));
      if (response.opCode == _opFrame && response.payload['evt'] == 'READY') {
        _log.info('Connected to Discord IPC');
        return true;
      }
      _log.warning('Discord IPC handshake rejected: ${response.payload}');
      await close();
      return false;
    } catch (e) {
      _log.fine('Discord IPC handshake failed: $e');
      await close();
      return false;
    }
  }

  Future<Map<String, dynamic>?> setActivity(Map<String, dynamic>? activity) async {
    if (!connected) return null;
    try {
      return await _request({
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': pid,
          'activity': activity,
        },
        'nonce': '${_nonce++}',
      });
    } catch (e) {
      _log.fine('Discord IPC setActivity failed: $e');
      await close();
      return null;
    }
  }

  Future<void> close() async {
    final transport = _transport;
    _transport = null;
    await transport?.close();
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> payload) {
    final result = _requestLock.then((_) async {
      await _write(_opFrame, payload);
      while (true) {
        final frame = await _readFrame().timeout(const Duration(seconds: 5));
        switch (frame.opCode) {
          case _opPing:
            await _write(_opPong, frame.payload);
          case _opClose:
            throw const SocketException('Discord IPC connection closed');
          default:
            return frame.payload;
        }
      }
    });
    _requestLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _write(int opCode, Map<String, dynamic> payload) async {
    final transport = _transport;
    if (transport == null) throw const SocketException('Discord IPC not connected');
    final data = utf8.encode(jsonEncode(payload));
    final frame = Uint8List(8 + data.length);
    final header = ByteData.view(frame.buffer);
    header.setUint32(0, opCode, Endian.little);
    header.setUint32(4, data.length, Endian.little);
    frame.setAll(8, data);
    await transport.write(frame);
  }

  Future<({int opCode, Map<String, dynamic> payload})> _readFrame() async {
    final transport = _transport;
    if (transport == null) throw const SocketException('Discord IPC not connected');
    final header = ByteData.sublistView(await transport.read(8));
    final opCode = header.getUint32(0, Endian.little);
    final length = header.getUint32(4, Endian.little);
    final body = await transport.read(length);
    final payload = length > 0 ? jsonDecode(utf8.decode(body)) as Map<String, dynamic> : <String, dynamic>{};
    return (opCode: opCode, payload: payload);
  }

  Future<_DiscordTransport?> _openTransport() async {
    if (Platform.isWindows) {
      for (var i = 0; i < 10; i++) {
        try {
          final pipe = await File('\\\\?\\pipe\\discord-ipc-$i').open(mode: FileMode.append);
          return _WindowsPipeTransport(pipe);
        } catch (_) {
          continue;
        }
      }
      return null;
    }

    if (Platform.isLinux || Platform.isMacOS) {
      final env = Platform.environment;
      final baseDirs = <String>{
        for (final dir in [env['XDG_RUNTIME_DIR'], env['TMPDIR'], env['TMP'], env['TEMP'], '/tmp'])
          if (dir != null && dir.isNotEmpty) dir,
      };
      const subDirs = ['', 'app/com.discordapp.Discord', 'snap.discord', 'snap.discord-canary'];

      for (final base in baseDirs) {
        for (final sub in subDirs) {
          for (var i = 0; i < 10; i++) {
            final path = [base, if (sub.isNotEmpty) sub, 'discord-ipc-$i'].join('/');
            try {
              final socket = await Socket.connect(
                InternetAddress(path, type: InternetAddressType.unix),
                0,
                timeout: const Duration(seconds: 2),
              );
              return _UnixSocketTransport(socket);
            } catch (_) {
              continue;
            }
          }
        }
      }
      return null;
    }

    return null;
  }
}

abstract class _DiscordTransport {
  Future<void> write(Uint8List data);

  Future<Uint8List> read(int length);

  Future<void> close();
}

class _WindowsPipeTransport implements _DiscordTransport {
  _WindowsPipeTransport(this._pipe);

  final RandomAccessFile _pipe;

  @override
  Future<void> write(Uint8List data) => _pipe.writeFrom(data);

  @override
  Future<Uint8List> read(int length) async {
    final builder = BytesBuilder(copy: false);
    while (builder.length < length) {
      final chunk = await _pipe.read(length - builder.length);
      if (chunk.isEmpty) {
        throw const SocketException('Discord IPC pipe closed');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<void> close() async {
    try {
      await _pipe.close();
    } catch (_) {}
  }
}

class _UnixSocketTransport implements _DiscordTransport {
  _UnixSocketTransport(this._socket) {
    _subscription = _socket.listen(
      (data) {
        _buffer.add(data);
        _tryComplete();
      },
      onError: (Object error) => _fail(error),
      onDone: () => _fail(const SocketException('Discord IPC socket closed')),
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _buffer = BytesBuilder();
  Completer<Uint8List>? _pending;
  int _pendingLength = 0;
  Object? _error;

  void _tryComplete() {
    final pending = _pending;
    if (pending == null || _buffer.length < _pendingLength) return;
    final bytes = _buffer.takeBytes();
    _pending = null;
    pending.complete(Uint8List.sublistView(bytes, 0, _pendingLength));
    if (bytes.length > _pendingLength) {
      _buffer.add(Uint8List.sublistView(bytes, _pendingLength));
    }
  }

  void _fail(Object error) {
    _error = error;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  @override
  Future<void> write(Uint8List data) async {
    final error = _error;
    if (error != null) throw error;
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<Uint8List> read(int length) {
    final error = _error;
    if (error != null) return Future.error(error);
    assert(_pending == null, 'Only one read at a time is supported');
    _pendingLength = length;
    _pending = Completer<Uint8List>();
    final future = _pending!.future;
    _tryComplete();
    return future;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}
