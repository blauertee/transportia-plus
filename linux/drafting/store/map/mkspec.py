"""Turns one itinerary of a /plan capture into what map.html draws.

    python3 mkspec.py PLAN.json ITINERARY FOCUS_LEGS OUT.json

FOCUS_LEGS is a comma-separated list of leg indices the camera fits.
Colours follow ItineraryMapScreen: grey walks, the route colour, else accent.
"""
import json
import sys

ACCENT = '#007185'
WALK = '#9E9E9E'


def decode(points, precision):
    factor = 10 ** precision
    i = lat = lon = 0
    out = []
    while i < len(points):
        for k in (0, 1):
            result = shift = 0
            while True:
                b = ord(points[i]) - 63
                i += 1
                result |= (b & 31) << shift
                shift += 5
                if b < 32:
                    break
            value = ~(result >> 1) if result & 1 else result >> 1
            if k == 0:
                lat += value
            else:
                lon += value
        out.append([lon / factor, lat / factor])
    return out


def main(plan, index, focus, out):
    itinerary = json.load(open(plan))['itineraries'][index]
    legs, stops = [], []
    for leg in itinerary['legs']:
        geometry = leg.get('legGeometry')
        coords = (
            decode(geometry['points'], geometry.get('precision', 6))
            if geometry
            else [[leg['from']['lon'], leg['from']['lat']],
                  [leg['to']['lon'], leg['to']['lat']]]
        )
        walk = leg['mode'] == 'WALK'
        colour = WALK if walk else (
            '#' + leg['routeColor'] if leg.get('routeColor') else ACCENT)
        legs.append({'coords': coords, 'color': colour,
                     'width': 3.0 if walk else 3.4})
        for end in (leg['from'], leg['to']):
            stops.append({'lon': end['lon'], 'lat': end['lat'], 'color': colour})
    points = [p for i in focus for p in legs[i]['coords']]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    json.dump({'legs': legs, 'stops': stops,
               'bounds': [[min(xs), min(ys)], [max(xs), max(ys)]]},
              open(out, 'w'))


if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]),
         [int(x) for x in sys.argv[3].split(',')], sys.argv[4])
