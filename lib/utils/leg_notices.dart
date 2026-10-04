import '../models/itinerary.dart';
import 'changeover.dart';
import 'itinerary_leg_utils.dart';

/// Said on the change itself and, naming the station, at the head of the
/// journey, so the banner and the row it points at read as one statement.
const String kMissedChangeMessage = 'You will not make this change.';

const String kPlatformUnknownMessage =
    'Platform unknown: walking route and time may be off.';

/// How much a notice matters, most first. The order is the stacking order.
enum NoticeSeverity {
  /// The journey breaks here: something you planned on will not happen.
  problem,

  /// It still works, but not as planned, or the plan is a guess.
  caution,

  /// Worth knowing; changes nothing you have to do.
  info,
}

/// One thing to tell the rider about a leg, whatever kind of leg it is.
class LegNotice {
  const LegNotice(this.severity, this.title, {this.detail});

  final NoticeSeverity severity;
  final String title;

  /// The operator's longer text, where there is one.
  final String? detail;
}

/// Everything worth saying about [leg], most severe first.
///
/// A ride, a walk and a change all go through here: the notices come from
/// what the leg carries (cancellations, the operator's alerts on it and on
/// its stops) and from the change it belongs to, not from its mode.
List<LegNotice> legNotices(Leg leg, {Changeover? changeover}) {
  final missed = changeover?.isMissed ?? false;
  final notices = <LegNotice>[
    if (missed) const LegNotice(NoticeSeverity.problem, kMissedChangeMessage),
    if (leg.cancelled) LegNotice(NoticeSeverity.problem, _cancelledTitle(leg)),
    if (!leg.cancelled && leg.from.cancelled)
      LegNotice(
        NoticeSeverity.problem,
        'It no longer stops at ${leg.fromName}.',
      ),
    if (!leg.cancelled && leg.to.cancelled)
      LegNotice(NoticeSeverity.problem, 'It no longer stops at ${leg.toName}.'),
    if (!missed && (changeover?.platformUnknown ?? false))
      const LegNotice(NoticeSeverity.caution, kPlatformUnknownMessage),
    if (_skippedStops(leg) case final skipped when skipped > 0)
      LegNotice(
        NoticeSeverity.caution,
        skipped == 1
            ? 'One stop on the way is skipped.'
            : '$skipped stops on the way are skipped.',
      ),
    ..._alertNotices(leg),
  ];
  // Stable, so notices of one severity keep the order they were found in.
  final indexed = notices.indexed.toList()
    ..sort((a, b) {
      final bySeverity = a.$2.severity.index.compareTo(b.$2.severity.index);
      return bySeverity != 0 ? bySeverity : a.$1.compareTo(b.$1);
    });
  return [for (final (_, notice) in indexed) notice];
}

/// Every notice the itinerary shows, leg by leg: the legs as it lays them
/// out, each change with its changeover. Counting these gives the number of
/// blocks the rider will actually see, which is what a summary should say.
List<LegNotice> journeyNotices(List<Leg> legs) {
  final displayLegs = buildDisplayLegs(legs);
  final changeovers = changeoversOf(displayLegs);
  return [
    for (final entry in displayLegs)
      ...legNotices(
        entry.leg,
        changeover: entry.isTransfer
            ? changeovers.where((c) => identical(c.transfer, entry.leg)).first
            : null,
      ),
  ];
}

int _skippedStops(Leg leg) {
  if (leg.cancelled) return 0;
  return leg.intermediateStops.where((stop) => stop.cancelled).length;
}

/// What a cancelled leg means for the rider, which depends on what the leg
/// is: a service that will not run, a shared vehicle that is no longer there,
/// or a way on foot the street network no longer has.
String _cancelledTitle(Leg leg) {
  if (!leg.isStreet) return 'This service is cancelled.';
  if (leg.mode == TransitMode.rental.wireName) {
    return 'No shared vehicle is within reach any more.';
  }
  return 'There is no way through here any more.';
}

/// The operator's alerts on the leg and on every stop it calls at, each once.
///
/// A cancelled street leg is the stand-in a refresh sends for a stretch it
/// could not route again, and its only alert is the server's own error text
/// ("no offset found"), not anything an operator said.
Iterable<LegNotice> _alertNotices(Leg leg) {
  final seen = <String>{};
  final all = [
    if (!(leg.isStreet && leg.cancelled)) ...leg.alerts,
    ...leg.from.alerts,
    for (final stop in leg.intermediateStops) ...stop.alerts,
    ...leg.to.alerts,
  ];
  return [
    for (final alert in all)
      if (alert.hasText && seen.add(_key(alert)))
        LegNotice(severityOf(alert), _titleOf(alert), detail: _detailOf(alert)),
  ];
}

String _key(Alert alert) =>
    '${alert.headerText ?? ''}\u0000${alert.descriptionText ?? ''}';

String _titleOf(Alert alert) {
  final header = alert.headerText?.trim();
  if (header != null && header.isNotEmpty) return header;
  return alert.descriptionText!.trim();
}

String? _detailOf(Alert alert) {
  final header = alert.headerText?.trim();
  if (header == null || header.isEmpty) return null;
  final body = alert.descriptionText?.trim();
  return (body == null || body.isEmpty || body == header) ? null : body;
}

/// The feed's own severity where it gives one; most feeds do not, so the
/// effect decides otherwise.
NoticeSeverity severityOf(Alert alert) {
  switch (alert.severityLevel) {
    case AlertSeverityLevel.severe:
      return NoticeSeverity.problem;
    case AlertSeverityLevel.warning:
      return NoticeSeverity.caution;
    case AlertSeverityLevel.info:
      return NoticeSeverity.info;
    case AlertSeverityLevel.unknownSeverity || null:
      break;
  }
  return switch (alert.effect) {
    AlertEffect.noService => NoticeSeverity.problem,
    AlertEffect.additionalService ||
    AlertEffect.noEffect => NoticeSeverity.info,
    _ => NoticeSeverity.caution,
  };
}
