// Operator-facing tool: stdout is the product.
// ignore_for_file: avoid_print

/// Screenshots the web UI at real device sizes.
///
/// `chrome --headless --screenshot --window-size=360,800` does NOT give a
/// 360px viewport: Chrome enforces a minimum window width, so the capture is
/// the top-left corner of a wider render and every narrow layout looks broken
/// when it is not. Device emulation over the DevTools protocol is the only way
/// to get an honest answer, so this drives CDP directly.
///
/// The app is web-only (ADR-0007) and there is no other way to look at it.
///
///   dart run tool/screenshot.dart [url] [outDir]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9222;

/// Sizes worth checking: the narrowest phone we claim to support, a normal
/// phone, a tablet in portrait for the wall display, and a desktop window.
const sizes = <String, (int, int, bool)>{
  'phone-360': (360, 780, true),
  'phone-430': (430, 932, true),
  'tablet-820': (820, 1180, true),
  'desktop-1280': (1280, 860, false),
};

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run tool/screenshot.dart <url> [outDir]');
    exit(64);
  }
  final url = arguments.first;
  final outDir = Directory(arguments.length > 1 ? arguments[1] : 'build/screenshots')
    ..createSync(recursive: true);

  final browser = await Process.start(chrome, [
    '--headless=new',
    '--remote-debugging-port=$port',
    '--disable-gpu',
    '--no-first-run',
    '--user-data-dir=${Directory.systemTemp.createTempSync('shot').path}',
  ]);

  try {
    final endpoint = await _waitForDevTools();
    for (final entry in sizes.entries) {
      final (width, height, mobile) = entry.value;
      final png = await _capture(endpoint, url, width, height, mobile);
      final file = File('${outDir.path}/${entry.key}.png')..writeAsBytesSync(png);
      print('${entry.key.padRight(14)} ${width}x$height  ${file.path}');
    }
  } finally {
    browser.kill();
  }
}

/// Chrome takes a moment to open its debugging port.
Future<String> _waitForDevTools() async {
  final client = HttpClient();
  for (var attempt = 0; attempt < 50; attempt++) {
    try {
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/json/version')))
          .close();
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      client.close();
      return body['webSocketDebuggerUrl'] as String;
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  client.close();
  throw StateError('Chrome never opened its debugging port');
}

Future<Uint8List> _capture(
    String browserEndpoint, String url, int width, int height, bool mobile) async {
  final client = HttpClient();
  // Chrome 111+ requires PUT here; GET returns a plain-text error.
  final created = await (await client.putUrl(
          Uri.parse('http://127.0.0.1:$port/json/new?about:blank')))
      .close();
  final target = jsonDecode(await created.transform(utf8.decoder).join());
  client.close();

  final socket = await WebSocket.connect(target['webSocketDebuggerUrl'] as String);
  var id = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};

  socket.listen((dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final replyTo = message['id'];
    if (replyTo is int) pending.remove(replyTo)?.complete(message);
  });

  Future<Map<String, dynamic>> send(String method,
      [Map<String, dynamic> params = const {}]) {
    final completer = Completer<Map<String, dynamic>>();
    pending[++id] = completer;
    socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    return completer.future.timeout(const Duration(seconds: 30));
  }

  // The whole point: a real viewport of exactly this width.
  await send('Emulation.setDeviceMetricsOverride', {
    'width': width,
    'height': height,
    'deviceScaleFactor': 1,
    'mobile': mobile,
  });
  await send('Page.enable');
  await send('Page.navigate', {'url': url});
  // CanvasKit and the WebSocket handshake both need a moment; the app has to
  // have received a state before there is anything worth looking at.
  await Future<void>.delayed(Duration(seconds: int.parse(Platform.environment['SHOT_WAIT'] ?? '6')));

  final shot = await send('Page.captureScreenshot', {'format': 'png'});
  await socket.close();
  return base64Decode(shot['result']['data'] as String);
}
