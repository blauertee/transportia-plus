# Store screenshots

Renders the seven phone screenshots in
`fastlane/metadata/android/en-US/images/phoneScreenshots/`: a question as the
heading, and below it the app widget that answers it, on the brand colour.

```sh
linux/drafting/store/render_store.sh            # renders into build/store
linux/drafting/store/render_store.sh --install  # and copies into fastlane
```

Needs Flutter (see `../README.md`), Python 3, and Node with Playwright and a
Chromium it can launch. The map backgrounds load the map style, tiles and
MapLibre GL JS from the network; nothing else does.

## The scenario

Little Snoring (a village in Norfolk) to Prague, leaving by bike for the
first bus. The image to scenario mapping lives in `store_draft_test.dart`:

| image | widget | data |
|---|---|---|
| 1 | the search card as a page (map turned off), "To the station" open | bike, 30 min |
| 2 | search results | `plan.json`: a train-only trip first, a coach from Brussels second |
| 3 | search results as a graph, locked up to London Kings Cross | itinerary 0 with its Great Northern 30 min late, so the Eurostar is missed; `plan_onward.json` is the search on from Kings Cross |
| 4 | trip timeline | itinerary 0, the train-only trip |
| 5 | journey map, transfer | itinerary 4, leg 12: Bercy Métro to the Paris coach stop |
| 6 | journey map, bike leg | itinerary 0, leg 0 |
| 7 | place search for "Decathlon" | `geocode_decathlon.json`, biased to central Prague |

## Data

Real responses from `api.transitous.org`, captured 2026-10-11:

- `data/plan.json`: `/api/v6/plan?fromPlace=52.8700,0.9180&toPlace=50.0833,14.4231&time=2026-10-21T08:00:00Z&preTransitModes=BIKE&maxPreTransitTime=1800&numItineraries=5&useRoutedTransfers=true&detailedTransfers=true&detailedLegs=true`
- `data/geocode_decathlon.json`: `/api/v1/geocode?text=Decathlon&place=50.0833,14.4231&placeBias=1.5&numResults=20&language=en`

Captured 2026-10-27, for the day a week after the main capture's trip,
since a search on a past day finds no Eurostar:

- `data/plan_onward.json`: `/api/v6/plan?fromPlace=gb-great-britain_9100KNGX9&toPlace=50.0833,14.4231&time=2026-10-28T15:05:00Z&numItineraries=5&useRoutedTransfers=true&detailedTransfers=true&detailedLegs=true`

The draft serves them to the app through a `MockClient`, so the screens run
their own requests and parsing. Re-capturing changes which itinerary is
which: check the indices in `store_draft_test.dart` and the `maps` list in
`render_store.sh` afterwards.

## The credit

Every image says "Powered by Transitous and OpenStreetMap": the trips come
from Transitous and the maps and places from OpenStreetMap.
`transitous_logo.png` is https://transitous.org/images/logo-text.svg
rasterised to 482×100 px with Chromium.

## Things that are faked

- **The missed Eurostar.** Image 7 makes the Great Northern into Kings
  Cross 30 minutes late. The search on from there is a week later, and
  after the clocks went back, so `render_store.sh` moves it back a week and
  an hour first: the same wall clock times on the day of the main capture.

- **The clock.** Widgets read `DateTime.now()`. `render_store.sh` moves every
  time in the capture so the first trip leaves 21 minutes after the render,
  and runs the test in a made-up time zone whose wall clock shows the times
  a rider in London would see.
- **The map.** MapLibre is a platform view and draws nothing in a test.
  `map/` renders the app's own style (`assets/styles/default.json`) in
  headless Chromium with the legs drawn as `ItineraryMapScreen` draws them,
  and the draft puts that image where the map would be. Stop icons are
  approximated by rings.
