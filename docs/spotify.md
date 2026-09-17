# Showing Spotify

Spotify Connect is invisible to Google Cast on this device — while it plays, the
Streamplayer reports no Cast app and an empty mDNS status line (SPIKE-01 /
[OQ-1](open-questions.md)). So a Spotify track can only be seen through the
Spotify Web API, which the relay reads server-side. Set-up is once.

Services that cast over Google Cast (SoundCloud, Deezer) need none of this —
they already show up.

## One-time set-up

1. **Create a Spotify app** at <https://developer.spotify.com/dashboard>. Any
   name. Copy the **Client ID** and **Client secret**.

2. **Add a redirect URI** in the app's settings, exactly:

   ```
   http://127.0.0.1:8888/callback
   ```

3. **Create `relay/spotify.json`** (it is gitignored — the secret never leaves
   the machine, and never reaches a browser):

   ```json
   {
     "clientId": "your-client-id",
     "clientSecret": "your-client-secret",
     "refreshToken": "",
     "deviceName": "The Kids"
   }
   ```

   `deviceName` is the Spotify device to watch — a substring of the speaker's
   Spotify name is enough. It stops a colleague's phone playing Spotify from
   showing as the office system. Leave it out to show whatever is playing on the
   account anywhere.

4. **Authorise once:**

   ```
   just spotify-setup
   ```

   It opens Spotify's consent page; approve, and it writes the refresh token
   back into `relay/spotify.json`.

That is all. The relay picks Spotify up automatically on its next start — no
flag. Restart it if it was running.

## How it fits

The relay layers its sources, richest first:

```
CASTV2 connection      SoundCloud, Deezer — full metadata and control
   ↓ (idle / not seen)
Spotify Web API        Spotify — metadata, and control if you granted it
   ↓ (idle / not seen)
mDNS status line       whatever else, one line, no artwork
```

Each layer is consulted only when the one above comes up empty, so Spotify is
not polled while SoundCloud is playing.

## If Spotify stops showing

- `curl -s http://<relay-host>:8080/health | python3 -m json.tool` — the
  `source` block shows which layer is active and the last error.
- `Spotify refresh token rejected` means the authorisation was revoked (or the
  app's secret changed). Run `just spotify-setup` again.
- A track playing on someone's phone not showing is correct — `deviceName`
  filters to the speaker.

## Control

Spotify is **view-only for now** — the app shows the track but its
pause/skip/seek/volume buttons do not drive Spotify (they do work for
SoundCloud and other Cast senders). The setup still asks for the
`user-modify-playback-state` scope, so control can be added later without
re-authorising; wiring the Web API's play/pause/next/volume endpoints into the
Spotify source is the remaining piece.
