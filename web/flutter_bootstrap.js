// Flutter's loader, with the service worker deliberately left out (WEB-04).
//
// `_flutter.loader.load()` registers a service worker only when it is handed
// `serviceWorkerSettings`. Passing nothing is therefore the whole mechanism —
// but it is invisible, so this file exists to say so out loud rather than
// leaving the absence of an argument as the only record of the decision.
//
// Why no service worker:
//   * the relay is redeployed by whoever is nearest, with no version
//     discipline; a cached bundle would keep running against a newer relay
//     and there is no way to tell a dozen phones to hard-refresh;
//   * offline is meaningless here — the page shows live state from a relay on
//     the same LAN, so with no network there is nothing to show;
//   * first load is a few MB of CanvasKit over a LAN, which is fast enough
//     that caching buys little (ADR-0005).
//
// If caching is ever wanted, it must be a bundle-versioned worker with a
// skipWaiting/clients.claim update path, decided in an ADR — not a default.

{{flutter_js}}
{{flutter_build_config}}

// Undo history: any service worker registered by an earlier deploy of this
// app would otherwise keep serving its cached bundle forever, and the whole
// point above would be defeated for exactly the people who visited first.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    for (const registration of registrations) {
      registration.unregister();
    }
  }).catch(() => {
    // Nothing registered, or the browser refuses to say. Either is fine.
  });
}

_flutter.loader.load();
