# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: application code.
  - `lib/main.dart`: entrypoint; boots `Transportia`.
  - `lib/app.dart`: app shell, routing, locale setup.
  - `lib/environment.dart`: app-wide constants and API version resolution.
  - `lib/api/`: Transitous (MOTIS) client — endpoint registry, HTTP client,
    query formatting — and the Nominatim client for place details. The only
    place that talks to `package:http`.
  - `lib/models/`: app-level models; `lib/models/transitous/` holds the
    response models mirroring the MOTIS schema.
  - `lib/screens/`: UI screens (e.g., `map_screen.dart`, `welcome_screen.dart`),
    with a subdirectory per screen large enough to be split up.
  - `lib/services/`: platform/data services (e.g., `location_service.dart`).
  - `lib/migrations/`: storage migrations; one at a time, see Storage & Migrations.
  - `lib/utils/`: pure helpers — no widgets, no `BuildContext`. Shared logic
    belongs here.
  - `lib/widgets/`: reusable UI components (e.g., `route_field_box.dart`),
    grouped into `journey/`, `map/`, `options/`, `search/`, `buttons/` and
    `skeletons/`.
  - `lib/providers/`, `lib/theme/`, `lib/constants/`, `lib/animations/`:
    app state, colours, preference keys, shared curves.
- `docs/`: the privacy policy and terms the app links to (`legal/`), audit trackers (`doc-contradictions.md`, `unused-code.md`) and
  the measurements behind tuned constants (`geocode-place-bias.md`).
- `linux/drafting/`: renders app screens to PNGs for design review; see its
  README. Unrelated to the Linux desktop runner beside it.
- `assets/`: images and static assets (declared in `pubspec.yaml`).
- `test/`: Dart tests (`*_test.dart`).
- Platform runners: `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`.

## Build, Test, and Development Commands
- Install deps: `flutter pub get`
- Run app (auto‑select device): `flutter run`
  - Web example: `flutter run -d chrome`
- Static analysis: `flutter analyze`
- Format code: `dart format .` (CI-friendly check: `dart format . --set-exit-if-changed`)
- Unit tests: `flutter test`
- Coverage (optional): `flutter test --coverage`
- Release builds: `flutter build apk` | `flutter build ios` | `flutter build web`

## Coding Style & Naming Conventions
- Dart/Flutter style, 2-space indent; prefer `final`/`const` and trailing commas.
- File names: `snake_case.dart`. Screens: `*_screen.dart`; services: `*_service.dart`.
- Types: `UpperCamelCase`; members/functions/vars: `lowerCamelCase`.
- Avoid `print`; use logs or comments when necessary.
- Lints: `flutter_lints` configured via `analysis_options.yaml`. Fix all `flutter analyze` issues before submitting.

## Code Structure
- Prefer guard clauses; four early returns beat one nested chain.
- Split a `build` deeper than ~8 levels into a private method or a `StatelessWidget`.
- Never dispatch on a running index; build a list of section builders and index into it.
- Name the condition, not the branch: `if (position.isAtStop)`, not `if (a && b && i == c)`.
- Lift logic duplicated across unrelated files: pure helpers to `lib/utils/`; shared UI to `lib/widgets/`; shared computation onto the model.
- Give a shared widget its variants as named constructors (`SelectableTick.large`), not optional-argument piles.
- Merging drifted copies: unify on the better behaviour; say so in the commit.
- Name literals that are thresholds, intervals, limits, conversion factors, tolerances or meaningful indices.
- Leave widget dimensions inline; name one only where two things must agree on it.
- Scope constants where used: file-level `_k…`; `static const` on the class; `lib/theme/` app-wide.
- Comment why code is as it is; delete comments describing what it used to be.
- Keep comments on constraints still live, even when they read as history.

## Testing Guidelines
- Place tests in `test/` with `_test.dart` suffix (e.g., `route_field_box_test.dart`).
- Use `flutter_test`. Keep tests deterministic; mock location/permissions when needed.
- For API code, inject an `http.Client` into `TransitousClient` and drive it
  with `MockClient` from `package:http/testing.dart`. Parse tests should read
  the real captures in `test/fixtures/transitous/` rather than hand-written
  JSON; see the README there before re-capturing.
- Aim to cover core logic in `services/` and widget behaviors with golden or widget tests where practical.
- Always test: logic extracted to `lib/utils/`; two implementations merged into one; anything with an index, boundary or clock; the empty and degenerate cases.
- Pass the clock in (`DateTime? now`); never call `DateTime.now()` in a test.
- Seed old-version storage with literal key names, not `PrefsKeys`; constants move, released key names do not.

## Storage & Migrations
- SharedPreferences is the only store; no database.
- One migration class in `lib/migrations/` at a time, spanning last-released → in-development; delete and replace it when a release ships.
- Both endpoints are released versions; never migrate between trunk states.
- Upgrade only; downgrades are unsupported.
- Migrations run from `main()` before `runApp`; services read storage lazily, so anything later races.
- Migrations must be idempotent, and must not throw past their own boundary.
- No version suffixes in key names; the stamp is `PrefsKeys.storageVersion`.
- Old key names live in the migration as literals, not in `PrefsKeys`.
- Bump `pubspec.yaml` and the migration pair together; `AppVersion` reads the package.

## UI Changes & Screenshots
- Any change the user can see gets screenshots of your work sent to the user: render them
  with `linux/drafting/`
- For bigger redesignd, send drafts before writing tests or wiring it up; the design usually moves once the user sees it.

## Branches & Releases
- `master` is the default branch; open PRs against it.
- Every push to `nightly` publishes a release to friends' phones through the
  F-Droid repo. `nightly` is updated from `master` by PR.
- Never push or merge to `master` or `nightly` yourself; open a PR and leave
  merging to the owner.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject (e.g., “Improve welcome transition”).
- Group related changes; keep diffs focused. Reference issues if applicable.
- PRs must include:
  - Clear description and rationale.
  - Test plan (commands run, devices/simulators tested).
  - Confirmation that `flutter analyze` passes and code is formatted.
- Run `flutter analyze`, `flutter test` and `dart format .` before each commit, not once at the end; analyze must be clean, not merely no-worse.

## Security & Configuration Tips
- Do not commit secrets or keys. Manage platform permissions via `permission_handler` and update `AndroidManifest.xml`/`Info.plist` as needed.
- Keep `pubspec.yaml` assets in sync (e.g., `assets/images/welcome-image.png`).
