import 'package:country_trivia/core/constants/app_constants.dart';
import 'package:country_trivia/core/utils/url_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlBuilder.flagUrl', () {
    test('lowercases an uppercase ISO2 code', () {
      // The reason this file exists. The API returns 'US'; flagcdn 404s on
      // 'US' and only serves 'us'.
      expect(UrlBuilder.flagUrl('US'), 'https://flagcdn.com/w320/us.png');
    });

    test('lowercases every code the CountriesNow API can return', () {
      for (final iso2 in <String>['US', 'GB', 'DE', 'AF', 'ZW', 'BQ']) {
        final url = Uri.parse(UrlBuilder.flagUrl(iso2));
        expect(
          url.pathSegments.last,
          '${iso2.toLowerCase()}.png',
          reason: '$iso2 must be lowercased in the path',
        );
      }
    });

    test('leaves an already lowercase code unchanged', () {
      expect(UrlBuilder.flagUrl('us'), 'https://flagcdn.com/w320/us.png');
    });

    test('defaults to width 320', () {
      expect(UrlBuilder.flagUrl('US'), contains('/w320/'));
    });

    test('honours an explicit width', () {
      expect(
        UrlBuilder.flagUrl('US', width: 80),
        'https://flagcdn.com/w80/us.png',
      );
      expect(
        UrlBuilder.flagUrl('US', width: 640),
        'https://flagcdn.com/w640/us.png',
      );
    });

    test('uses https so cleartext policy does not block it', () {
      expect(UrlBuilder.flagUrl('US'), startsWith('https://'));
      expect(UrlBuilder.flagUrl('US'), isNot(contains('http://')));
    });

    test('builds from the shared base url constant', () {
      expect(UrlBuilder.flagUrl('US'), startsWith('$kFlagCdnBaseUrl/'));
      expect(kFlagCdnBaseUrl, 'https://flagcdn.com');
    });
  });

  group('UrlBuilder.isValidIso2', () {
    test('accepts two letters in either case', () {
      expect(UrlBuilder.isValidIso2('US'), isTrue);
      expect(UrlBuilder.isValidIso2('us'), isTrue);
    });

    test('rejects anything that is not exactly two letters', () {
      for (final bad in <String>['', 'U', 'USA', 'U1', '1S', '  ', 'u s']) {
        expect(
          UrlBuilder.isValidIso2(bad),
          isFalse,
          reason: '"$bad" is invalid',
        );
      }
    });
  });
}
