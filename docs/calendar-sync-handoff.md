# Handoff: add saved trips to a chosen calendar

Status: **planned, not implemented.** This file is the spec for the draft PR
that adds it; delete it in the PR that implements it.

Follows #88. Builds on #90 (the one-off "Add to calendar" row in the share
sheet, `CalendarEvent` and `itineraryAsCalendarEvent`).

## Goal

An opt-in setting that puts every trip the rider **explicitly saves** into one
calendar they chose. Off by default. Calendar permission is requested only
when the rider switches it on. Recent trips and plain searches never get an
event, so quick commute checks don't clutter the calendar.

## Ground rules (from the owner, not negotiable)

1. **Never mess up the rider's calendar.** The app only ever touches events it
   created itself, and only while they are exactly as it wrote them. No
   searching the calendar, no bulk deletes by query, no moving events between
   calendars.
2. **Planned times only.** A calendar is for long-term planning: events hold
   the provider's original plan, never live data. Live refreshes never touch
   the calendar.
3. **Native code in its own file**, not in `MainActivity.kt`.
4. The settings entry goes in a **new "Synchronization" section beneath
   "Preferences"** in `SettingsScreen`, not inside Preferences.
5. Screen title and the tile that opens it share one string
   (`CalendarSettingsScreen.title`), the pattern #90 started with
   `ShareTripSheet.title` (see #91).

## Decisions

| Question | Decision |
|---|---|
| How many calendars | One. |
| Rider changes the calendar later | Applies to new saves only. Existing events stay where they are. |
| Live delays | Never written. |
| Rider renames a saved trip | Rename the event's title, guarded (below). |
| Rider unsaves a trip | Delete the event, guarded. |
| App prunes a trip 30 days after arrival (`pruneExpired`) | Keep the event (it's history); forget the mapping. |
| Rider edited/moved/deleted the event in their calendar | Leave it alone forever; forget the mapping. Never recreate. |
| Permission revoked in system settings | Sync becomes a no-op; settings screen shows the switch off with a note. |
| Turning the setting on with trips already saved | Offer once: "Add your N upcoming saved trips?" |
| Turning the setting off | Ask: "Remove the trips already added?" (Remove / Keep). Remove is guarded per event. |

## The guard: only touch what we wrote

At insert, store per trip:

```
tripId → { eventId, calendarId, fingerprint }
```

`fingerprint` = hash of exactly the title, start millis, end millis and
description written. Store it in SharedPreferences under a new key (e.g.
`PrefsKeys.calendarSyncEvents`), JSON map. New key, so no migration.

Before **any** update or delete:

1. Read that one event by id (`readEvent`).
2. Proceed only if it exists, is not deleted (`Events.DELETED == 0`), is still
   in `calendarId`, and its recomputed fingerprint equals the stored one.
3. Otherwise: do nothing to the calendar, drop the mapping.

After a guarded rename, store the new fingerprint.

## Planned times

`SavedTrip.itineraryJson` is the planner snapshot, which can already carry
real-time data at save time and is later overwritten by
`SavedTripsService.storeLiveItinerary`. So the event must be built from
**scheduled** times, not `Itinerary.startTime`/`endTime`:

- `Leg.scheduledStartTime` / `Leg.scheduledEndTime` exist
  (`lib/models/itinerary.dart`, ~L418).
- Start = first leg's `scheduledStartTime ?? startTime`; end = last leg's
  `scheduledEndTime ?? endTime`. Street legs usually have no schedule: derive
  their planned times from the adjacent ride's scheduled time minus/plus the
  walk duration.
- The description must use planned times too: add a planned variant of
  `itineraryAsText` (e.g. a `planned: true` flag that reads scheduled times and
  leaves out live-only notes such as "(cancelled)"). Put the shared logic in
  `lib/utils/`, with tests (AGENTS.md).
- Switch #90's one-off share-sheet row to the same planned builder, so both
  paths write identical events. `itineraryAsCalendarEvent` gains the planned
  behaviour; its tests change accordingly.

## Implementation

### 1. Native bridge: `android/app/src/main/kotlin/one/wafler/transportia/CalendarBridge.kt`

A `MethodChannel` (`transportia/calendar`) over `CalendarContract`.
`MainActivity.configureFlutterEngine` gets one line:
`CalendarBridge.register(flutterEngine, this)`.

| Method | Does |
|---|---|
| `listCalendars` | id, display name, account name, colour, for calendars with `CALENDAR_ACCESS_LEVEL >= CAL_ACCESS_CONTRIBUTOR` and `VISIBLE = 1` |
| `insertEvent` | `calendarId`, title, description, location, `DTSTART`, `DTEND`, `EVENT_TIMEZONE` (required by the provider; use the device zone), `AVAILABILITY_BUSY`. Returns the new id |
| `readEvent` | by id: calendar id, title, description, dtstart, dtend, deleted. Null if gone |
| `updateEventTitle` | by id, title only |
| `deleteEvent` | by id |

All calls catch `SecurityException` (permission revoked) and return a typed
error the Dart side maps to "not permitted". No sync-adapter URIs, no
`ExtendedProperties` (those need a sync adapter).

Android only. iOS/desktop: setting hidden (`CalendarService.isSupported`).

### 2. Manifest

`android/app/src/main/AndroidManifest.xml`: add `READ_CALENDAR` and
`WRITE_CALENDAR`. Read is needed for `listCalendars` and the guard's
`readEvent`. Request at runtime with `Permission.calendarFullAccess`
(`permission_handler`, already a dependency; maps to both on Android).

### 3. Dart bridge + sync service

- `lib/services/calendar_bridge.dart`: thin typed wrapper over the channel,
  behind an interface so tests use a fake.
- `lib/services/calendar_sync_service.dart`:
  - Holds: enabled flag, chosen calendar id, the mapping. New `PrefsKeys`.
  - `onSaved(SavedTrip)`, `onRenamed(SavedTrip)`, `onRemoved(String tripId)`,
    `addExisting(List<SavedTrip>)`, `removeAll()`, `forgetPruned(ids)`.
  - Every method: no-op when disabled, unsupported or not permitted; never
    throws (a failed calendar write must never fail a save).
  - `onSaved` for a trip that already has a mapping does nothing (no
    re-insert, no update: the first plan stays).

### 4. Hook into `SavedTripsService` (`lib/services/saved_trips_service.dart`)

After `_persist` in `saveTrip`, `renameTrip`, `removeTrip`, and with the ids
removed in `pruneExpired`, call the sync service through an injectable static
hook (fake in tests). Fire-and-forget (`unawaited`) so the "Trip saved" toast
in `lib/widgets/save_trip_button.dart` isn't delayed.
**Not** from `storeLiveItinerary`.

### 5. UI

- `lib/screens/calendar_settings_screen.dart`, `static const title =
  'Calendar'`, built on `AppPageScaffold` like
  `lib/screens/location_settings_screen.dart`:
  - `AppToggleSwitch` row "Add saved trips to calendar", off by default.
  - Switching on → request permission. Granted → calendar picker. Denied →
    switch stays off, explanation, "Open app settings" when permanently
    denied (copy `_openAppSettings` from the location screen).
  - Chosen calendar row (name, account, colour dot) → picker.
  - A short note: "Only trips you save. Planned times; delays aren't added."
- Calendar picker as a `BottomOverlayCard` sheet listing writable calendars.
- `lib/screens/settings_screen.dart`: new `SettingsSection(title:
  'Synchronization')` between Preferences and About, one `SettingsTile`
  (`LucideIcons.calendarSync` or `calendarPlus`) with
  `title: CalendarSettingsScreen.title`, subtitle "Add saved trips to your
  calendar". Hide the section where unsupported.
- Optional: share-sheet row reads "In your calendar" for a trip that already
  has a mapping.
- Drafts via `linux/drafting/` and send them **before** wiring up
  (AGENTS.md: bigger UI changes get drafts first).

### 6. Tests

- Planned-times builder: live delay in the snapshot does not move the event;
  street legs around rides; no schedule falls back; past midnight.
- Sync service with a fake bridge: off by default; insert stores mapping and
  fingerprint; rename and delete go through only when the fingerprint
  matches; edited, moved or deleted event is left alone and the mapping
  dropped; permission missing is a no-op; prune forgets without deleting;
  saving again doesn't re-insert; `removeAll` is per-event guarded.
- `SavedTripsService` calls the hook on save/rename/remove/prune, never on
  `storeLiveItinerary`.
- Settings screen: permission granted/denied/permanently denied flows with a
  fake permission; Synchronization section shows the tile.

### 7. Manual check before merging

On a device with Etar and with Google Calendar: enable, pick calendar, save,
rename, unsave; edit an event by hand and confirm the app no longer touches
it; revoke the permission and confirm nothing breaks.
