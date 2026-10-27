import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The smallest text the app shows, in logical pixels at the default text
/// scale. Below this, line numbers and times on the journey graph were
/// unreadable on a phone.
const double kMinFontSize = 10;

/// Every piece of text on screen drawn smaller than [min], as
/// `size px: "text"`: plain text and text fields, with each span's own size
/// or the one it inherits, at the text scale it is drawn with. Icons are
/// text too, drawn from an icon font; they are left out.
///
/// Text a [CustomPainter] paints itself is not in the render tree and is not
/// seen here.
List<String> textSmallerThan(WidgetTester tester, {double min = kMinFontSize}) {
  final small = <String>[];
  void check(InlineSpan span, TextScaler scaler, double inherited) {
    final size = span.style?.fontSize ?? inherited;
    if (span is! TextSpan) return;
    final text = span.text;
    final drawn = scaler.scale(size);
    if (text != null && _isWords(text) && drawn < min) {
      small.add('${drawn.toStringAsFixed(1)} px: "$text"');
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      check(child, scaler, size);
    }
  }

  for (final object in tester.allRenderObjects) {
    // 14 is what a style without a size falls back to.
    if (object is RenderParagraph) {
      check(object.text, object.textScaler, 14);
    } else if (object is RenderEditable && object.text != null) {
      check(object.text!, object.textScaler, 14);
    }
  }
  return small;
}

/// Whether [text] has something to read: not blank, and not an icon, which
/// is a glyph from the private use area of an icon font.
bool _isWords(String text) => text.runes.any(
  (rune) =>
      String.fromCharCode(rune).trim().isNotEmpty &&
      !(rune >= 0xE000 && rune <= 0xF8FF) &&
      rune < 0xF0000,
);

/// Fails with every piece of text on screen smaller than [kMinFontSize].
void expectReadableText(WidgetTester tester) {
  expect(
    textSmallerThan(tester),
    isEmpty,
    reason: 'Text smaller than $kMinFontSize px is too small to read.',
  );
}
