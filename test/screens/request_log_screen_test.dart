import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/motis_request_log.dart';
import 'package:transportia/api/transitous_endpoint.dart';
import 'package:transportia/models/motis_request_record.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/request_log_screen.dart';

MotisRequestRecord _record(
  TransitousEndpoint endpoint,
  Map<String, String> query, {
  int status = 200,
  String? error,
}) => MotisRequestRecord(
  endpoint: endpoint,
  method: 'GET',
  uri: Uri.https('api.transitous.org', '/api/v5/${endpoint.path}', query),
  sentAt: DateTime(2026, 11, 8, 12),
  duration: const Duration(milliseconds: 200),
  statusCode: status,
  error: error,
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: const CupertinoApp(home: RequestLogScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    MotisRequestLog.records.value = [
      _record(TransitousEndpoint.stopTimes, {'stopId': 'stop-1'}),
      _record(TransitousEndpoint.plan, {'fromPlace': 'a', 'toPlace': 'b'}),
      _record(
        TransitousEndpoint.plan,
        {'fromPlace': 'a', 'toPlace': 'nowhere'},
        status: 400,
        error: 'unknown stop',
      ),
    ];
  });
  tearDown(MotisRequestLog.clear);

  testWidgets('lists every request, and one endpoint when filtered', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('stop-1'), findsOneWidget);
    expect(find.text('a → b'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);

    await tester.tap(find.text('Plan  2'));
    await tester.pump();

    expect(find.text('stop-1'), findsNothing);
    expect(find.text('a → b'), findsOneWidget);
    expect(find.text('a → nowhere'), findsOneWidget);
  });

  testWidgets('clearing empties the log', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(MotisRequestLog.records.value, isEmpty);
    expect(find.text('No requests logged'), findsOneWidget);
  });

  testWidgets('a request opens, and copies as sent', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);

    await tester.tap(find.text('a → nowhere'));
    await tester.pumpAndSettle();
    expect(find.text('unknown stop'), findsOneWidget);

    await tester.tap(find.text('Copy request'));
    await tester.pump();

    expect(
      copied,
      'GET https://api.transitous.org/api/v5/plan?fromPlace=a&toPlace=nowhere',
    );
    await tester.pump(const Duration(seconds: 2));
  });
}
