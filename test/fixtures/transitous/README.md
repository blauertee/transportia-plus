# Transitous API fixtures

Real responses captured from `api.transitous.org` (MOTIS `v2.11.1`) on
2026-08-08. They exist so model parsing is tested against what the server
actually sends — exponential numbers, absent optional fields and all — rather
than against hand-written JSON that agrees with our assumptions.

| file | request |
|---|---|
| `plan.json` | `/api/v6/plan` Berlin→Hamburg, `withFares`, `detailedTransfers`, `detailedLegs`, `numLegAlternatives=2` |
| `trip.json` | `/api/v6/trip` for a trip taken from `plan.json` |
| `stoptimes.json` | `/api/v6/stoptimes` at Alexanderplatz, `withAlerts`, `fetchStops` |
| `stop.json` | `/api/v6/stop` for Alexanderplatz |
| `geocode.json` | `/api/v1/geocode?text=Alexanderplatz` |
| `reverse_geocode.json` | `/api/v1/reverse-geocode` near Alexanderplatz |
| `geocode_rewe.json` | `/api/v1/geocode?text=Rewe&place=52.52,13.405&placeBias=1.5&numResults=20` (2026-09-28) |
| `geocode_springfield.json` | `/api/v1/geocode?text=Springfield&place=52.52,13.405&placeBias=1.5&numResults=20` (2026-09-28) |
| `geocode_paris.json` | `/api/v1/geocode?text=Paris&place=52.52,13.405&placeBias=1.5&numResults=20` (2026-09-28) |
| `map_initial.json` | `/api/v1/map/initial` — carries `serverConfig` |
| `map_stops.json` | `/api/v1/map/stops` over central Berlin |
| `map_routes.json` | `/api/experimental/map/routes` over central Berlin |
| `one_to_all.json` | `/api/v6/one-to-all` from Alexanderplatz, 15 min |
| `one_to_many.json` | `/api/v1/one-to-many`, walking, `withDistance` |
| `one_to_many_intermodal.json` | `/api/experimental/one-to-many-intermodal` |
| `rentals.json` | `/api/v1/rentals` over central Berlin, all sub-resources |
| `rentals_groups.json` | `/api/v1/rentals?withProviders=false` — every provider group, nothing else (2026-09-29) |
| `health.json` | `/api/v1/health` |
| `debug_transfers.json` | `/api/debug/transfers` for Alexanderplatz |
| `refresh_itinerary_bike.json` | `/api/v6/refresh-itinerary` for the #35 journey (bike → S3 → bike, Berlin), `preTransitModes=BIKE&postTransitModes=BIKE`, `maxPre/PostTransitTime=3600`, full geometry (2026-10-04, `v2.11.3`) |
| `plan_itinerary_rental.json` | one itinerary from `/api/v6/plan` Kottbusser Tor area → Alexanderplatz, `preTransitModes=RENTAL&preTransitRentalFormFactors=SCOOTER_STANDING`: walk, Dott scooter, walk, U5, walk (2026-10-04, `v2.11.3`) |
| `refresh_itinerary_bike_placeholders.json` | the same refresh as `refresh_itinerary_bike.json` with no limits sent (server default 900 s): both bike legs come back as cancelled placeholders with a `no offset found` alert |
| `refresh_itinerary_rental.json` | `/api/v6/refresh-itinerary` for `plan_itinerary_rental.json`, `preTransitRentalFormFactors=SCOOTER_STANDING&preTransitRentalProviders=de-DottBerlin`, `maxPre/PostTransitTime=1500`, `detailedTransfers=false` |
| `refresh_itinerary_rental_swapped.json` | the same without the rental filters: the server picks a Call a Bike bicycle elsewhere |
| `refresh_itinerary_rental_none.json` | the same with the filters and `maxPre/PostTransitTime=60`: a single cancelled `RENTAL` placeholder for the first mile, and the last walk as a placeholder too |

## Trimming

Four files were shortened after capture, because the endpoints return far
more than a parser test needs: `map_routes.json` keeps 1 route, 3 polylines
and 5 stops; `one_to_all.json` keeps 30 reachable places; `map_stops.json`
keeps 20 stops; `debug_transfers.json` keeps 5 equivalences and 15
transfers. Nothing else was edited, and no field was removed — array
lengths are the only thing that differs from the wire.

Because of that, do not assert cross-references in `map_routes.json`: its
route no longer indexes the polylines and stops that remain.

## Coordinate formats

The captures record a real inconsistency worth remembering. `/one-to-many`
and `/one-to-many-intermodal` take `lat;lon` and reject `lat,lon`; every other
endpoint takes `lat,lon`. `/rentals` accepts `lat;lon` without complaint and
answers with providers from the wrong region, so getting it backwards there
produces bad data instead of an error.

## Refreshing

Re-capture with the requests above when the API changes. Keep them compact
(`json.dump(..., separators=(',', ':'))`) — they are parser inputs, not
documents meant to be read as diffs.
