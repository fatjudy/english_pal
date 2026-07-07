# English Pal — Welcome / Onboarding Screen Spec

This documents the welcome screen **as currently implemented** in
`lib/onboarding_screen.dart`. It is the first thing a new user sees: a
4-slide, swipe-driven carousel that ends on sign up / log in. Colors reference
the shared chat UI palette but this screen **inverts** it — navy is the
background, yellow/gold are the accents.

> Note: this reflects the built screen, which intentionally deviates from the
> original brief in a few places (swipe replaces the "Start" button, a swipe
> hint was added, the hero uses an icon rather than a photo). Those deviations
> are called out inline.

## Font

**Roboto** — Android's default system font (zero download, native feel on the
Android-first target). No `fontFamily` is set in code, so the platform default
(Roboto on Android) is used everywhere. Hierarchy comes from weight and size,
not a second font.

- Weights: 400 regular, 500 medium, 700 bold.
- Type scale on this screen: 34 (big greeting title), 22 (slide headline),
  15 (slide body), 15 (Sign up button), 13 (swipe hint / login text).
- Line height: ~1.1 on the big title, ~1.5 on body text.
- Case: sentence case throughout.

## Colors (screen-local tokens: `_Onb`)

These live locally in `onboarding_screen.dart` (not in the shared `AppColors`),
because this screen uses a **lighter** yellow/gold than the chat screen.

| Token | Hex | Use |
|-------|-----|-----|
| `navy` | `#233A66` | Page background; text on yellow buttons/icons |
| `navyLight` | `#2C4676` | Faint decorative circle (top-right) |
| `navyDark` | `#1E3358` | Faint decorative circle (bottom-left) |
| `yellow` | `#FFE0A6` | Hero icon circle, active dot, greeting title, swipe hint, Sign up fill, "Log in" link |
| `gold` | `#F2D79A` | Tutor bubble in the slide-2 chat preview |
| `goldText` | `#4A3A17` | Text on the gold tutor bubble |
| `goldAccent` | `#E8C583` | Left accent border of the correction card (slide 3) |
| `white` | `#FFFFFF` | Slide headlines; user bubble in preview; correction card surface |
| `bodyText` | `#C6D2E6` | Light blue-gray body text on navy |
| `dotInactive` | `#41527A` | Inactive page-dots |

**Correction signal colors (slide 3)** — same as the chat spec, not recolored:
`deletionRed #C0392B` (strikethrough), `correctionGreen #2E7D32` (bold 700),
`tipIcon #D7A859` (lightbulb), `tipText #6B6862` (italic tip).

Contrast rule: yellow always carries **navy** text, never white. Body text on
navy uses `bodyText`, except headlines which are white for emphasis.

## Screen structure

Full-screen navy `Scaffold` → `SafeArea` → `Stack`:

1. **Background decoration** (all slides) — two large faint circles bleeding off
   the edges, behind the content:
   - Top-right: 160px circle, `navyLight`, offset ~-40px past top and right.
   - Bottom-left: 130px circle, `navyDark`, ~-50px past the left, ~70px up from
     the bottom.
2. **`PageView`** of 4 slides (horizontal swipe).
3. **Bottom chrome** — page-dots (left) + swipe hint (right). Hidden on slide 4.

### Shared slide skeleton

Slides 2 and 3 use a shared column (`_slide`): optional big title → an
`Expanded` central visual (flexes to fill height) → 22px bold white headline →
15px `bodyText` body. Side padding ~24px. Slide 1 uses a custom layout
(below); slide 4 adds a footer with the buttons.

## The 4 slides

### Slide 1 — greeting + meet the AI
- **Custom layout (not the shared skeleton):** the three components — the
  "Hi there!" title, the hero, and the headline+body block — are grouped into a
  band that spans **60% of the slide height, centered** (~20% empty above and
  below), via `LayoutBuilder` + a `SizedBox(height: maxHeight * 0.6)` with
  `MainAxisAlignment.spaceBetween`.
- Big title: **"Hi there!"** — 34px, weight 700, `yellow`.
- Hero: 140px `yellow` circle with a robot icon (~66px, navy) inside, plus a
  soft translucent halo (`spreadRadius: 10`, `rgba(255,224,166,0.15)`).
  - *Deviation:* the brief suggested a custom illustration/photo; the build uses
    a Material icon (`Icons.smart_toy_outlined`). A photo was trialed and
    reverted.
- Headline: "Meet your English partner"
- Body: "A friendly AI that chats with you anytime, at your own pace."

### Slide 2 — chat freely
- Central visual: a mini chat preview, two bubbles:
  - Tutor bubble (left, `gold` bg, `goldText`, tail bottom-left):
    "What did you do this weekend?"
  - User bubble (right, `white` bg, `navy` text, tail bottom-right):
    "I go to the beach with friends!" — deliberate error, sets up slide 3.
- Headline: "Chat about anything"
- Body: "No scripts, no pressure. Talk about your day, hobbies, or plans."

### Slide 3 — the correction feature
- Central visual: a correction card on a white surface with a 3px `goldAccent`
  left border, square corners, strong drop shadow
  (`0 6px 18px rgba(0,0,0,0.22)`):
  - Header: check icon (navy) + "Correction" (navy, 12px, weight 500).
  - Corrected sentence: "I ~~go~~ **went** to the beach with friends!"
    ("go" strikethrough `deletionRed`; "went" `correctionGreen` bold 700).
  - Divider, then tip row: lightbulb (`tipIcon`) + italic
    "Past tense: 'go' → 'went'." (`tipText`).
- Headline: "Improve as you go"
- Body: "I gently correct your English and explain why — no red pen, no judgment."

### Slide 4 — sign up / log in (the close)
- Central visual: 110px `yellow` circle with a sparkles icon (~52px, navy),
  same halo as slide 1.
- Headline: "Ready to start?"
- Body: "Create an account to save your progress and streaks."
- **Sign up** button (full width): `yellow` fill, `navy` text, weight 700,
  radius 14px, ~13px vertical padding.
- Below: "Already have an account? **Log in**" — 13px `bodyText`, with "Log in"
  in `yellow` weight 500 as a tappable link.
- Bottom chrome (dots + swipe hint) is hidden here.

## Navigation & bottom chrome

- **Swipe left** to advance between slides. *(Deviation: the original brief had
  a "Start" button advancing the pages; it was removed in favor of swipe.)*
- **Page-dots** (bottom-left): 4 dots, 7px, 7px gap. Active = `yellow`, follows
  the current slide; inactive = `dotInactive`.
- **Swipe hint** (bottom-right, slide 1 only): "Swipe to start →" in `yellow`,
  13px weight 500, with the arrow (`Icons.arrow_forward`, 16px) gently nudging
  ~4px left↔right on a looping 900ms ease-in-out animation. It **fades out
  (300ms) after the first swipe** and does not return.

## Wiring / behavior

- Shown as the app home for new users (no saved `palName`); returning users go
  straight to the chat.
- `OnboardingScreen` takes optional `onSignUp` / `onLogin` callbacks. **Not
  wired yet** — the login / sign-up page is the next screen to build. The Sign
  up button stays visually active (`onPressed: onSignUp ?? () {}`).

## Widget breakdown (Flutter)

- `OnboardingScreen` (`StatefulWidget`) — `PageView` of 4 slides + bottom chrome;
  tracks `_page` and `_showHint`.
- `_slide({ title?, visual, headline, body, footer? })` — shared skeleton
  (slides 2–4).
- `_slideGreeting()` — slide 1's custom 60%-band layout.
- `_heroIcon(icon, circle, glyph)` — haloed yellow circle with a navy icon.
- `_SwipeHint` (`StatefulWidget`) — the animated "Swipe to start →" cue.
- `_Onb` — the screen-local color tokens above.

---

# Login / Sign-up Screen Spec

The second onboarding page (`lib/login_screen.dart`). Opened from onboarding
slide 4 — both **Sign up** and **Log in** navigate here. Uses the same inverted
palette (navy canvas, yellow accents), the same faint background circles, and
the same Roboto type scale as the welcome screen. Layout top→bottom: profile
photo → login options → sign-in / create-account → terms & policy.

## Colors & font

Same tokens as the welcome screen (mirrored locally in a `_L` class):
`navy #233A66`, `navyLight #2C4676`, `navyDark #1E3358`, `yellow #FFE0A6`,
`white #FFFFFF`, `bodyText #C6D2E6`, plus `googleBlue #4285F4` for the Google
"G". Font is Roboto (platform default); type scale: 22 (heading), 15 (subtitle
+ button labels), 14 (create-account link), 12 (terms).

Contrast rule holds: yellow always carries navy text. The Google button is a
white surface with navy label (recognizable, high contrast).

## Structure (top → bottom)

Navy `Scaffold` → `SafeArea` → `Stack` [background circles, content]. Content is
a padded (24px) `Column`, top-aligned, with a `Spacer` pushing the terms to the
bottom.

1. **Profile photo** — the welcome screen's haloed yellow hero, smaller: 96px
   `yellow` circle, robot icon (~46px, navy), same translucent halo
   (`spreadRadius 10`, `rgba(255,224,166,0.15)`).
2. **Heading** — "Welcome to English Pal" (22px, weight 700, `white`) + subtitle
   "Log in to save your progress and streaks." (15px, `bodyText`), centered.
3. **Login options** (common Android methods):
   - **Continue with Google** — primary, full-width `white` `FilledButton`, navy
     label (15px weight 600), a blue "G" (`googleBlue`) leading. Radius 14px,
     ~14px vertical padding. Lowest-friction option on Android.
   - **Continue with email** — secondary, full-width `OutlinedButton`, 1.5px
     `yellow` border, `yellow` label + mail icon. Same radius/padding.
   - *Decision:* no phone and no Apple option — not publishing in China (phone
     login unneeded) and Android-only for now (Apple is iOS-only).
4. **Sign in / create account** — centered row: "New here? " (`bodyText`) +
   "Create an account" (`yellow`, weight 600, tappable).
5. **Terms & policy** — pinned near the bottom, centered, 12px `bodyText`:
   "By continuing, you agree to our **Terms of Service** and **Privacy
   Policy**." with both link phrases in `yellow` weight 500.

## Wiring / behavior

- `LoginScreen` takes optional callbacks: `onGoogle`, `onEmail`,
  `onCreateAccount`, `onTerms`, `onPrivacy`.
- **Not wired to real auth yet** — all actions are no-op placeholders; buttons
  stay visually active (`onPressed: cb ?? () {}`).
- Terms / Privacy are styled as links but **not tappable yet** (`onTerms` /
  `onPrivacy` unused). When wiring real URLs, convert `LoginScreen` to a
  `StatefulWidget` so a `TapGestureRecognizer` can be created and disposed.

## Widget breakdown

- `LoginScreen` (`StatelessWidget`) — the whole page.
- `_heroIcon`, `_bgCircle` — local copies of the welcome screen's helpers.
- `_googleButton`, `_emailButton`, `_createAccountRow`, `_termsText` — sections.
- `_L` — screen-local color tokens (same values as `_Onb`).

---

---

# Account Setup Screen Spec

The 3-page flow a new user completes after tapping **Create an account** on the
login page (`lib/setup_flow_screen.dart`, `AccountSetupScreen`). Same inverted
palette (navy canvas, faint circles, yellow accents) and Roboto scale.

**Entry / exit:**
- Login **Continue with Google / email → chat directly** (existing user).
- Login **Create an account → this 3-page setup → chat**.
- Settings **Start over** also routes here (after clearing prefs).
- `AccountSetupScreen` takes a required `onDone` callback (→ chat) called after
  the profile is saved.

## Colors & font

Same tokens as the welcome/login screens (local `_S` class): `navy`, `navyLight`,
`navyDark`, `yellow #FFE0A6`, `white`, `bodyText #C6D2E6`, `dotInactive #41527A`.
Roboto; type scale: 24 (page title), 15 (subtitle), 14 (field/section labels),
16 (level card title), 13 (level blurb + hints).

## Shared frame (every page)

Navy `Scaffold` → `SafeArea` → `Stack` [background circles, padded (24px)
`PageView`]. The `PageView` is **button-driven only** (`NeverScrollableScroll
Physics`) — no free swiping in a form. Each page:

1. **Header row** — a back arrow (`bodyText`; on page 1 it pops to login, else
   goes to the previous page) + a **step indicator**: 3 pills where the active
   step is a stretched `yellow` bar (22px) and the others are 7px `dotInactive`
   dots.
2. **Title** (24px, weight 700, `white`) + **subtitle** (15px, `bodyText`).
3. **Content** — a scrollable middle area (`Expanded` + `SingleChildScrollView`).
4. **Primary button** pinned at the bottom — full-width `yellow` fill, `navy`
   text, weight 700, radius 14px, ~14px vertical padding. Disabled state uses
   35%-opacity yellow.

Spacing is deliberately balanced (title/subtitle top, content middle, button
bottom) — not compact, not spread.

## The 3 pages

### Page 1 — name + personality
- Title "Create your pal", subtitle "Give your AI partner a name and a
  personality."
- **Name** — a white filled `TextField`, navy text, radius 14px, `yellow` focus
  border. **Next is disabled until the name is non-empty.**
- **Personality** — a `Wrap` of multi-select pill chips (`kPersonalityOptions`).
  Labels are 15px bold. Every chip has a `yellow` 1.5px frame (palette-consistent):
  selected = `yellow` fill + navy text (weight 700); unselected = transparent fill
  + `bodyText` label (weight 600).
- Button: **Next**.

### Page 2 — topics the pal loves
- Title "What do you both love?", subtitle "Pick the topics your pal enjoys
  chatting about."
- Multi-select chips (`kHobbyOptions`), same chip style.
- Button: **Next**.

### Page 3 — English level
- Title "Your English level", subtitle "This helps your pal match how it talks
  to you."
- Three single-select **cards** (`kLevelOptions`), each: a radio icon
  (`radio_button_checked`/`unchecked`, `yellow` when selected), the level name
  (16px, weight 700, white), and a one-line blurb (13px, `bodyText`). Selected
  card = 2px `yellow` border + faint yellow tint; unselected = `navyLight` fill.
  Blurbs:
  - **Beginner** — "Just starting out — simple words, short sentences, and lots
    of encouragement."
  - **Intermediate** (default) — "You can chat about everyday things but want to
    get smoother and more confident."
  - **Advanced** — "Comfortable and fluent — polishing nuance, idioms, and
    natural phrasing."
- Button: **Start chatting** → saves profile + `onDone()`.

## Saved data

Writes `SharedPreferences` (and best-effort cloud via `saveProfileToCloud`):
`palName` (defaults to "Mia" if left blank), `personality` (list), `level`.
The 3-page flow has **no separate hobbies page**, so page 2's selection is saved
to **both** `hobbies` and `topics` — keeping the chat persona and the notification
opener (which reads user topics / pal hobbies) working unchanged.

---

## Open items / next

- Wire real authentication: Google Sign-In + email, and the Terms / Privacy links
  (convert `LoginScreen` to `StatefulWidget` for the link recognizers).
- Build the **email sign-in / create-account** flow that "Continue with email"
  leads to (the setup flow itself is built).
- Optional: swap the slide-1 icon hero for a custom illustration if design time
  allows.
- Note: `_Onb` (onboarding), `_L` (login), and `_S` (setup) duplicate the same
  color hexes. If they drift, extract a shared public palette.
