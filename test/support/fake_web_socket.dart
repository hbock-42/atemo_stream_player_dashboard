/// A WebSocket channel the test drives by hand.
///
/// `RelaySource` takes its channel factory as a parameter precisely so that
/// reconnect behaviour can be tested without a server, a port, or a timing
/// guess.
library;

import 'dart:async';

// stream_channel arrives with web_socket_channel, whose own public API is
// built on it; no new dependency is being taken.
// ignore: depend_on_referenced_packages
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocket extends StreamChannelMixin implements WebSocketChannel {
  FakeWebSocket(this.url);

  final Uri url;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<dynamic> sent = <dynamic>[];
  bool closed = false;

  /// A frame arriving from the relay.
  void receive(String message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  /// The relay went away, or the network did.
  void dropped() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  Future<void> get ready => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._socket);

  final FakeWebSocket _socket;

  @override
  void add(dynamic data) => _socket.sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _socket.closed = true;
    _socket.dropped();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
