# Documentation that disagrees with the code

Places where a document, a doc comment or a README states something the
implementation does not do. Each entry says what is written, what is true, and
which of the two looks wrong.

Tick an entry off by fixing one side and deleting the row. Nothing here has
been changed yet — resolving a contradiction is a decision about intent, not a
cleanup.

Last swept: 2026-08-12, against `e60c97e`.

---

## 1. `AGENTS.md` names an asset that does not exist

- **Written** — "Keep `pubspec.yaml` assets in sync (e.g.,
  `assets/images/welcome-image.png`)."
- **True** — the file is `assets/images/welcome-image.webp`. That is what
  `pubspec.yaml:56` declares and what `welcome_screen.dart:125` loads. There is
  no `.png`.
- **Wrong side** — the document. A one-word fix, but the example is the only
  concrete thing that line says, so it is worth it being right.

## 2. `AGENTS.md` says avoid `print`; the code logs with `debugPrint`

- **Written** — "Avoid `print`; use logs or comments when necessary."
- **True** — there is no `print` anywhere in `lib/`, so the rule is being
  followed. But "logs" is ambiguous: the code uses both `debugPrint` (10 sites,
  mostly in `itinerary_detail_screen.dart` and `map_screen.dart`) and
  `dart:developer`'s `log` (in `routing_options_service.dart` and
  `itinerary.dart`).
- **Wrong side** — arguably neither, but the guidance does not say which of the
  two to reach for, and the codebase has not picked one. Worth deciding.

## 3. `AGENTS.md` names an example test file that does not exist

- **Written** — "Place tests in `test/` with `_test.dart` suffix (e.g.,
  `route_field_box_test.dart`)."
- **True** — there is no `route_field_box_test.dart`, and
  `lib/widgets/route_field_box.dart` (530 lines) has no direct test at all. The
  example was presumably aspirational.
- **Wrong side** — both, in different ways. Either pick an example that exists,
  or write the test the example implies.

## 4. `SavedTripsService`'s class doc undersells what it does

- **Written** — "there is no cap and nothing is evicted to make room — a saved
  trip disappears only when the user removes it, or once it is long enough in
  the past to be clutter."
- **True** — accurate, and `_keepPastTripsFor = Duration(days: 30)` is the
  "long enough". The doc never gives the figure, so a reader has to find the
  constant to learn a saved trip is dropped after a month.
- **Wrong side** — the document, mildly. Naming the window in the class doc
  would make the one surprising behaviour discoverable.

## 5. `TransitModeGroup.allSelectable` re-lists what the enum already declares

Not a doc mismatch — a latent bug. Filed here because this is where findings
that need a decision live.

- **Written** — the doc comment on `allSelectable`
  (`lib/models/transit_mode_group.dart:48`) presents it as "every mode a rider
  can pick", derived from the groups.
- **True** — it is a hand-written list. The five rail modes, the two metro
  modes and the two bus modes are spelled out again as literal
  sub-lists, and they are the same values already passed to
  `rail(...)`, `metro(...)` and `bus(...)` a few lines above. Only `extras` is
  spread from its own constant.
- **Consequence** — adding a mode to a group's constructor arguments does not
  add it to the picker, and nothing fails: the mode simply never appears as a
  tick. `transit_mode_group_test.dart` asserts every *group* mode is in
  `allSelectable`, so the test would catch it — but only if someone runs it
  while wondering why their new mode is missing.
- **Wrong side** — the code. `allSelectable` should be built from
  `values.expand((group) => group.modes)` plus `extras`, at which point the
  duplication cannot drift.

---

## Checked and found consistent

Recorded so the next sweep does not re-verify them:

- `AGENTS.md`: "`lib/api/` … the only place that talks to `package:http`" —
  true, `transitous_client.dart` is the sole importer.
- `test/fixtures/transitous/README.md`'s trimming claims — all four hold
  exactly: `map_routes.json` has 1 route / 3 polylines / 5 stops,
  `one_to_all.json` has 30 entries, `map_stops.json` has 20,
  `debug_transfers.json` has 5 equivalences and 15 transfers.
- `changeover.dart`: "Ten minutes is room to read the screen and walk" matches
  `kReplanHeadStart = Duration(minutes: 10)`.
- `SavedTripsService.getSavedTrips` — "soonest departure first" matches
  `_sort`.
- `transitous_endpoint.dart` — the six `prefKey`s the doc says must not change
  (`plan`, `trip`, `stoptimes`, `mapTrips`, `mapStops`, `geocode`) are all
  present and spelled as stated.
- The legacy mode-count threshold, previously entry 6. `git show
  8cb9437:lib/screens/transit_options_screen.dart` lists exactly 28 modes in
  `_transitModeOptions`, so 28 was right; `TransitMode` having 33 values today
  is irrelevant, because the only data this reads was written by 1.0.3. The
  check now lives in `MigrateV103ToV104` and runs once per install.
- `AGENTS.md`'s module map, previously entry 2 — fixed in `7fb61a9`; the entry
  outlived the fix by one commit.
