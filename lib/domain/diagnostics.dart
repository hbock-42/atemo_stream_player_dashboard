/// What a source is willing to say about its own health.
///
/// Part of the seam, for the same reason [NowPlayingSource] is: the
/// diagnostics screen needs protocol-level facts — where we connected, whether
/// the link is up, how long the device has been silent — but `lib/ui/` is
/// forbidden from knowing what Cast is. So every source reports its health in
/// the same source-agnostic shape: the direct source fills it from its CASTV2
/// client, a relay client from what the relay tells it, the fake source from
/// stubs, and the screen renders whichever it is handed.
///
/// Protocol-specific facts that have no home in the common fields travel as
/// [DiagnosticFact] label/value pairs, which the UI prints without
/// interpreting. That keeps Cast vocabulary out of `lib/ui/` — it is data
/// passing through, never a type the UI compiles against.
///
/// Nothing here may be sensitive: this screen is meant to survive into release
/// builds and be read aloud over the phone.
library;

/// How the app is getting its data.
enum SourceMode {
  /// A socket straight to the device on this machine.
  direct,

  /// Through the relay, which holds the one real connection.
  relay,

  /// Scripted data, no device involved.
  fake,

  /// A source that does not report a mode.
  unknown;

  String get label => switch (this) {
        SourceMode.direct => 'direct',
        SourceMode.relay => 'relay',
        SourceMode.fake => 'fake',
        SourceMode.unknown => 'unknown',
      };
}

/// The state of whatever connection the source maintains.
///
/// Deliberately coarser than the protocol's own states: three words a person
/// can report over the phone.
enum LinkState {
  connecting,
  connected,
  disconnected;

  String get label => switch (this) {
        LinkState.connecting => 'connecting',
        LinkState.connected => 'connected',
        LinkState.disconnected => 'disconnected',
      };
}

/// One extra fact a source wants shown, already phrased for a human.
class DiagnosticFact {
  const DiagnosticFact(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticFact && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

/// One line in the recent-events log.
class DiagnosticLogEntry {
  const DiagnosticLogEntry(this.at, this.message);

  final DateTime at;
  final String message;

  /// `HH:MM:SS message` — the clock time is what makes two people's reports
  /// line up.
  String format() {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}  $message';
  }

  @override
  String toString() => format();
}

/// A fixed-size ring of recent log lines.
///
/// Bounded on purpose: the wall display runs for days, and an unbounded list
/// of every reconnect is a slow leak with no upper limit.
class DiagnosticLog {
  DiagnosticLog({this.capacity = 80}) : assert(capacity > 0);

  final int capacity;
  final List<DiagnosticLogEntry> _entries = <DiagnosticLogEntry>[];

  /// Oldest first.
  List<DiagnosticLogEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  void add(String message, {DateTime? at}) {
    _entries.add(DiagnosticLogEntry(at ?? DateTime.now(), message));
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }

  void clear() => _entries.clear();
}

/// A snapshot of one source's health, taken when the screen asks for it.
class SourceDiagnostics {
  const SourceDiagnostics({
    this.mode = SourceMode.unknown,
    this.link = LinkState.connecting,
    this.endpoint,
    this.lastError,
    this.sessionId,
    this.lastMessageAt,
    this.facts = const <DiagnosticFact>[],
    this.log = const <DiagnosticLogEntry>[],
  });

  /// Direct, relay, or fake.
  final SourceMode mode;

  final LinkState link;

  /// Where we are talking to, as discovered — a host and port, a relay URL.
  /// Null when nothing has been found yet.
  final String? endpoint;

  /// The last failure, phrased for a person. Sticky: it stays after a
  /// successful reconnect, because "what went wrong ten minutes ago" is the
  /// question this screen exists to answer.
  final String? lastError;

  /// The id the source uses to address the live session, when it has one.
  final String? sessionId;

  /// When the device (or the relay) last said anything at all.
  final DateTime? lastMessageAt;

  /// Extra source-specific facts, already labelled.
  final List<DiagnosticFact> facts;

  /// Recent events, oldest first.
  final List<DiagnosticLogEntry> log;

  SourceDiagnostics copyWith({
    SourceMode? mode,
    LinkState? link,
    String? endpoint,
    String? lastError,
    String? sessionId,
    DateTime? lastMessageAt,
    List<DiagnosticFact>? facts,
    List<DiagnosticLogEntry>? log,
  }) =>
      SourceDiagnostics(
        mode: mode ?? this.mode,
        link: link ?? this.link,
        endpoint: endpoint ?? this.endpoint,
        lastError: lastError ?? this.lastError,
        sessionId: sessionId ?? this.sessionId,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        facts: facts ?? this.facts,
        log: log ?? this.log,
      );

  /// The same snapshot with [more] facts appended.
  ///
  /// Lets a layer above the source add what only it knows — the last command
  /// the device refused, say — without the source having to know it exists.
  SourceDiagnostics withFacts(List<DiagnosticFact> more) =>
      copyWith(facts: [...facts, ...more]);

  /// How long the other end has been silent, or null if it has never spoken.
  Duration? silenceFor([DateTime? now]) {
    final last = lastMessageAt;
    if (last == null) return null;
    final elapsed = (now ?? DateTime.now()).difference(last);
    // A clock that jumped backwards should read "just now", not a negative age.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// The whole screen as plain text, for the clipboard.
  ///
  /// This is what gets pasted into a chat message, so it repeats the labels
  /// rather than assuming the reader has the screen in front of them.
  String toReport([DateTime? now]) {
    final silence = silenceFor(now);
    final lines = <String>[
      'Streamplayer diagnostics',
      'source mode: ${mode.label}',
      'connection: ${link.label}',
      'address: ${endpoint ?? '—'}',
      'session: ${sessionId ?? '—'}',
      'last message: ${silence == null ? 'never' : '${silence.inSeconds}s ago'}',
      'last error: ${lastError ?? 'none'}',
      for (final fact in facts) '${fact.label}: ${fact.value}',
      '',
      'log:',
      if (log.isEmpty) '  (empty)',
      for (final entry in log) '  ${entry.format()}',
    ];
    return lines.join('\n');
  }
}
