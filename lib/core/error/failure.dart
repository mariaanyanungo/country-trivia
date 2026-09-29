/// The sealed failure hierarchy raised by the data layer.
///
/// [Failure] is `sealed`, so `switch` statements over it are checked by the
/// compiler: adding a case forces every consumer to handle the new variant
/// instead of silently falling through to a default branch.
library;

/// A recoverable problem the UI is expected to present to the player.
sealed class Failure {
  const Failure(this.message);

  /// A message safe to show in the UI. Must not leak URLs or stack traces.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The country list could not be fetched: non-200, empty body or timeout.
final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Could not reach the country service.',
  ]);
}

/// The response arrived but did not match the expected CountriesNow shape.
final class ParseFailure extends Failure {
  const ParseFailure([
    super.message = 'The country data was not in the expected format.',
  ]);
}

/// Persisted state could not be read or written. Never fatal to the run.
final class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Progress could not be saved.']);
}

/// The request succeeded but yielded no usable countries.
final class NoCountriesFailure extends Failure {
  const NoCountriesFailure([super.message = 'No countries were returned.']);
}
