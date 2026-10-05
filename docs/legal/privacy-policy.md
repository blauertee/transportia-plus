# Transportia+ Privacy Policy

_Last updated: 5 October 2026_

Transportia+ is a free, open-source app maintained by blauertee
([github.com/blauertee](https://github.com/blauertee)). It is a fork of
[Transportia](https://github.com/Wafler1/transportia) by Wafler.one, and is
maintained separately from it. This policy covers Transportia+ only, in every
version that links to it.

## The short version

Transportia+ has no accounts, no analytics, no advertising and no server of
its own. The maintainer receives no data from the app. Everything you save
stays on your device. To show maps, routes and timetables, the app talks
directly to the third-party services listed below.

## What stays on your device

Your saved places and favourites, saved trips, recent searches, settings and
the choice of routing server are stored only in the app's local storage on
your device. They are never uploaded. Uninstalling the app, or clearing its
storage, deletes them.

## Your location

If you allow location access, the app uses your position on the device to
show where you are on the map and to plan trips from "My Location". When you
search for a route from or to your location, its coordinates are sent to the
routing server as part of that request, in the same way as any other start or
end point. Your location is not sent anywhere else, and it is not recorded by
the app. You can withdraw the permission at any time in your device settings;
the app keeps working without it.

## Third-party services the app contacts

Every request to these services reveals your IP address and the app's
identity (`Transportia+/<version>`) to them, along with the contents of the
request. Each service handles that data under its own privacy policy.

- **Routing server (MOTIS).** By default [Transitous](https://transitous.org)
  (`api.transitous.org`). It receives your searches, start and end points,
  travel times and routing options, and the map area you are looking at, so it
  can return routes, departures, stops and vehicles. You can choose a
  different MOTIS server in the settings; requests then go there instead.
- **Map tiles.** [OpenFreeMap](https://openfreemap.org)
  (`tiles.openfreemap.org`) receives requests for the map area being shown.
- **Place details.** When you tap a search result on the map, the app asks
  OpenStreetMap's [Nominatim](https://nominatim.openstreetmap.org) which place
  it is, to show its address, opening hours and contact details. Only the
  place you tapped is sent, never your location. You can turn this off under
  Settings → Location.
- **Shared trips.** A trip you share is a link to `blauertee.github.io`,
  hosted on GitHub Pages. If someone opens it in a browser instead of the app,
  GitHub receives that request.
- **Links you open.** Links to websites, email or other apps open outside
  Transportia+ and are governed by those services.

## What the maintainer does not do

The maintainer does not collect, store, sell or share any personal data, and
does not use the data described above for any purpose, because it never
reaches them.

## Children

Transportia+ is not directed at children under 13, and, as it collects no
personal data from anyone, collects none from children either.

## Changes to this policy

Changes are published in this file in the app's public repository, where its
full history can be read. The date at the top shows the latest revision.

## Questions

Open an issue on the
[issue tracker](https://github.com/blauertee/transportia-plus/issues), or use
the contact details shown under About Transportia+ in the app.
