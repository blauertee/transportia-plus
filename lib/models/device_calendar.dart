/// `CalendarContract.ACCOUNT_TYPE_LOCAL`: a calendar no account syncs.
const String kLocalCalendarAccountType = 'LOCAL';

/// Names for the account types riders are likely to have, so a calendar can
/// say where it syncs to. Anything else falls back to the account name alone.
const Map<String, String> _kAccountTypeLabels = {
  'bitfire.at.davdroid': 'DAVx5',
  'com.google': 'Google',
  'com.android.exchange': 'Exchange',
  'com.google.android.gm.exchange': 'Exchange',
  'org.dmfs.caldav.account': 'CalDAV-Sync',
  'at.bitfire.icsdroid': 'ICSx5',
  'com.samsung.android.calendar': 'Samsung',
};

/// One calendar on the device the app may write events into.
class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.name,
    required this.accountName,
    required this.accountType,
    required this.color,
    this.isOwn = false,
  });

  /// `Calendars._ID`.
  final int id;

  /// `Calendars.CALENDAR_DISPLAY_NAME`.
  final String name;

  /// `Calendars.ACCOUNT_NAME`.
  final String accountName;

  /// `Calendars.ACCOUNT_TYPE`.
  final String accountType;

  /// `Calendars.CALENDAR_COLOR`, as ARGB.
  final int color;

  /// Whether Transportia+ created this calendar for itself.
  final bool isOwn;

  /// This calendar, known to be the one the app made for itself.
  DeviceCalendar get asOwn => DeviceCalendar(
    id: id,
    name: name,
    accountName: accountName,
    accountType: accountType,
    color: color,
    isOwn: true,
  );

  /// Kept on the phone only: nothing uploads it anywhere.
  bool get isLocal => accountType == kLocalCalendarAccountType;

  /// The app that syncs this calendar, or null when the type is unknown or
  /// nothing syncs it.
  String? get syncedBy => _kAccountTypeLabels[accountType];

  /// Where this calendar lives, for the line under its name.
  String get whereabouts {
    if (isLocal) return 'On this phone only';
    final syncedBy = this.syncedBy;
    if (syncedBy == null) return accountName;
    return '$accountName · $syncedBy';
  }
}
