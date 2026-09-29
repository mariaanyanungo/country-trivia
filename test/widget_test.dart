// Placeholder to keep the `test/` directory and `flutter test` harness alive.
//
// The generated counter smoke test was removed in T01 because it asserted on the
// Flutter template demo (a `+` FAB and the text '0'), so it would have failed the
// moment `main.dart` was rewritten for the trivia app — a failure that reads like
// a regression in the quiz view model but is really a stale template test.
//
// T08 replaces this file with the real suite: the flag URL builder (lowercase ISO2),
// the `Iso2` JSON key casing, scoring 10/8/5/0, double-tap protection, and the
// solved-country-never-repeats guarantee.
//
// Until then this asserts only that the harness itself runs, so `flutter test`
// exits 0 and CI stays green.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test harness runs', () {
    expect(1 + 1, 2);
  });
}
