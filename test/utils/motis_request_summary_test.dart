import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/api/transitous_endpoint.dart';
import 'package:transportia/utils/motis_request_summary.dart';

Uri _uri(Map<String, String> q) => Uri.https('example.org', '/x', q);

void main() {
  test('a plan reads as from → to, with its time', () {
    expect(
      motisRequestSummary(
        TransitousEndpoint.plan,
        _uri({'fromPlace': 'a', 'toPlace': 'b', 'time': 't', 'other': 'x'}),
      ),
      'a → b · t',
    );
  });

  test('a later page of a plan says so', () {
    expect(
      motisRequestSummary(
        TransitousEndpoint.plan,
        _uri({'fromPlace': 'a', 'toPlace': 'b', 'pageCursor': 'c'}),
      ),
      'a → b · next page',
    );
  });

  test('stop times name the stop, or the centre without one', () {
    expect(
      motisRequestSummary(
        TransitousEndpoint.stopTimes,
        _uri({'stopId': 's', 'time': 't'}),
      ),
      's · t',
    );
    expect(
      motisRequestSummary(
        TransitousEndpoint.stopTimes,
        _uri({'center': '1,2'}),
      ),
      '1,2',
    );
  });

  test('a geocode quotes what was typed', () {
    expect(
      motisRequestSummary(TransitousEndpoint.geocode, _uri({'text': 'Hbf'})),
      '"Hbf"',
    );
  });

  test('other endpoints show their first two parameters', () {
    expect(
      motisRequestSummary(
        TransitousEndpoint.oneToAll,
        _uri({'one': '1', 'two': '2', 'three': '3'}),
      ),
      'one=1 · two=2',
    );
  });

  test('nothing to say is an empty line', () {
    expect(motisRequestSummary(TransitousEndpoint.health, _uri({})), '');
  });
}
