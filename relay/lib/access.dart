/// Who may control the speaker.
///
/// ADR-0006: everyone on the office Wi-Fi may view and control; nobody outside
/// it may do either. The network is the credential — there is no PIN and no
/// account, because the Streamplayer itself has no authentication and anyone
/// on the LAN can already control it from any Cast app.
///
/// Three layers, so no single misconfiguration opens it up. Layer 1 (never
/// expose the relay to the internet) is a deployment property; layers 2 and 3
/// are here.
library;

import 'dart:io';

class AccessDecision {
  const AccessDecision({required this.allowed, required this.canControl, this.reason});

  final bool allowed;
  final bool canControl;
  final String? reason;

  static const grantedWithControl = AccessDecision(allowed: true, canControl: true);
}

class AccessPolicy {
  const AccessPolicy({this.allowedHosts = const <String>{}});

  /// Hostnames the relay is expected to be reached by, in addition to any
  /// private IP literal. Used for the Host check below.
  final Set<String> allowedHosts;

  /// Layer 2: the peer must be on a private network.
  ///
  /// The *actual socket address* is used, never X-Forwarded-For, which any
  /// client can set. The deliberate consequence: putting a tunnel in front of
  /// the relay disables control rather than handing it to the internet.
  static bool isPrivateAddress(InternetAddress address) {
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv6) {
      final text = address.address.toLowerCase();
      // Unique local (fc00::/7) and link-local (fe80::/10).
      return text.startsWith('fc') || text.startsWith('fd') || text.startsWith('fe80');
    }
    final parts = address.address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    final [a!, b!, _, _] = parts;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true; // link-local
    return false;
  }

  /// Layer 3: defeat DNS rebinding.
  ///
  /// A LAN-only unauthenticated service is still reachable from the internet
  /// *through a browser on the LAN*: an attacker's site re-resolves its own
  /// domain to the relay's private address and the visitor's browser makes the
  /// requests. The network boundary offers no protection there, so the Origin
  /// and Host headers have to be checked.
  bool _isAcceptableOrigin(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null) {
      // Not a browser — the native app sends no Origin. Permitted only because
      // the peer check above has already passed.
      return true;
    }
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    return _isAcceptableHostname(uri.host);
  }

  bool _isAcceptableHost(HttpRequest request) {
    final host = request.headers.host;
    if (host == null) return false;
    return _isAcceptableHostname(host);
  }

  bool _isAcceptableHostname(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.endsWith('.local')) return true;
    if (allowedHosts.contains(name)) return true;
    final parsed = InternetAddress.tryParse(name);
    return parsed != null && isPrivateAddress(parsed);
  }

  AccessDecision evaluate(HttpRequest request) {
    final peer = request.connectionInfo?.remoteAddress;
    if (peer == null || !isPrivateAddress(peer)) {
      return const AccessDecision(
        allowed: false,
        canControl: false,
        reason: 'not on the local network',
      );
    }
    if (!_isAcceptableHost(request) || !_isAcceptableOrigin(request)) {
      // Almost certainly a rebinding attempt: a LAN peer asking for a hostname
      // the relay is not served under.
      return const AccessDecision(
        allowed: false,
        canControl: false,
        reason: 'unrecognised Host or Origin',
      );
    }
    return AccessDecision.grantedWithControl;
  }
}
