# EPIC-8 — Spotify Web API source

**Conditional epic, and possibly the wrong shape.** Build only if [SPIKE-01] finds a service
that does not surface through the Cast media namespace, or [SPIKE-04] finds one we cannot
command.

**Read the spike result before starting.** This epic covers *one* service. The office casts
from Spotify, Tidal, Deezer and SoundCloud, and a per-service Web API source needs its own
OAuth app, its own token storage and its own mapping for each. If several services turn out
to be silent, four of these is the wrong answer and the service-agnostic mDNS `rs=` status
line ([OQ-1](../../open-questions.md)) is worth pursuing first — it covers everything at
once and costs no sender slot.

Deezer and SoundCloud cast over Google Cast proper, so the likely finding is that they work
and only the Connect protocols are in doubt. In that case this epic stays Spotify-shaped.

The whole point of the [`NowPlayingSource`](../../architecture.md#the-seam) seam is that
this epic touches no UI code.

---

## SPOT-01 — Spotify OAuth for the speaker's account

**Acceptance**
- [ ] Authorization Code flow against the account that drives the office speaker.
- [ ] Refresh token stored securely; access token refreshed automatically.
- [ ] Authorisation happens once, on the relay host if the relay exists — not on every
      phone.
- [ ] Scopes: `user-read-playback-state`, `user-read-currently-playing`, plus
      `user-modify-playback-state` if control is required.
- [ ] Expired or revoked authorisation degrades to `Unreachable` with a clear reason and a
      documented re-auth path.

**Size:** M

---

## SPOT-02 — `SpotifyWebApiSource` including control

**Acceptance**
- [ ] Implements `NowPlayingSource` from `/v1/me/player/currently-playing`.
- [ ] Polls at a modest interval (5s) — the Web API has no push; rate limits respected with
      backoff on 429.
- [ ] Filters to the Streamplayer device by name, so a phone playing elsewhere isn't shown
      as the office speaker.
- [ ] Maps into the same `NowPlaying` types; `castingApp` is "Spotify".
- [ ] `204 No Content` ⇒ `Idle`.
- [ ] Implements `PlaybackControl` over `PUT /v1/me/player/pause`, `/play`, `/volume` and
      `POST /v1/me/player/next`, `/previous`, targeting the Streamplayer's device id — so
      control survives the fallback behind the same interface.
- [ ] Returns `control: null` rather than failing if the granted scopes don't allow
      modification; [UI-09] already handles it.

**Size:** M

---

## SPOT-03 — Compose Cast and Spotify sources

**As** a user, **I want** the right track shown whatever the source, **so that** I never
have to know which protocol is carrying it.

**Acceptance**
- [ ] A `CompositeSource` preferring Cast when it reports `Playing`, falling back to
      Spotify when Cast reports `Idle`.
- [ ] No flapping between the two when both report something.
- [ ] Either source failing leaves the other working.
- [ ] `ui/` unchanged — verified by the diff.

**Size:** M
