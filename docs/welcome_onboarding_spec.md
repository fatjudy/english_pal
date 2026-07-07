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

## Open items / next

- Wire real authentication: Google Sign-In + email, `onCreateAccount`, and the
  Terms / Privacy links (convert `LoginScreen` to `StatefulWidget` for the link
  recognizers).
- Build the **email sign-in / create-account** flow that "Continue with email"
  and "Create an account" lead to.
- Optional: swap the slide-1 icon hero for a custom illustration if design time
  allows.
- Note: `_Onb` (onboarding) and `_L` (login) duplicate the same color hexes. If
  they drift, consider extracting a shared public palette.
