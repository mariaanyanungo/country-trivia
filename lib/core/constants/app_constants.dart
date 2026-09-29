/// Application-wide constants: API endpoints, scoring rules and storage keys.
///
/// Everything here is verified against the live APIs in
/// `docs/master_plan.md` §1. Values are frozen once T03–T05 land; changing one
/// is a contract change with ripple risk across the data and domain layers.
library;

/// Base URL of the CountriesNow REST API (master plan §1.1).
const String kCountriesApiBaseUrl = 'https://countriesnow.space/api/v0.1';

/// Endpoint returning the 222 country/territory records with `Iso2`/`Iso3`.
const String kCountriesIsoEndpoint = '/countries/iso';

/// Base URL of the flag image CDN (master plan §1.2).
const String kFlagCdnBaseUrl = 'https://flagcdn.com';

/// Timeout for the CountriesNow request.
const Duration kNetworkTimeout = Duration(seconds: 15);

/// Number of name options offered per question, including the correct answer.
const int kOptionsPerQuestion = 4;

/// Attempts allowed per question before the answer is revealed.
const int kMaxAttempts = 3;

/// Points awarded for a correct answer, indexed by attempt.
///
/// `pointsForAttempt[0]` is the first attempt (10), `[1]` the second (8) and
/// `[2]` the third (5). Wrong answers award nothing and never subtract, so the
/// score is never negative. Attempt 4 does not exist: the question is decided
/// after the third.
const List<int> kPointsForAttempt = <int>[10, 8, 5];

/// Points awarded when all [kMaxAttempts] are wrong and the answer is revealed.
const int kPointsForFailure = 0;

/// Flag image width for the quiz question.
const int kFlagWidthLarge = 320;

/// Flag image width for the small progress thumbnail.
const int kFlagWidthSmall = 80;

/// Persisted key: the current run's score (`int`).
const String kStorageKeyScore = 'ct.score';

/// Persisted key: ISO2 codes solved this run (`List<String>`).
const String kStorageKeySolved = 'ct.solved';

/// Persisted key: all-time best score (`int`).
const String kStorageKeyBestScore = 'ct.bestScore';

/// Persisted key: country count at run start, used to detect API growth.
const String kStorageKeyPoolSize = 'ct.poolSize';

/// Persisted key: forward-compatibility guard for future migrations.
const String kStorageKeySchemaVersion = 'ct.schemaVersion';

/// Storage keys handed to `SharedPreferencesWithCache`'s `allowList`.
///
/// Only these five keys are read, so a corrupt or unexpected value elsewhere
/// in the store can never crash the load at bootstrap.
const List<String> kPreferencesAllowList = <String>[
  kStorageKeyScore,
  kStorageKeySolved,
  kStorageKeyBestScore,
  kStorageKeyPoolSize,
  kStorageKeySchemaVersion,
];

/// Current persisted-shape version. Bump when [kStorageKeySchemaVersion]
/// handling changes in a way that older installs cannot satisfy.
const int kSchemaVersion = 1;
