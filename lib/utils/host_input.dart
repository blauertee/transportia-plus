/// A hostname, optionally with a port. Where the app sends a request, so
/// anything else (a path, credentials, spaces) makes it invalid rather than
/// being cleaned up.
final RegExp _kHostPattern = RegExp(
  r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:\d{1,5})?$',
);

/// The highest TCP port.
const int _kMaxPort = 65535;

/// The scheme every server is reached on. A pasted address may carry it.
const String _kHttpsPrefix = 'https://';
const String _kHttpPrefix = 'http://';

/// Whether [host] is a hostname, with an optional port in range, and
/// nothing else.
bool isValidHost(String host) {
  if (!_kHostPattern.hasMatch(host)) return false;
  final colon = host.indexOf(':');
  if (colon < 0) return true;
  final port = int.parse(host.substring(colon + 1));
  return port >= 1 && port <= _kMaxPort;
}

/// Whether [input] names a server on plain http, which the app cannot
/// reach: every request goes out over https.
bool isPlainHttpAddress(String input) =>
    input.trim().toLowerCase().startsWith(_kHttpPrefix);

/// [input] as a host to store, or null when it is not one.
///
/// Takes what a rider is likely to paste: an `https://` address, with a
/// trailing slash, in any case. Gives back the bare `host[:port]`, in lower
/// case. Anything more (a path, plain http, credentials) is not a host.
String? normalizeHost(String input) {
  var host = input.trim();
  if (host.toLowerCase().startsWith(_kHttpsPrefix)) {
    host = host.substring(_kHttpsPrefix.length);
  }
  if (host.endsWith('/')) host = host.substring(0, host.length - 1);
  host = host.toLowerCase();
  return isValidHost(host) ? host : null;
}
