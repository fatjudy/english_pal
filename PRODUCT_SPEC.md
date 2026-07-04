# English Pal — Product Spec

An English-learning mobile app where an AI "pal" chats with the user like a friend
and gives gentle English correction advice. Built with Flutter (Android first, iOS
later). This document is the blueprint for Phase 2 (build).

_Last updated: 2026-07-01 (end of Phase 1 — Product Definition)._

---

## 1. Concept

A friendly AI chat companion that:
- Chats naturally like a friend, matched to the user's chosen personality and interests.
- Corrects the user's English gently, inline, as they chat.
- Can proactively message the user at scheduled times to start a conversation.
- Stays safe: refuses harmful topics and redirects warmly.

Cost control: use a free LLM tier first (Google Gemini).

---

## 2. Key decisions (locked)

| Area | Decision |
| --- | --- |
| Framework | Flutter (one codebase → Android now, iOS later) |
| LLM | Google Gemini (free tier); API key hidden in a backend, never in the app |
| Accounts | **No login** for MVP — data saved locally on the phone |
| Onboarding | **Multi-step wizard** (one question per screen) |
| Navigation | **Chat is home**; a menu/gear icon → Settings → Schedule |
| Input style | **Presets only** (chips) for personality/hobbies/topics; name is free text |
| Audience | **Adults (18+)** — add a light age confirmation at first launch |
| Testing | Android emulator (`pixel_pal`); physical phone possible later |

---

## 3. Core user flows

**A. First-time setup (onboarding)**
1. Welcome screen (what the app does) → "Get started".
2. Age confirmation ("I'm 18 or older").
3. Wizard: name the pal → personality → hobbies → topics → English level.
4. Land in Chat; the AI sends a friendly first message.

**B. Everyday chat**
1. Open app → Chat with the pal.
2. User types a message → sends.
3. AI replies like a friend.
4. If the message had mistakes, a correction appears below it.
5. Conversation continues.

**C. Scheduled / AI-initiated message**
1. User has set a time + topic (specific or "surprise me") in the Schedule screen.
2. At that time → push notification with the AI's opening line.
3. Tap it → Chat opens with the AI's opener already there.
4. User replies → normal chat + corrections.

**D. Adjusting settings**
1. From Chat → menu → Settings.
2. Edit the pal (personality/hobbies/topics), own English level, or schedules.
3. Changes apply to the next messages.

---

## 4. Screens (MVP)

| # | Screen | Notes |
| --- | --- | --- |
| 1 | Welcome | First launch only → "Get started" |
| 2 | Age confirmation | "I'm 18+" gate |
| 3 | Onboarding wizard | Multi-step (see §5) |
| 4 | Chat (home) | Core screen; app bar has pal name + gear icon |
| 5 | Schedule | List + add (time, repeat, topic); reached via Settings |
| 6 | Settings | Edit pal, edit level, manage schedules |

**Later (not MVP):** progress/stats screen tracking common mistakes; typing indicator;
message timestamps; notification preferences; data reset.

---

## 5. Onboarding wizard content

One question per screen, with Back/Next and a progress bar.

1. **Name your pal** — free text field + "🎲 suggest a name" button.
2. **Personality** — chips, **pick several**:
   Friendly · Funny · Calm & Patient · Encouraging · Curious · Witty · Chatty ·
   Gentle · Enthusiastic · Thoughtful
3. **Hobbies (pal's interests)** — chips, multi-select:
   Sports · Music · Movies & TV · Gaming · Cooking · Travel · Books · Art ·
   Technology · Nature · Fitness · Pets · Photography · Science
4. **Topics (user wants to practice)** — chips, multi-select:
   Daily life · Work/Career · Travel English · Job interviews · Small talk ·
   Hobbies · News · Food · Culture · Studying abroad · Shopping · Health
5. **English level** — pick one:
   - **Beginner** — simple words, short sentences
   - **Intermediate** — everyday conversation, some new vocabulary
   - **Advanced** — natural, native-like, richer vocabulary
6. **Create my pal** → Chat.

---

## 6. Correction format

Corrections appear **directly below** the user's message, as a card.

**When the message has mistakes:**
- The corrected sentence, with **changed words highlighted**.
- A **one-line tip** explaining the fix (e.g. "Use past tense for 'yesterday': go → went").

**When the message is already correct:**
- A **subtle "✓ Looks good"** note with brief encouragement.

Design intent: enough to learn from, light enough to keep it feeling like a real
chat, not a grammar textbook.

---

## 7. Schedule feature

Each scheduled message has:
- **Time** (e.g. 8:00 AM).
- **Repeat rule** — Every day / Weekdays / Weekends.
- **Topic** — a specific one (e.g. "Small talk") or "🎲 Surprise me" (random).
- **On/off toggle**.

At the scheduled time, the app sends a **push notification** with the AI's opener;
tapping it opens Chat with that message already present.

_Technical note (Phase 5): scheduled messages need a backend scheduler + Firebase
Cloud Messaging (FCM) for push. Local phone alarms are unreliable for this._

---

## 8. Safety policy

**Audience:** Adults (18+). Add a light age confirmation at first launch, and set the
app-store age rating accordingly at release.

**Hard blocks (always refuse):**
- Sexual content — especially anything involving minors (absolute hard line).
- Graphic violence; instructions for hurting people.
- Self-harm / suicide methods.
- Dangerous / illegal instructions (weapons, drugs, hacking, etc.).
- Hate speech & harassment.
- Extremism.

**Sensitive-but-legitimate topics (balanced):** factual, gentle discussion of news,
history, or health is allowed; graphic detail, glorification, or how-to is blocked.

**Decline style:** stay a warm, friendly tutor — brief acknowledgment, gentle redirect
back to safe conversation. Never scold or lecture.
> Example: "That's not something I can chat about — but I'd love to hear about your
> weekend plans! What are you up to?"

**Distress / self-harm:** do not simply refuse. Respond with warmth and care, and
gently encourage reaching out to a trusted person or a local helpline. Never provide
methods. Human first, tutor second.

---

## 9. Architecture (planned, for Phase 2+)

```
Flutter app  ──►  Small backend  ──►  Gemini API
 (Android)         (hides API key,     (free tier)
                    runs schedules,
                    sends push via FCM)
```

- The app never holds the Gemini key; it calls our backend, which holds the key as a
  secret (env var).
- Chat history, pal settings, and schedules are stored **locally on the phone** for
  MVP (no accounts). Cloud sync is a later phase.
- Backend also runs the scheduler and sends push notifications (Phase 5).

---

## 10. Phase roadmap

- **Phase 0 — Setup** ✅ (done 2026-07-01): Flutter, Android Studio, SDK, emulator.
- **Phase 1 — Product definition** ✅ (this document).
- **Phase 2 — Core chat + backend**: chat UI, backend endpoint, Gemini call, correction prompt, local history.
- **Phase 3 — AI personalization**: onboarding wizard feeds the AI prompt.
- **Phase 4 — Safety**: safety instructions in the prompt + a second-layer check.
- **Phase 5 — Scheduled/push messages**: FCM + backend scheduler + Schedule screen.
- **Phase 6 — Accounts & persistence** (optional): auth + cloud storage.
- **Phase 7 — Polish & testing**.
- **Phase 8 — Android release**.
- **Phase 9 — iOS** (needs a Mac for the final build).
