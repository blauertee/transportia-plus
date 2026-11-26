# Navigation

How the app moves between screens, and where back takes the rider. Add a new
path here in the same commit that adds it.

## Two kinds of back

- **Leaving a screen** slides it back out the way it came. Every screen is
  opened with `context.openScreen` and every sheet with `context.openSheet`
  (`lib/navigation/routes.dart`), so this is the same everywhere.
- **A step** undoes something on the screen you are on — a picked stop, a
  card over the map, a tab other than routing — and is instant. Steps are
  declared with `BackStep` (`lib/navigation/back_step.dart`); one press undoes
  the innermost step that is showing.

The on-screen back button and the system back take the same path.
`test/navigation_guard_test.dart` fails on any other way of doing either.

## The tree

Each screen goes back to the one it hangs from. Sheets stay open under a
screen opened from them, so back returns to the sheet. Exceptions are marked.

- **Routing** (tab; back: steps below, then leaves the app)
  - Steps, innermost first: focused vehicle → quick settings → stop card →
    long-press pin → search card raised to the top is lowered to where it
    rests → search card lowered over the map is raised again
  - Origin / destination search
    - Map place picker
  - Travel through (hands over each change as it is made)
  - Location settings (when location is blocked)
  - Itinerary list
    - Itinerary detail
      - Itinerary map (a leg, or the whole trip)
        - Stop departures sheet → Connection info
      - Connection info (a ride)
        - Itinerary map → …
      - Stop departures sheet → Connection info
      - Itinerary list, graph from a ride → Itinerary detail → … (no end, on
        purpose: every level may be the one the rider wants back to)
      - Itinerary list, find alternatives — *clears down to Routing first, so
        back lands where the search can be changed*
      - Share sheet
  - Itinerary detail (a recent trip) — as above
  - Vehicle on the map → Stop departures sheet → Connection info
  - Stop card → Timetable — *switches to the Timetables tab with the stop
    picked; back clears the stop, then returns to Routing*
- **Timetables** (tab; back: clears a picked stop, then to Routing)
  - Connection info
    - Itinerary map
- **Saved trips** (tab; back: to Routing)
  - Itinerary detail — as under Itinerary list
- **Settings** (tab; back: to Routing)
  - Location
  - Appearance
  - Search options
    - Quick access → Name & icon dialog → Icon picker
  - Advanced
    - Request log
      - Request detail
  - Calendar
  - About
  - Legal
  - Developer info

## From outside the app

- **A shared trip link** opens a loading screen, which replaces itself with
  Itinerary detail: back skips the loading screen.
- **A geo: link** clears down to Routing and opens Itinerary list over it,
  like find alternatives.
