# Drafting: screenshots of app screens without a device

Renders any widget or screen of the app to a PNG from a headless
`flutter test`, with the app's real fonts, icons, colours and layout. Use it
to show the user what a UI change looks like, before and after, without an
emulator.

It lives under `linux/` because it runs on the Linux host `flutter test`
uses; it has nothing to do with the Linux desktop runner, and CMake never
sees it.

## What is here

- `draft_kit.dart` — the helpers:
  - `loadDraftFonts()` — call from `setUpAll`. Loads Roboto from the SDK for
    text and every font in the bundle's manifest (Lucide icons included).
    Without it, `flutter test` draws text and icons as solid boxes.
  - `resetDraftStorage()` — call from `setUp`: fresh in-memory
    SharedPreferences, so every draft starts as a new install.
  - `shootScreen(tester, name, widget, {size, settle})` — pumps the widget
    inside `DraftApp`, lets it settle, saves `<tag>_<name>.png`.
  - `pumpDraft` + `saveDraft` — the same in two halves, for drafts that tap,
    scroll or type before the picture.
  - `DraftApp` — the app shell without a device: `ThemeProvider`, the
    localizations `app.dart` installs, and a navigator, so screens can push
    and read `Navigator.of`.
  - `DraftOverMap` — puts a sheet over a map stand-in with the nav bar
    painted on top. MapLibre is a platform view and draws nothing in a test.
  - `DraftNavBar` — the floating nav bar's footprint on its own.
- `render.sh` — runs draft files and says where the PNGs went.
- `examples/example_draft_test.dart` — one plain screen, one seeded with
  stored data, one sheet over the map. Copy it.
- `store/` — the fastlane store screenshots, with the captured data they
  are rendered from; see its README.

## Getting Flutter

Cloud containers usually have no Flutter. Install the version CI pins
(`.github/workflows/main.yml`) outside the repo:

```sh
curl -sSo /tmp/flutter.tar.xz \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.38.1-stable.tar.xz
tar xf /tmp/flutter.tar.xz -C "$HOME" && rm /tmp/flutter.tar.xz
git config --global --add safe.directory "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
```

It is about 1.5 GB unpacked; run the download in the background and read
the code meanwhile.

## Rendering

1. Write a draft file under `linux/drafting/`, named `*_draft_test.dart`.
   Start from `examples/example_draft_test.dart`. One `testWidgets` per
   picture; give each a `name` that says what state it shows
   (`empty_destination`, `arrive_by`), not what it is.
2. Render the current code first, as the baseline:

   ```sh
   linux/drafting/render.sh --tag before --out "$SCRATCH/drafts" linux/drafting/my_draft_test.dart
   ```

3. Make the change, render again with `--tag after`.
4. Look at every PNG yourself before sending it (read the image file).
   Overflow stripes, boxes instead of text, or an empty frame mean the
   draft is wrong, not the design.
5. Send the before/after pairs to the user.

Draft files are working files: git ignores everything in this directory
except the tooling and `examples/`, so drafts stay out of commits. `flutter
test` with no arguments only runs `test/`, so a draft never runs in CI — but
`flutter analyze` does read it, so it must still be clean. `--out` defaults to `build/drafts`, which git ignores.

## Rendering the states that matter

- **Seed data through the services**, as the app would have written it:
  `FavoritesService.saveFavorite(...)`, `SavedTripsService.saveTrip(...)`. For
  itineraries, `test/support/plan_fixtures.dart` builds planner JSON; import
  it relatively (`../../test/support/plan_fixtures.dart`).
- **Widgets with many callbacks** (the route card) are easier through a test
  host from `test/support/` that stubs them all; import it the same way.
- **The whole page of a scrolling screen:** pass a taller `size`, or
  `pumpDraft`, `tester.drag(find.byType(Scrollable).first, ...)`, then
  `saveDraft`.
- **Phone width is 400 logical px** (`kDraftPhone`). Check tight layouts at
  360 too.
- **Time-dependent text** ("Today", "in 5 min") reads `DateTime.now()` in
  most widgets; build fixtures relative to now, or the draft ages.

## What it cannot show

- The map itself, and anything else that is a platform view: its area stays
  blank. A screen with a map in it still renders around it, and a map tap
  can be simulated by calling the widget's own callback:
  `tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapClick!(...)`.
- Anything that needs the network: geocoder results, live departures,
  planning. Screens that fetch on open show their loading or error state;
  seed what they would have loaded, or draft the widget that displays it.
- Animations mid-flight: a draft is one frame. Use `settle` or
  `tester.pump(duration)` to pick the moment.
- Platform chrome: status bar, system navigation, keyboard.
