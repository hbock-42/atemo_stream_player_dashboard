#!/usr/bin/env bash
# Builds the web bundle, compiles the relay, and lays both out under a
# destination directory in the layout the launchd plist and systemd unit in
# this directory expect (RELAY-04).
#
# Usage:
#   relay/deploy/build_and_deploy.sh [dest]
#
#   dest defaults to /opt/streamplayer-relay. This script only writes files -
#   it does not install or (re)start the service. See RUNBOOK.md for that.
#
# Run from anywhere; paths are resolved relative to this script.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
relay_dir="$repo_root/relay"
dest="${1:-/opt/streamplayer-relay}"

# Use sudo only where the destination is not already writable. /opt needs
# it; a user directory like ~/streamplayer-relay does not, and demanding a
# password there - or in CI - is pure friction.
probe="$dest"
while [ ! -e "$probe" ]; do probe="$(dirname "$probe")"; done
if [ -w "$probe" ]; then SUDO=""; else SUDO="sudo"; fi

echo "==> Building Flutter web bundle"
(cd "$repo_root" && flutter build web)

echo "==> Fetching relay dependencies"
(cd "$relay_dir" && dart pub get)

echo "==> Compiling relay to a native executable"
# Compiled, not `dart run`, for deployment: near-instant start on boot/restart
# (no analyzer/VM warm-up) and no dependency on the Dart SDK or pub cache
# being present on the target machine at runtime. See RUNBOOK.md for why.
tmp_bin="$(mktemp)"
(cd "$relay_dir" && dart compile exe bin/relay.dart -o "$tmp_bin")

echo "==> Installing into $dest (may prompt for sudo)"
$SUDO mkdir -p "$dest/bin" "$dest/web" "$dest/logs"
$SUDO install -m 755 "$tmp_bin" "$dest/bin/relay"
rm -f "$tmp_bin"

# Replace the served web bundle atomically-ish: build fresh, then swap.
$SUDO rm -rf "$dest/web.new"
$SUDO cp -R "$repo_root/build/web" "$dest/web.new"
$SUDO rm -rf "$dest/web.old"
if [ -d "$dest/web" ]; then
  $SUDO mv "$dest/web" "$dest/web.old"
fi
$SUDO mv "$dest/web.new" "$dest/web"
$SUDO rm -rf "$dest/web.old"

echo "==> Done. Binary: $dest/bin/relay, web bundle: $dest/web"
echo "    Restart the service so it picks up the new build:"
echo "      macOS:  sudo launchctl kickstart -k system/com.streamplayer.relay"
echo "      Linux:  sudo systemctl restart streamplayer-relay"
