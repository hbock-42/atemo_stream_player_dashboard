# Getting the app in front of people

**Nobody installs anything.** The relay serves the web UI on the office network,
so opening `http://<relay-host>:8080` is the whole process.

The client ships to browsers only — see
[ADR-0007](adr/0007-web-only-client.md) for why the Android and iOS targets were
removed after being built.

## For everyone in the office

Send them the URL. That is it.

To make it feel like an app, add it to the home screen: Safari's Share → *Add to
Home Screen*, or Chrome's ⋮ → *Add to home screen*. `web/manifest.json` declares
`display: standalone`, so it opens without browser chrome, with the same icon and
dark theme as the page.

## For the wall display

Open the same URL with `?wall`:

```
http://<relay-host>:8080/?wall
```

That hides all chrome, switches to the large across-the-room layout, dims when
nothing is playing, and holds a Screen Wake Lock so the tablet does not sleep.
Add *that* URL to the home screen and the tablet boots straight into it.

Wake lock is a browser API and is feature-detected — on a browser without it the
page still works, the screen just sleeps on its own schedule. If that bites,
disable screen timeout in the tablet's own settings rather than reaching for a
native build.

## Deploying a new version

Rebuild the bundle and restart the relay:

```bash
flutter build web
relay/deploy/build_and_deploy.sh
```

There is deliberately no service worker, so a redeploy reaches everyone on their
next page load. See [WEB-04](kanban/cards/EPIC-10-web.md).

## Access

Anyone on the office Wi-Fi can view and control. Nobody outside can do either.
No PIN, no accounts — see
[ADR-0006](adr/0006-lan-membership-is-the-auth-boundary.md), and **do not**
port-forward or tunnel the relay.
