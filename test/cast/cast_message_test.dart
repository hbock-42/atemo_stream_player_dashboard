import 'dart:typed_data';

import 'package:atemo_stream_player_viewer/cast/cast_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CastMessage codec', () {
    test('round-trips every field', () {
      const original = CastMessage(
        sourceId: 'sender-123',
        destinationId: 'receiver-0',
        namespace: 'urn:x-cast:com.google.cast.receiver',
        payloadUtf8: '{"type":"GET_STATUS","requestId":7}',
      );

      final decoded = CastMessage.decode(original.encode());

      expect(decoded.sourceId, 'sender-123');
      expect(decoded.destinationId, 'receiver-0');
      expect(decoded.namespace, 'urn:x-cast:com.google.cast.receiver');
      expect(decoded.payloadUtf8, '{"type":"GET_STATUS","requestId":7}');
      expect(decoded.payloadType, CastPayloadType.string);
      expect(decoded.type, 'GET_STATUS');
    });

    test('handles multi-byte payloads and long strings', () {
      final long = 'é${'x' * 500}';
      final decoded = CastMessage.decode(CastMessage(
        sourceId: 'a',
        destinationId: 'b',
        namespace: 'ns',
        payloadUtf8: long,
      ).encode());

      expect(decoded.payloadUtf8, long);
    });

    test('skips unknown fields rather than failing', () {
      // A field 9 varint appended, as a future firmware might send.
      final base = const CastMessage(
        sourceId: 'a',
        destinationId: 'b',
        namespace: 'ns',
        payloadUtf8: '{}',
      ).encode();
      final withUnknown = Uint8List.fromList([...base, (9 << 3) | 0, 0x2A]);

      expect(CastMessage.decode(withUnknown).sourceId, 'a');
    });

    test('json returns an empty map for malformed payloads', () {
      const message = CastMessage(
        sourceId: 'a',
        destinationId: 'b',
        namespace: 'ns',
        payloadUtf8: 'not json at all',
      );
      expect(message.json, isEmpty);
      expect(message.type, '');
    });

    test('throws on a truncated frame', () {
      final bytes = const CastMessage(
        sourceId: 'a',
        destinationId: 'b',
        namespace: 'ns',
        payloadUtf8: '{}',
      ).encode();

      expect(
        () => CastMessage.decode(Uint8List.sublistView(bytes, 0, bytes.length - 3)),
        throwsA(isA<CastMessageFormatException>()),
      );
    });
  });
}
