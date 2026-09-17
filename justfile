# Streamplayer viewer — common commands.
#   just            list recipes, grouped
#   just <recipe>   run one
#
# The web-only Flutter app is served by the relay, which holds the one CASTV2
# connection to the speaker. See docs/README.md and relay/README.md.

# The speaker's address. Override per-run: `just host=192.168.1.55 run`
host := "192.168.1.131"
# Port the relay serves the UI and WebSocket on.
port := "8080"
# A peer's IP for the network isolation check.
peer := ""
# Where `deploy` lays the service out (`just dest=~/relay deploy` avoids sudo).
dest := "/opt/streamplayer-relay"

# List recipes, grouped (default).
default:
    @just --list

# Serve the UI against the real speaker, then open http://<this-machine>:8080
[group('play')]
run: build-web
    cd relay && dart run bin/relay.dart --host {{host}} --port {{port}} --web ../build/web

# Serve scripted data — no speaker needed, good for demos and UI work
[group('play')]
demo: build-web
    cd relay && dart run bin/relay.dart --demo --port {{port}} --web ../build/web

# Serve from the mDNS status line — view-only, works where sockets are blocked
[group('play')]
txt: build-web
    cd relay && dart run bin/relay.dart --txt --port {{port}} --web ../build/web

# Discover the speaker on the LAN and serve — no --host needed
[group('play')]
discover: build-web
    cd relay && dart run bin/relay.dart --port {{port}} --web ../build/web

# Show a running relay's health and what it sees
[group('play')]
health:
    @curl -s http://127.0.0.1:{{port}}/health | python3 -m json.tool

# Stop any relay this repo started
[group('play')]
stop:
    -pkill -f "bin/relay.dart" || true
    @echo "stopped"

# Can this machine reach the speaker? Runs Dart vs system tools side by side
[group('diagnose')]
doctor:
    cd relay && dart run bin/spike.dart doctor --host {{host}}

# Check the office network (`just peer=192.168.1.42 network-check` for isolation)
[group('diagnose')]
network-check:
    ./tool/network_check.sh {{peer}}

# Watch the mDNS status line change as you switch services (SPIKE-01, cheap)
[group('diagnose')]
txt-watch:
    cd relay && dart run bin/spike.dart txt --seconds 600

# Dump every CASTV2 frame while you play from each service (SPIKE-01, read-only)
[group('diagnose')]
probe:
    cd relay && dart run bin/spike.dart probe --host {{host}} --seconds 180

# Build the Flutter web bundle the relay serves
[group('build')]
build-web:
    flutter build web

# App tests only (fast)
[group('build')]
test:
    flutter test

# Everything CI runs: analyze, both suites, the layer guard, a web build
[group('build')]
check:
    flutter analyze
    flutter test
    cd relay && dart test
    ./tool/check_layers.sh
    flutter build web

# Screenshot the running UI at real device sizes (needs a relay up)
[group('build')]
shots:
    dart run tool/screenshot.dart http://127.0.0.1:{{port}}/ build/screenshots

# Build/lay out the relay as a service (`just dest=~/relay deploy` avoids sudo)
[group('deploy')]
deploy:
    relay/deploy/build_and_deploy.sh {{dest}}

# One-time Spotify authorisation — writes the refresh token (see docs/spotify.md)
[group('spotify')]
spotify-setup:
    cd relay && dart run bin/spotify_setup.dart
