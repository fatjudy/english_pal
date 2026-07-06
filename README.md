# English Pal 🗣️

An AI-powered English-learning chat companion for Android (iOS planned). Chat with a friendly AI "pal" that talks like a friend, gently corrects your English, remembers your conversations, and can message you at scheduled times to start a chat — like a real friend texting you.

Built as a learning project with **Flutter** + a **Python backend** + **Google Gemini**.

## Features

- **Personalized pal** — name your pal and pick its personality, hobbies, topics, and your English level through a multi-step setup wizard.
- **Natural chat + gentle corrections** — the pal replies like a friend, and shows a correction card *under your message* (rewritten in your own voice) when there's a mistake — or a "✓ Looks good!" when it's fine.
- **Conversation memory** — a sliding window of recent messages plus an AI-maintained running **summary**, so the pal remembers you without resending the whole history.
- **Scheduled messages** — set times for the pal to text you (with a topic or a surprise). Notifications look like a real chat message from your pal, with an **AI-written opener**.
- **Safety boundaries** — the pal warmly declines unsafe topics and offers support if you seem distressed.
- **On-device persistence** — chats, settings, and schedules are saved locally and survive restarts.

## Tech stack

- **App:** Flutter (Dart) — Android now, iOS planned
- **Backend:** FastAPI (Python)
- **AI:** Google Gemini (`gemini-2.5-flash-lite`)
- **Notifications:** `flutter_local_notifications`
- **Storage:** `shared_preferences` (on-device)

## Architecture

```
Flutter app  ──►  FastAPI backend  ──►  Google Gemini
 (Android)         (hides API key,        (free tier)
                    builds prompts)
```

The app never holds the API key — it calls the backend, which keeps the Gemini key as a secret and builds the personalized prompts. This also keeps the door open to swap the AI provider without touching the app.

## Project structure

```
english_pal/
├── lib/main.dart        # Flutter app: chat, setup wizard, schedules, notifications
├── backend/
│   ├── main.py          # FastAPI server (/chat, /opener) calling Gemini
│   └── .env             # GEMINI_API_KEY (NOT committed)
├── PRODUCT_SPEC.md      # Product design / blueprint
└── README.md
```

## Getting started

### 1. Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows (use `source .venv/bin/activate` on macOS/Linux)
pip install fastapi "uvicorn[standard]" google-genai python-dotenv
```

Create `backend/.env` with your own Gemini API key (get one free at https://aistudio.google.com/apikey):

```
GEMINI_API_KEY=your_key_here
```

Then run the server:

```bash
python -m uvicorn main:app --reload
```

### 2. App

```bash
flutter pub get
flutter run -d chrome           # fast web preview
# or
flutter run -d emulator-5554    # Android emulator
```

The app reaches the backend at `127.0.0.1:8000` on web, or `10.0.2.2:8000` from the Android emulator.

## Status

**Work in progress.** Done so far: core chat, English correction, personalization, conversation memory, safety boundaries, and scheduled AI-message notifications.

Planned next: tapping a notification opens straight into the chat, cloud persistence & accounts, backend deployment (for server-pushed messages), and app-store release.

---

*Built while learning Flutter and Python — one small piece at a time.* 🌱
