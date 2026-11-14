# Windowsill: project brief for Claude in Xcode

## What we're building
Windowsill is a shared paper-collage windowsill for 2–6 close friends. It lives in iPhone home-screen widgets and in a Mac desktop widget plus a menu-bar panel.

- Each friend cuts **one petal** from patterned paper folded in half. The app mirrors it across the fold and repeats it around a centre (5–8 times) to make that friend's flower.
- Everyone's flowers sit side by side in pots on one windowsill, with a name under each pot.
- Every so often a **gust of wind** blows through: flowers lean, the curtains billow, and a petal or two blows off and lands on the sill.
- Watering (tap a friend's flower to leave a drop) is optional and can come later.
- **No time tracking.** No weeks, seasons, streaks, timestamps or counts anywhere in the UI.

## Stack
- Swift + SwiftUI, one multiplatform Xcode project (iOS + macOS).
- WidgetKit for home-screen and desktop widgets. Interactive buttons use App Intents.
- `MenuBarExtra` for the Mac menu-bar panel.
- Supabase (Postgres, auth, row-level security, edge functions) as the backend. Sign in with Apple. Invites by link.
- APNs for pushes. WidgetKit push updates (`WidgetPushHandler`, iOS 26+) are budgeted and opportunistic, so they add to timeline reloads but never replace them.
- Android (Kotlin + Jetpack Glance) is out of scope for v1.

## Data model (draft)
- `profiles(id, name)`
- `groups(id)`, `members(group_id, profile_id, joined_at)`. A group has 2–6 members.
- `petals(id, profile_id, group_id, points jsonb, pattern text, n_petals int, created_at)`. `points` is the half-petal polygon, cut along the fold, about 0.5 KB.
- `gusts(id, group_id, seed int, created_at)`
- Optional, later: `waterings(from_id, to_id, created_at)`

## Rendering rules
- A flower is drawn from the petal polygon: mirror it across the fold, then repeat it radially.
- Paper patterns: dots (red), gingham (blue), stripe (lilac), ditsy (yellow), newsprint (orange). Use scanned paper textures as image assets, not code filters.
- Widgets are rendered as static images. Pre-render each flower to a PNG in the App Group container and have the widget display those images. Widgets never animate the gust. After a gust they just show the settled state, with fallen petals on the sill.
- The full gust animation plays in the app and in the Mac menu-bar panel:
  - lean 0.45 s, ease-out (.2, .8, .2, 1)
  - 40 ms stagger, left to right
  - hold 0.45 s
  - spring back (response 0.9, damping 0.55)
  - with Reduce Motion on: no lean; fallen petals fade in over 0.2 s
- Primary buttons are "ticket" buttons. The stub tears off on release.
  - body: 0.18 s ease-out
  - stub falls: 0.35 s, cubic-bezier(.5, 0, .75, 0)
  - navigate in the same frame
  - widget tickets are static

## Design system
- Colours:
  - ink #2B211A, grey #5A5249, cream #FBF6EC, wall #F1E7D5, sky #DCE4E1
  - wood #C29A6B, sill #B98E62, mat #3E5747, drop #5F95BF
- Type: Special Elite for titles (20) and labels (13, never below 12). Atkinson Hyperlegible for body (15) and buttons (Bold 15).
- Tap targets are 44 pt minimum. Every flower is a button with a VoiceOver label ("junie's flower").
- Don't make it look AI-made:
  - no gradients, glow or glass
  - no emoji or stock icons
  - no copy that explains the UI
  - no perfectly symmetric repeats
- The full mockups live on the Windowsill canvas, in the "v4" section.

## First milestone: the widget spike (one weekend)
Goal: find out how it feels when a friend's change shows up on your home screen.
1. A bare SwiftUI app plus a widget extension sharing an App Group.
2. A Supabase table `petals` with 2 hard-coded users. Draw flowers as solid-colour shapes for now.
3. The app has one button, "plant a random petal", which writes a row.
4. The widget shows both users' flowers. It reloads on its timeline, and the app sends a WidgetKit push when the other user plants.
5. Put it on two real iPhones for a few days. Measure how long until the other phone's widget updates, and note whether you actually look at it.

No accounts, invites, cutting screen, Mac app or paper art until the spike feels right.
