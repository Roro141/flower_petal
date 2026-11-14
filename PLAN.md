# Windowsill plan

## Where we are

Done (milestone 0, the spike):
- The iOS app and the widget extension share an App Group.
- Supabase holds a petals table (`petals_v2`, plus the `latest_petals_v2` view). The test policies are wide open: anon can select and insert.
- The app inserts a petal. The widget reads the latest petal for each owner and draws a simple solid-colour flower.
- It has been tested on real iPhones: a row inserted for one person changes the flower on the other person's widget.

Done (milestone 1, real flowers):
- Petals are mirrored half-polygons on code-drawn papers, repeated around one of five centres, with a stem, leaves and one of five pots.
- The widget shows the plants as PNGs rendered by `FlowerRenderer`; it never draws them itself.
- Tested on a real iPhone: a petal inserted in Supabase for the other person showed up on the widget without opening the app, about 30 seconds later.
- Unit tests (Swift Testing) in `WindowsillTests/` cover petal geometry, stored rows, seeded randomness and the PNG renderer.

Not done: cutting, paper textures, accounts, wind, Mac.

## Working rules

- One milestone at a time. Finish its acceptance checks before starting the next.
- Keep the app building and running after every step. If a change breaks the build, fix it before moving on.
- Share one rendering code path between the app and the widget. Never draw a flower two different ways.
- Widgets are static snapshots:
  - no animation in widget views
  - no network calls in widget views (fetch in the timeline provider)
  - keep reloads cheap
- Never add UI copy that explains the interface, and never add time tracking (no weeks, streaks, timestamps or counts on screen).
- Accessibility:
  - 44 pt minimum tap targets
  - VoiceOver labels on flowers, e.g. "junie's flower"
  - Dynamic Type for body text
  - a Reduce Motion version of every animation
- Never commit secrets. The Supabase publishable key is fine in the app. The service/secret key and the APNs .p8 key never go in the app or the repo.
- Commit after each milestone with a short message.

## File layout

Keep the existing structure. Folders are synced by Xcode, so a new file dropped
into a folder joins that folder's target(s) automatically.

```
flower/                app target
  MyApp.swift, ContentView.swift
  SamplesView.swift    milestone 1 sample screen
  (later: Cut/, Garden/ subfolders when those screens exist)
Shared/                member of BOTH targets
  Flower.swift         spike flower model, App Group store, colours
  Petal.swift          Petal model, PetalPath, sample shapes
  FlowerView.swift     draws a flower from a Petal (the one rendering path)
  Papers.swift         pattern fills (code-drawn until milestone 3)
  FlowerRenderer.swift ImageRenderer → PNG in the App Group
  PetalService.swift   Supabase fetch/insert
WindowsillWidget/      widget extension
  WindowsillWidget.swift (provider + view), WindowsillWidgetBundle.swift
WindowsillTests/       unit tests, hosted in the app (run on a simulator)
```

Only split or move files when a file gets hard to read.

## Milestone 1: real flowers (done)

Goal: the flowers look like the designs: patterned paper petals, mirrored on a fold, repeated around a centre, with a stem and a pot.

Data: use the existing `points` jsonb as an array of `[x, y]` pairs.
- Coordinates are normalized 0–1. They describe the right half of one petal.
- `[0, 0]` is the base, sitting on the fold line x = 0. The tip is near `[0, 1]`.
- 5–12 points per half, in order from base to tip.
- Rows with no points (spike rows) fall back to a sample shape picked from the owner.

Steps:
1. [x] `Petal` model and `PetalPath` (mirror + slight smoothing). Sample screen shows the 5 hard-coded shapes.
2. [x] Papers: code-drawn fills (table below).
3. [x] `FlowerView(petal:size:)`: radial repeat, crease, offset shadow, varied centre.
4. [x] Stem, 1–2 leaves, and five hand-cut pot shapes with rim strips.
5. [x] Supabase: read/write `points`, `pattern`, `n_petals`; the app plants a random sample petal.
6. [x] `FlowerRenderer`: PNG per petal id in the App Group; the widget shows the images only.

| Paper | Colours |
| --- | --- |
| dots | #D9574C, cream dots |
| gingham | #3A6EA5 |
| stripe | #A77AA5 |
| ditsy | #EDB93F, white and red specks |
| newsprint | #EE8A4E, ink lines |

Sample shapes: rounded, pointed, notched tip, slim, heart notch.

Done when:
- Five clearly different flowers render in the app.
- The widget shows the same flowers as images.
- Changing a row in Supabase changes the widget flower.
- The project builds with no warnings about widget memory.

## Milestone 2: the cutting screen

Goal: the core moment. You draw half a petal from the crease, it unfolds into your flower, and you plant it.

Screen (phone):
- A dark green cutting mat background (#3E5747) with a faint grid and a ruler along the top.
- A folded sheet of the chosen paper, with the crease on the left edge.
- A small notch marks where the cut starts. Snap the start to the crease if the finger lands within 24 pt.
- Draw with your finger:
  - Render the line as a solid ink cut.
  - Show a small knife tip drawn 44 pt ahead of the finger so the finger doesn't hide it.
  - A loupe in a corner shows the tip magnified.
  - Lifting the finger pauses the cut. The next touch near the end of the line resumes it.
- The cut must end back on the crease. If it doesn't, show a faint dashed ghost line to the crease and a small 4 pt nudge animation. No error text.
- Paper picker: a fan of 5 paper sheets.
- Accessible alternative: 4 preset shapes as 48 pt cut-paper tiles.
- Buttons: "undo" as a tape tab (removes the last stroke; long-press clears), and a primary ticket button "cut".

Unfold screen:
- The petal rotates out into the full flower: about 1 s total, each petal staggered by 90 ms, ease-out.
- With Reduce Motion on, it fades in instead.
- Buttons: "recut" (secondary ticket) and "plant it" (primary ticket).

Saving:
- Simplify the drawn path to 5–12 points.
- Normalize to 0–1 with the base at [0, 0].
- Insert into petals with the pattern and petal count.
- Re-render the PNG and reload the widget timeline.

Ticket button component:
- A dark body plus a perforated stub.
- On release: the body tilts slightly (0.18 s ease-out), the stub tears off and falls (0.35 s, cubic-bezier(.5, 0, .75, 0)), and navigation happens in the same frame.
- The full tear plays only on the first press after the app opens. Later presses get a 120 ms tick.
- With Reduce Motion on, the stub dims to 40%.

Done when:
- You can cut a petal with a finger and with a preset.
- It unfolds, is saved, and appears on both phones' widgets.
- Undo works.
- VoiceOver can complete the flow using a preset.

## Milestone 3: paper that looks real

- Add 5 scanned paper textures to the asset catalog: paper_dots, paper_gingham, paper_stripe, paper_ditsy, paper_news. Use them as image fills clipped to the petal path, replacing the code-drawn patterns.
- Make edges slightly irregular: perturb the clip path by 0.5–1.5 px of noise, but never distort the pattern inside it.
- Add a 3–5% paper-grain overlay image and small cast shadows that vary with each piece's height.
- Build the window scene for the widget and the garden, as cut-paper pieces:
  - wall
  - sky
  - wood frame strips that are slightly misaligned
  - curtains (left and right different lengths)
  - a sill board
  - names under the pots in Special Elite, 13 pt
  - a resting friend shown as desaturated paper with a drooped head, never transparency

Done when side by side with the mockups on the Windowsill canvas, it reads as paper, not vector art.

## Milestone 4: accounts, groups, invites

- Sign in with Apple through Supabase Auth.
- Tables:
  - `profiles(id uuid = auth.uid, name)`
  - `groups(id)`
  - `members(group_id, profile_id)`, maximum 6 per group
- Change petals.owner to profile_id, and add group_id.
- Invite link: a universal link such as windowsill.app/join/<code>. It opens the app and adds you to the group.
- Row-level security: replace the open test policies so members can only read and insert within their own groups.
- The widget sill shows your group, with you first and the others in the order they joined.

Done when two fresh accounts can join one group through a link, each sees only that group's petals, and the open policies are gone.

## Milestone 5: faster updates (widget push)

- Implement `WidgetPushHandler` in the widget and save each device's widget push token to `widget_tokens(profile_id, token)`.
- Write a Supabase Edge Function, triggered on a petals insert, that sends an APNs widget push (`apns-push-type: widgets`) to every other member's tokens. The .p8 key lives only in the function's secrets.
- Keep timeline reloads as the fallback. Pushes are budgeted and best-effort.

Done when a new petal usually shows on a friend's widget within a minute or two.

## Milestone 6: wind

- Trigger: a server-side event per group. The owner hasn't decided whether it fires at random a few times a day or when a friend cuts a new petal, so ask before building the trigger.
- In the app (garden screen):
  - Flowers lean right 10–22° each, staggered 40 ms from left to right.
  - Lean in 0.45 s ease-out, hold 0.45 s, then spring back (response 0.9, damping 0.55).
  - The curtains billow.
  - 1–2 petals blow off and land on the sill.
  - With Reduce Motion on: no lean, and fallen petals fade in over 0.2 s.
- Widgets: never show a lean. After a gust, the next timeline entry shows 1–2 fallen petals on the sill.
- A gust you missed while the app was closed replays once when you open it, compressed to 1.2 s.

## Milestone 7: Mac

- Add a macOS target to the same multiplatform project and reuse Shared/.
- Desktop widget: the same window widget as on iOS.
- A `MenuBarExtra` panel with the full window scene. The wind plays here with the full animation.
- A cut window:
  - click to place points, drag to curve a segment
  - click the first point, or press Return, to close the shape
  - Delete removes the last point, Esc cancels
  - paper choices in a side column

## Later (not now)

- watering
- the pressed keepsake page
- Android (Kotlin + Jetpack Glance)
- App Store submission
