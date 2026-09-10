# Getting the app onto people's devices

**Most people should not install anything.** The relay serves the web UI on the
office network, so opening `http://<relay-host>:8080` is the whole process, and
[WEB-04](kanban/cards/EPIC-10-web.md) puts it on a home screen without an app
store. See [ADR-0005](adr/0005-web-delivery-via-relay.md).

Native builds exist for two cases: a wall display that must keep working when
the relay is down, and anyone who would rather have a real app icon.

## Android

### One-off, unsigned

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

With no keystore configured this is signed with the **debug key**. That is fine
for handing to a colleague who enables "install unknown apps", and not fine for
anything longer-lived: debug-signed builds cannot be upgraded in place by a
properly signed one later, because the signatures differ.

### Properly signed

Create a keystore once, and keep it somewhere you will still have in two years —
losing it means every installed copy has to be uninstalled before an update:

```bash
keytool -genkey -v -keystore ~/streamplayer-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias streamplayer
```

Then `android/key.properties`:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=streamplayer
storeFile=/Users/you/streamplayer-release.jks
```

`key.properties` and `*.jks` are gitignored, and `build.gradle.kts` only uses
the release config when that file exists — so a fresh clone still builds.

### Size

The universal APK is ~43MB because it carries every ABI. Split it if that
matters:

```bash
flutter build apk --release --split-per-abi
```

Most office phones want `app-arm64-v8a-release.apk`, roughly a third the size.

## iOS

There is no route as easy as Android's. Pick one:

| Route | Cost | Limit |
|---|---|---|
| **TestFlight** | Apple Developer Program, ~€99/yr | 100 internal testers; builds expire after 90 days |
| **Ad-hoc** | Same programme | 100 devices per type per year, each UDID registered up front |
| **Free provisioning** | None | Rebuild every **7 days**, one device at a time, via Xcode |

Free provisioning is only viable for a single wall-display iPad you can plug
into a Mac weekly. For anyone else, the web UI is genuinely the better answer —
this is exactly the pain ADR-0005 was written to avoid.

Building locally:

```bash
flutter build ios --release          # needs a signing identity
flutter build ipa --export-method ad-hoc
```

CI builds iOS with `--no-codesign` on every push to `main`, which proves it
compiles but produces nothing installable.

## Which source do native builds use?

Native defaults to **direct** — a socket straight to the speaker, with the
device found over mDNS and no configuration at all. Set a relay URL in the
app's config to use the relay instead; that choice is persisted.

Native builds do **not** yet find the relay automatically. That needs the relay
to advertise itself over mDNS, which is unimplemented — see the note on
RELAY-02 in [the board](kanban/board.md).
