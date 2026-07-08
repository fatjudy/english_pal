# English Pal — Partner Chat Spec

A second chat mode where a user talks to **another real person** (not the AI),
while the AI quietly acts as a **coach** that produces an English correction card
for each human message. This document is the blueprint for building it.

_Planned 2026-07-07 (Phase 1 = product definition). Not yet built._

---

## 1. Concept

Today the app is **You ↔ Mia (AI)**: the AI both *replies* and *corrects*.

Partner Chat adds **You ↔ another real person**. The other human does the
replying, so the AI stops replying and does only the *correction* half of its
current job — a silent coach that annotates each message.

Everything already built is reused: the `_correctionCard`, the colored
track-changes diff (`_wordDiff`), and the bookmark / save-for-review feature all
drop straight in.

---

## 2. Key decisions (locked)

| Area | Decision |
| --- | --- |
| AI role | Coach only — produces a correction per human message, no chat reply |
| Pairing | **Real accounts + friend search** (search by username, friend requests) |
| Auth | **Self-rolled email + password in FastAPI first**; add Google Sign-In (Firebase) later for production |
| Transport | **Polling first** (simple, reuses FastAPI + SQLite); swap to **WebSockets** later — app UI unchanged |
| Correction privacy | Sender **always** sees their own correction card (private coaching) |
| Partner view | A **once-set per-user preference** controls what the *partner* sees of the sender's message (3 modes, see §5) |
| Storage | Extend the existing SQLite backend (`backend/db.py`); each message stores **both** original and corrected text |
| Push | FCM (Phase 7) — fine because real users are outside China |

---

## 3. Audience & China constraint (why the auth choice)

- **Real users:** Australia / abroad — outside the Great Firewall, so Firebase
  and FCM work fine for them.
- **Developer (testing):** in mainland China, where Google / Firebase / the AI
  APIs are blocked (needs a VPN to develop).

Going straight to Firebase Auth would make day-to-day testing from China
painful. So we build **self-rolled email/password auth in FastAPI first** — it
works everywhere (smooth to test in China, fine for AU users since it's just our
own server), keeps everything in the Python + SQLite stack, and has zero Google
dependency. **"Continue with Google" via Firebase is added later** as a
production convenience (the login screen already has the button).

**Hosting:** production in Australia (near users, Firebase/FCM reachable);
local laptop for development.

---

## 4. The message flow (the heart of it)

Every message is stored with **both** its `original` and `corrected` text, plus
the short `why`. Who sees what is purely a rendering choice on top of the same
stored row.

```
You send: "I go beach yesterday"
  backend runs correction-only  →  corrected: "I went to the beach yesterday"
                                    why: "Past tense"
  stored: { original, corrected, why, understood, sender_pref }

YOUR view (always):     "I go beach yesterday"  + [correction card]   ← private
PARTNER's view depends on YOUR saved preference (sender_pref):
   mode 1 →  "I go beach yesterday"  + [your card]
   mode 2 →  "I went to the beach yesterday"          (polished only)
   mode 3 →  "I go beach yesterday"                    (raw only)
```

The sender's preference is **snapshotted onto each message** at send time, so a
later preference change never rewrites how old messages appear.

---

## 5. Partner-view preference (the 3 modes)

Set once per user (in Settings), default = **mode 1**. Controls what the
*partner* sees of the user's own messages; the user always additionally sees
their own private correction card regardless.

1. **Original + correction card** — share your raw message and your card.
2. **Corrected only** — the partner sees just your polished sentence.
3. **Original only** — the partner sees just what you typed, no card.

The **"✓ Looks good!"** note (shown when a message was checked and needed no
correction) is treated as part of the coaching card: it follows the same
sharing rule. Only **mode 1** shares it with the partner; modes 2 and 3 hide it.
You always still see it on your own messages. (Gibberish / non-English gets no
note either way, via the stored `understood` flag.)

---

## 6. Data model (extends `backend/db.py`, same SQLite style)

New tables (all keyed by an authenticated `user_id`, not the anonymous
`device_id` used by the solo-AI chat):

| Table | Columns (sketch) |
| --- | --- |
| `users` | `user_id` PK, `email` UNIQUE, `password_hash`, `username` UNIQUE, `display_name`, `partner_view_pref` (1/2/3), `created_at` |
| `friend_requests` | `id` PK, `requester_id`, `addressee_id`, `status` (pending/accepted/declined), `created_at` |
| `conversations` | `id` PK, `user_a`, `user_b`, `created_at` (one row per friend pair) |
| `messages` | `id` PK, `conversation_id`, `sender_id`, `original`, `corrected`, `why`, `understood`, `sender_pref`, `created_at` |

Password hashing: use a real KDF (e.g. `bcrypt`/`passlib`), never store plain
text. Auth token: a signed token (JWT or a random session token row).

---

## 7. Backend endpoints (FastAPI, mirroring today's style)

**Auth** _(built — Phase 0)_
- `POST /auth/continue` — email, password, `mode` (`login`/`signup`/`auto`).
  The app's Log in / Create account toggle sets the mode: `login` requires an
  existing account, `signup` requires a new email (username auto-derived from
  the email), `auto` logs in or creates. Returns `{ok, isNew, token, user}`.
  One screen, no separate signup page.
- `POST /auth/register`, `POST /auth/login` — kept for completeness/testing.
- (later) Google Sign-In verification endpoint.

**Friends**
- `POST /friends/search` — by username.
- `POST /friends/request` — send a request.
- `POST /friends/respond` — accept / decline.
- `POST /friends/list` — my friends + pending requests.

**Conversations & messages**
- `POST /conversation/open` — get-or-create the conversation with a friend.
- `POST /conversation/list` — my conversations (for the list screen).
- `POST /message/send` — text; backend runs the correction-only call, stores
  original + corrected + why + snapshotted `sender_pref`, returns the stored row.
- `POST /message/fetch` — messages in a conversation `since` a given id/time;
  each row is rendered for the **requesting viewer** (own message → full;
  partner's message → per that sender's `sender_pref`).

**Correction-only call:** reuse the existing `/chat` system prompt with the
"reply" job removed — same tool schema minus `reply`, returning `correction`,
`why`, `understood` (and no running summary needed here).

Authenticated endpoints take the token; the backend resolves it to a `user_id`.

---

## 8. App (Flutter) work

- **Real login** — wire the existing placeholder `login_screen.dart` to the new
  auth endpoints (email/password now; Google later).
- **Friends screen** — search by username, send/accept requests, friends list.
- **Conversation list** — friends you have chats with, newest first, unread hint.
- **`PartnerChatScreen`** — reuses `_messageBubble` and `_correctionCard`;
  messages aligned left/right by sender; correction card rendered per §4–5. The
  bookmark/save feature works unchanged.
- **Setting** — "What your chat partner sees" (the 3 modes), stored on the user.
- **Polling loop** — a `Timer` fetching new messages (~2s) while a chat is open;
  later replaced by a WebSocket connection.

---

## 9. Phase roadmap (each phase testable on its own)

- **Phase 0 — Auth foundation:** ✅ done. `users` + `sessions` tables, PBKDF2
  hashing, `/auth/continue` (log-in-or-sign-up); login screen wired to a single
  email/password form (no separate signup page). Verified end-to-end.
- **Phase 1 — Friends:** ✅ done. `friendships` table + `/friends/search`,
  `/friends/request`, `/friends/respond`, `/friends/list` (token-authed);
  `friends_screen.dart` reached via Settings → Friends. Verified in-app.
- **Phase 2 — Messaging plumbing:** ✅ done. `conversations` + `messages`
  tables; `/conversation/open`, `/message/send`, `/message/fetch`;
  `partner_chat_screen.dart` = real chat with left/right bubbles and 2s polling.
  Plain text only (no corrections yet). Verified in-app.
- **Phase 3 — Corrections:** ✅ done. `generate_correction` (correction-only
  Claude call); `messages` gains `corrected`/`why`/`understood`; the partner
  chat renders the sender's private correction card (with a bookmark → shared
  Saved corrections). Verified in-app.
- **Phase 4 — Partner-view preference:** ✅ done. `messages.sender_pref` snapshots
  the sender's `partner_view_pref` at send time; `/prefs/partner-view` sets it;
  `/message/fetch` shapes each row for the viewer (own = full; partner's = mode
  1 original+card / 2 corrected only / 3 original only). Settings → "What your
  chat partner sees" (3-option screen); partner chat renders a shared card
  left-aligned for the friend. Verified end-to-end (all 3 modes) via the API.
- **Phase 5 — Polish:** ✅ done. `/conversation/list` (friends + last-message
  preview, id, time; sorted by recency); Chats list shows the last message +
  relative time and an **unread badge** (navy dot + bold) driven by a
  locally-stored last-seen id per conversation (cleared when you open the chat);
  empty states ("No friends yet", "Tap to start chatting"). Verified in-app.

**Chats home** _(built early)_ — `chats_list_screen.dart` is the app's home
after login/setup: a list of the AI pal (→ `ChatScreen`) plus accepted friends
(→ `PartnerChatScreen`, a Phase-2 placeholder for now). Person-add and settings
icons in the app bar.
- **Phase 6 — Real-time:** ✅ done. `@app.websocket("/ws/{conversation_id}")`
  (token-authed) + a `ConnectionManager` that pushes each stored message to the
  other party's live sockets (per-viewer shaped); `/message/send` is async and
  broadcasts. App uses `web_socket_channel`: connects on open for instant
  delivery, with an always-on 5s safety poll as a backstop (a half-open socket
  can't silently lose messages) and backoff reconnection. Verified in-app:
  instant (~0.7s) delivery, self-heal after a backend restart, reconnect.
- **Phase 7 — Production niceties:** FCM push for new messages + Google Sign-In.
- **Phase 8 — Group chat:** ✅ done. New `groups` / `group_members` / `group_messages`
  tables; a group has 3+ participants and **at most one AI robot**. Endpoints
  `/group/create`, `/group/list`, `/group/info`, `/group/messages/fetch`,
  `/group/message/send`, `/group/prefs`, and a live `@app.websocket("/ws/group/{id}")`
  (separate `group_manager`). Decisions (chosen with the user):
  - **Robot replies only when mentioned by name** (`_mentions_robot`, whole-word,
    case-insensitive); `generate_group_reply` builds a short in-character reply
    from the last ~10 messages. The robot's persona is snapshotted onto the group
    as JSON (from the creator's local pal profile).
  - **Share preference is per-group** (`group_members.share_pref`), snapshotted per
    message — same 3 modes as 1-on-1, and the "✓ Looks good!" note follows the
    card's sharing rule. Server reuses `_view_message` to shape per viewer.
  - **Every human message is coached** (one `generate_correction` call).
  App: Groups tab lists groups (+ to create); `create_group_screen.dart` (name,
  friend multi-select, add-robot toggle, per-group share mode, 3-participant
  guard); `group_chat_screen.dart` (named bubbles, robot label, cards/looks-good
  per shaping, WebSocket + 5s safety poll) with a group-settings screen to change
  your own share mode + see members. Verified in-app: robot replied on mention
  and addressed the sender by name; own correction card shown.

---

## 10. Open items / notes

- **Cost:** every human message = one model call for its correction. Consider an
  on/off toggle or batching later.
- **Safety:** real accounts talking to strangers is out of scope for now
  (friends-only). If random matchmaking is ever added, it needs reporting /
  blocking / moderation (the app is 18+).
- **Two identities:** solo-AI chat is keyed by anonymous `device_id`; Partner
  Chat needs a real `user_id`. Decide later whether/how to link an existing
  device's data to a new account.
- **WebSockets migration:** only the "how messages arrive" layer changes; the
  message rendering and correction logic stay identical.
