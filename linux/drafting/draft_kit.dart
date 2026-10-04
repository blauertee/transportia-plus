// Renders app widgets to PNGs for design review, from a headless
// `flutter test`. See README.md beside this file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/widgets/floating_nav_bar.dart';

/// A phone in portrait, in logical pixels.
const Size kDraftPhone = Size(400, 860);

/// Where the PNGs go. `DRAFT_OUT` overrides it; `render.sh` points it at the
/// agent's scratch directory.
String get _outDir => Platform.environment['DRAFT_OUT'] ?? 'build/drafts';

/// Prefixed to every file name, so before and after renders sit side by side:
/// `DRAFT_TAG=before`, change the code, `DRAFT_TAG=after`.
String get _tag => Platform.environment['DRAFT_TAG'] ?? 'draft';

const Key _kShotKey = ValueKey('draft-shot');

/// The families the app's text resolves to with no `fontFamily` of its own.
///
/// `flutter test` draws text it has no font for as solid boxes, and the app
/// declares none: it uses the platform's. Roboto, the SDK's copy of the
/// Android font, stands in under every name the framework asks for.
const List<String> _kSystemFamilies = [
  'Roboto',
  'CupertinoSystemText',
  'CupertinoSystemDisplay',
  '.SF Pro Text',
  '.SF Pro Display',
  '.SF UI Text',
  '.SF UI Display',
];

const List<String> _kRobotoFiles = [
  'Roboto-Regular.ttf',
  'Roboto-Medium.ttf',
  'Roboto-Bold.ttf',
  'Roboto-Black.ttf',
];

/// Loads real fonts in place of the test font. Call once, from `setUpAll`.
///
/// Two sources: Roboto from the Flutter SDK for plain text, and every family
/// in the bundle's font manifest — each package's icon fonts included — so
/// an icon renders as itself rather than as a box.
Future<void> loadDraftFonts() async {
  final roboto = _materialFontsDir();
  for (final family in _kSystemFamilies) {
    final loader = FontLoader(family);
    for (final file in _kRobotoFiles) {
      loader.addFont(_fileBytes('${roboto.path}/$file'));
    }
    await loader.load();
  }

  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<ByteData> _fileBytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

/// The SDK's bundled Material fonts, found from `FLUTTER_ROOT` or, failing
/// that, from the test runner's own location inside the SDK.
Directory _materialFontsDir() {
  const relative = 'bin/cache/artifacts/material_fonts';
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) return Directory('$root/$relative');

  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    final candidate = Directory('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  throw StateError(
    'Cannot find the Flutter SDK fonts; set FLUTTER_ROOT to the SDK.',
  );
}

/// Empty storage, so every draft starts from a fresh install. Call from
/// `setUp`; seed data afterwards through the services, as a test would.
void resetDraftStorage() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

/// Pumps [screen] as the app would show it — theme, localizations, a
/// navigator to push from — at [size], then saves it as `<tag>_<name>.png`.
///
/// [screen] is built inside a route, so it can push, pop and read
/// `Navigator.of`. [settle] is how long to let async loads and animations
/// run first: long enough for a screen that reads storage on open.
Future<void> shootScreen(
  WidgetTester tester,
  String name,
  Widget screen, {
  Size size = kDraftPhone,
  Duration settle = const Duration(seconds: 1),
}) async {
  await pumpDraft(tester, screen, size: size);
  await tester.pump(settle);
  await saveDraft(tester, name);
}

/// Pumps [screen] the way [shootScreen] does, without saving: for drafts
/// that tap, scroll or type before the picture is taken.
Future<void> pumpDraft(
  WidgetTester tester,
  Widget screen, {
  Size size = kDraftPhone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _acceptPlatformViews(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _kShotKey,
      child: DraftApp(child: screen),
    ),
  );
}

/// Lets a screen with a map in it build: the map asks the platform for a
/// native view, which a test has no plugin to create.
///
/// The request is left pending rather than refused or granted. Refused, it
/// throws; granted, the map goes on to call its own plugin, which is not
/// there either. Pending, the map's area stays blank and the rest of the
/// screen draws around it.
void _acceptPlatformViews(WidgetTester tester) {
  const channel = SystemChannels.platform_views;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) => call.method == 'create'
        ? Completer<Object?>().future
        : Future<Object?>.value(),
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Saves what is on screen now as `<tag>_<name>.png`, at twice the logical
/// size so text stays sharp when viewed on a phone.
Future<File> saveDraft(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_kShotKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final file = File('$_outDir/${_tag}_$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!);
  return file;
}

/// The app's shell, minus everything that needs a device: the theme provider
/// every screen reads its colours from, the localizations the app installs,
/// and a navigator whose first route is [child].
class DraftApp extends StatelessWidget {
  const DraftApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        // As app.dart sets it, but naming the family the platform would
        // pick, which a test has no platform to pick for it.
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          color: Color(0xFF000000),
        ),
        // Cupertino widgets take the app's brightness, not the machine's,
        // as app.dart sets it; drafts are light.
        builder: (context, child) => CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.light),
          child: child ?? const SizedBox.shrink(),
        ),
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, _, _) => child,
        ),
      ),
    );
  }
}

/// A screen that normally sits over the map, drawn over a stand-in.
///
/// MapLibre is a platform view and renders nothing in a test, so anything
/// laid over the map needs something behind it to be judged against.
/// [sheetTop] is where the sheet starts; the nav bar is painted over the
/// bottom, as the real shell paints it over the tab.
class DraftOverMap extends StatelessWidget {
  const DraftOverMap({super.key, required this.sheet, this.sheetTop = 120});

  final Widget sheet;
  final double sheetTop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _MapStandIn())),
        Positioned(left: 0, right: 0, top: sheetTop, bottom: 0, child: sheet),
        const DraftNavBar(),
      ],
    );
  }
}

/// Where the floating nav bar sits, drawn as a plain pill: the real one
/// needs the shell's tab state, and a draft only needs to see what it hides.
class DraftNavBar extends StatelessWidget {
  const DraftNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 14,
      height: FloatingNavBar.reservedHeight - 20,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 12),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          'nav bar',
          style: TextStyle(color: Color(0x66000000), fontSize: 12),
        ),
      ),
    );
  }
}

/// Pale blocks and white streets: enough map to judge a sheet against.
class _MapStandIn extends CustomPainter {
  const _MapStandIn();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8ECE4),
    );
    final street = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 10;
    const streets = 8;
    for (var i = 0; i < streets; i++) {
      canvas.drawLine(
        Offset(0, 60.0 + i * 70),
        Offset(size.width, 20.0 + i * 90),
        street,
      );
      canvas.drawLine(
        Offset(40.0 + i * 60, 0),
        Offset(i * 50.0, size.height),
        street,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
