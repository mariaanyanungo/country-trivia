import '../constants/app_constants.dart';

/// Builds flag image URLs for flagcdn.
///
/// flagcdn serves only **lowercase** ISO2 codes: `w320/us.png` returns 200
/// while `w320/US.png` returns 404. The CountriesNow API returns them
/// uppercase, so the lowercasing is done here and nowhere else. This is the
/// single place that conversion can happen — every other layer must call
/// [flagUrl] rather than interpolating a code into a URL itself.
///
/// See `docs/master_plan.md` §1.2 and §9 risk #2.
abstract final class UrlBuilder {
  /// Matches a well-formed uppercase or lowercase ISO 3166-1 alpha-2 code.
  static final RegExp _iso2Pattern = RegExp(r'^[a-zA-Z]{2}$');

  /// The set of widths flagcdn actually serves.
  ///
  /// Anything else 404s, so an unsupported width is a programming error worth
  /// catching while developing rather than a broken image in production.
  static const Set<int> supportedWidths = <int>{
    20,
    40,
    80,
    160,
    320,
    640,
    1280,
    2560,
  };

  /// Returns the flag image URL for [iso2], e.g. `flagUrl('US')` yields
  /// `https://flagcdn.com/w320/us.png`.
  ///
  /// The [iso2] code is lowercased before interpolation, which is required for
  /// the image to resolve. The function is total: a malformed code produces a
  /// URL that will 404 rather than throwing, because a bad code should degrade
  /// to a broken flag image, not crash a run in progress. Debug builds assert
  /// instead, so the mistake is caught before it ships.
  static String flagUrl(String iso2, {int width = kFlagWidthLarge}) {
    assert(
      supportedWidths.contains(width),
      'flagcdn does not serve width $width; use one of $supportedWidths',
    );
    assert(
      _iso2Pattern.hasMatch(iso2),
      '"$iso2" is not a well-formed ISO2 code; expected two letters',
    );

    return '$kFlagCdnBaseUrl/w$width/${iso2.toLowerCase()}.png';
  }

  /// Whether [iso2] is a well-formed two-letter country code.
  ///
  /// The data layer uses this to reject malformed records while parsing, so a
  /// bad code never reaches [flagUrl] in the first place.
  static bool isValidIso2(String iso2) => _iso2Pattern.hasMatch(iso2);
}
