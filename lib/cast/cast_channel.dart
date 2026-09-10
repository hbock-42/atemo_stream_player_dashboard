/// The byte-level half of the CASTV2 client: a TLS socket that yields whole
/// [CastMessage]s.
///
/// Nothing above this file thinks about TCP. Nothing in this file knows what a
/// track is.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cast_address.dart';
import 'cast_message.dart';

/// Opens a transport to the device. Injected so tests can substitute a plain
/// socket against the fake device instead of a real TLS one.
typedef CastSocketFactory = Future<Stream<Uint8List>> Function(
  String host,
  int port,
  Duration timeout,
);

/// A framed CASTV2 connection.
///
/// Wire format is a 4-byte big-endian length prefix followed by a protobuf
/// `CastMessage`. Reads arrive as an arbitrary byte stream: several frames can
/// land in one read and one frame can be split across several. Both happen in
/// practice, so the buffer below is load-bearing rather than defensive.
class CastChannel {
  CastChannel._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: _messages.addError,
      onDone: () {
        if (!_messages.isClosed) _messages.close();
      },
      cancelOnError: true,
    );
  }

  /// Connects over TLS, accepting the device's self-signed certificate.
  ///
  /// The Streamplayer presents a certificate no public CA has signed, so
  /// verification is bypassed deliberately. The connection is to a device on
  /// the local network whose address we discovered ourselves; the TLS here
  /// buys transport framing, not identity.
  static Future<CastChannel> connect(
    String host, {
    int port = kDefaultCastPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: (_) => true,
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    return CastChannel._(_SocketTransport(socket));
  }

  /// Wraps an already-open transport. Used by tests and by the fake device.
  static CastChannel fromTransport(CastTransport transport) => CastChannel._(transport);

  final Stream<Uint8List> _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final StreamController<CastMessage> _messages = StreamController<CastMessage>();
  final BytesBuilder _buffer = BytesBuilder(copy: true);
  bool _closed = false;

  Stream<CastMessage> get messages => _messages.stream;

  void send(CastMessage message) {
    if (_closed) return;
    final payload = message.encode();
    final frame = Uint8List(4 + payload.length);
    final view = ByteData.view(frame.buffer);
    view.setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    (_socket as CastTransport).add(frame);
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    // takeBytes() drains the builder, so anything left over after the last
    // whole frame has to go back in.
    var pending = _buffer.takeBytes();
    var offset = 0;

    while (pending.length - offset >= 4) {
      final length =
          ByteData.view(pending.buffer, pending.offsetInBytes + offset, 4).getUint32(0, Endian.big);
      if (pending.length - offset - 4 < length) break;

      final frame = Uint8List.sublistView(pending, offset + 4, offset + 4 + length);
      offset += 4 + length;
      try {
        _messages.add(CastMessage.decode(Uint8List.fromList(frame)));
      } on CastMessageFormatException catch (error) {
        // A frame we cannot parse means the stream is out of sync; there is no
        // way to resynchronise, so the connection is finished.
        _messages.addError(error);
        unawaited(close());
        return;
      }
    }

    if (offset < pending.length) {
      _buffer.add(Uint8List.sublistView(pending, offset));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await (_socket as CastTransport).close();
    // A single-subscription controller's done future only completes once a
    // listener has received the done event. Awaiting it would hang forever
    // when the channel is closed before anything subscribed, or after the
    // subscription was cancelled above — which is every teardown path.
    if (!_messages.isClosed) unawaited(_messages.close());
  }
}

/// A bidirectional byte transport. Kept as an interface so the fake device in
/// tests does not need a real socket.
abstract class CastTransport extends Stream<Uint8List> {
  void add(Uint8List data);
  Future<void> close();
}

class _SocketTransport extends Stream<Uint8List> implements CastTransport {
  _SocketTransport(this._socket);
  final Socket _socket;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _socket.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(Uint8List data) => _socket.add(data);

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } on SocketException {
      // Already gone. Nothing to do.
    }
    _socket.destroy();
  }
}
