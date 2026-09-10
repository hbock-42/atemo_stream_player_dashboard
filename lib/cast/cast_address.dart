/// Where the device is. Produced by `discovery/`, consumed by `cast/`, so that
/// the protocol layer never has to know how an address was found.
library;

import 'cast_channel.dart';

class CastAddress {
  const CastAddress({required this.host, this.port = kDefaultCastPort, this.friendlyName});

  final String host;
  final int port;
  final String? friendlyName;

  @override
  bool operator ==(Object other) =>
      other is CastAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '$host:$port${friendlyName == null ? '' : ' ($friendlyName)'}';
}
