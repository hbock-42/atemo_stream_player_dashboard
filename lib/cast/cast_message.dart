/// Minimal hand-written codec for the CASTV2 `CastMessage` protobuf.
///
/// `CastMessage` has six fields we care about, all either varints or
/// length-delimited strings, so a full protobuf runtime would be a dependency
/// bought for about eighty lines of work. See ADR-0001.
///
/// ```proto
/// message CastMessage {
///   required ProtocolVersion protocol_version = 1;  // CASTV2_1_0 = 0
///   required string source_id                 = 2;
///   required string destination_id            = 3;
///   required string namespace                 = 4;
///   required PayloadType payload_type         = 5;  // STRING = 0, BINARY = 1
///   optional string payload_utf8              = 6;
///   optional bytes payload_binary             = 7;
/// }
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a frame cannot be decoded. Callers treat this as a corrupt
/// connection rather than as a recoverable per-message error.
class CastMessageFormatException implements Exception {
  const CastMessageFormatException(this.message);
  final String message;
  @override
  String toString() => 'CastMessageFormatException: $message';
}

enum CastPayloadType { string, binary }

/// One CASTV2 frame.
class CastMessage {
  const CastMessage({
    required this.sourceId,
    required this.destinationId,
    required this.namespace,
    this.payloadUtf8 = '',
    this.payloadType = CastPayloadType.string,
    this.payloadBinary,
  });

  final String sourceId;
  final String destinationId;
  final String namespace;
  final CastPayloadType payloadType;
  final String payloadUtf8;
  final Uint8List? payloadBinary;

  /// Decodes [payloadUtf8] as a JSON object.
  ///
  /// Returns an empty map rather than throwing when the payload is absent or
  /// is not a JSON object: cheap hardware sends odd things, and a malformed
  /// payload must not take the connection down.
  Map<String, dynamic> get json {
    if (payloadType != CastPayloadType.string || payloadUtf8.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payloadUtf8);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  /// The `type` field of the JSON payload, which is how CASTV2 discriminates
  /// messages within a namespace.
  String get type {
    final value = json['type'];
    return value is String ? value : '';
  }

  Uint8List encode() {
    final out = _ProtoWriter()
      ..writeVarintField(1, 0) // protocol_version: CASTV2_1_0
      ..writeStringField(2, sourceId)
      ..writeStringField(3, destinationId)
      ..writeStringField(4, namespace)
      ..writeVarintField(5, payloadType == CastPayloadType.string ? 0 : 1);

    if (payloadType == CastPayloadType.string) {
      out.writeStringField(6, payloadUtf8);
    } else if (payloadBinary != null) {
      out.writeBytesField(7, payloadBinary!);
    }
    return out.takeBytes();
  }

  static CastMessage decode(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    var sourceId = '';
    var destinationId = '';
    var namespace = '';
    var payloadUtf8 = '';
    var payloadType = CastPayloadType.string;
    Uint8List? payloadBinary;

    while (!reader.isAtEnd) {
      final tag = reader.readVarint();
      final field = tag >> 3;
      final wireType = tag & 0x7;
      switch (field) {
        case 1:
          reader.readVarint(); // protocol_version, unused
        case 2:
          sourceId = reader.readString();
        case 3:
          destinationId = reader.readString();
        case 4:
          namespace = reader.readString();
        case 5:
          payloadType =
              reader.readVarint() == 1 ? CastPayloadType.binary : CastPayloadType.string;
        case 6:
          payloadUtf8 = reader.readString();
        case 7:
          payloadBinary = reader.readBytes();
        default:
          // Forward compatibility: skip fields we don't know about rather than
          // failing, so a firmware update that adds one doesn't break us.
          reader.skipField(wireType);
      }
    }

    return CastMessage(
      sourceId: sourceId,
      destinationId: destinationId,
      namespace: namespace,
      payloadType: payloadType,
      payloadUtf8: payloadUtf8,
      payloadBinary: payloadBinary,
    );
  }

  @override
  String toString() =>
      'CastMessage($sourceId -> $destinationId, $namespace, '
      '${payloadUtf8.length > 120 ? '${payloadUtf8.substring(0, 120)}...' : payloadUtf8})';
}

class _ProtoWriter {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  void writeVarintField(int field, int value) {
    _writeVarint((field << 3) | 0);
    _writeVarint(value);
  }

  void writeStringField(int field, String value) =>
      writeBytesField(field, Uint8List.fromList(utf8.encode(value)));

  void writeBytesField(int field, Uint8List value) {
    _writeVarint((field << 3) | 2);
    _writeVarint(value.length);
    _buffer.add(value);
  }

  void _writeVarint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      _buffer.addByte((remaining & 0x7F) | 0x80);
      remaining >>= 7;
    }
    _buffer.addByte(remaining);
  }

  Uint8List takeBytes() => _buffer.takeBytes();
}

class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (isAtEnd) {
        throw const CastMessageFormatException('truncated varint');
      }
      if (shift > 63) {
        throw const CastMessageFormatException('varint overflow');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (length < 0 || _offset + length > _bytes.length) {
      throw const CastMessageFormatException('length-delimited field overruns frame');
    }
    final view = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(view);
  }

  String readString() => utf8.decode(readBytes(), allowMalformed: true);

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _advance(8);
      case 2:
        readBytes();
      case 5:
        _advance(4);
      default:
        throw CastMessageFormatException('unsupported wire type $wireType');
    }
  }

  void _advance(int count) {
    if (_offset + count > _bytes.length) {
      throw const CastMessageFormatException('fixed-width field overruns frame');
    }
    _offset += count;
  }
}
