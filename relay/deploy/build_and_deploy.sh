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
sudo mkdir -p "$dest/bin" "$dest/web" "$dest/logs"
sudo install -m 755 "$tmp_bin" "$dest/bin/relay"
rm -f "$tmp_bin"

# Replace the served web bundle atomically-ish: build fresh, then swap.
sudo rm -rf "$dest/web.new"
sudo cp -R "$repo_root/build/web" "$dest/web.new"
sudo rm -rf "$dest/web.old"
if [ -d "$dest/web" ]; then
  sudo mv "$dest/web" "$dest/web.old"
fi
sudo mv "$dest/web.new" "$dest/web"
sudo rm -rf "$dest/web.old"

echo "==> Done. Binary: $dest/bin/relay, web bundle: $dest/web"
echo "    Restart the service so it picks up the new build:"
echo "      macOS:  sudo launchctl kickstart -k system/com.streamplayer.relay"
echo "      Linux:  sudo systemctl restart streamplayer-relay"
