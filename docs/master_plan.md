# Country Trivia — Master Plan

Flutter app: show a country flag + 4 name options, score 10/8/5 for attempts 1/2/3,
0 points and reveal on failure. Tracks solved countries, persists progress and points
across restarts. MVVM + `provider`.

**Environment verified:** Flutter 3.47.1 (stable), Dart 3.13.1.

---

## 1. API Research (verified live, 2026-09-29)

### 1.1 Countries API

The Postman collection *"Countries & Cities API"*
(`https://documenter.getpostman.com/view/1134062/T1LJjU52`) is published by **CountriesNow**.

| Item | Value |
|---|---|
| Base URL | `https://countriesnow.space/api/v0.1` |
| Endpoint used | `GET /countries/iso` |
| Auth | None |
| Latency | ~0.87 s, 10.4 KB |
| Records | **222** countries/territories |

Response envelope (note: the success flag is the key `error`, which is `false` on success):

```json
{
  "error": false,
  "msg": "countries and ISO codes retrieved",
  "data": [
    { "name": "Afghanistan", "Iso2": "AF", "Iso3": "AFG" }
  ]
}
```

Verified properties:
- All 222 `name` values are unique — safe to use as a display key.
- All 222 `Iso2` codes are unique, well-formed, uppercase, 2 characters.
- **The JSON keys are `Iso2` / `Iso3` (capital `I`), not `iso2` / `iso3`.** Dart field
  mapping must use `@JsonKey(name: 'Iso2')`. This is the single easiest thing to get wrong.
- Error shape for an unknown path: `{"error":true,"msg":"you seem to be lost"}`.

Secondary endpoints available if ever needed: `/countries/flag/images` (Wikimedia SVG flag
URLs — *not* used, the app uses flagcdn), `/countries/capital`, `/countries/population`,
`/countries/currency`, `/countries/dialCode`, `/countries/iso2`, `/countries/iso3`.

**Relevance note:** the dataset includes 222 entries — 195 UN member states plus
dependencies and territories (e.g. `Bouvet Island`, `Réunion`, `Cocos (Keeling) Islands`).
The plan treats all of them as playable. See §9, risk #11, for the optional exclusion note.

### 1.2 Flags API

| Item | Value |
|---|---|
| URL template | `https://flagcdn.com/w320/{iso2}.png` |
| Auth | None |
| CORS | `access-control-allow-origin: *` (verified) |

**Critical finding — the ISO2 code must be lowercased.** Verified:

| URL | Status |
|---|---|
| `https://flagcdn.com/w320/us.png` | 200 |
| `https://flagcdn.com/w320/US.png` | **404** |
| `https://flagcdn.com/w320/zz.png` | 404 |

The API returns ISO2 codes uppercase; flagcdn only serves lowercase. The
`Country` model must expose a lowercase accessor for the flag URL. Missing this
yields a 404 for **every single flag** — the app will appear completely broken
with no compile error.

**Coverage — all 222 verified.** Every lowercase ISO2 code was fetched and decoded:

- 222/222 return HTTP 200 with a valid `image/png`.
- 0 codes are missing a flag.
- Two codes (`bv` Bouvet Island, `sj` Svalbard and Jan Mayen) return the *Norway* flag.
  This is intentional flagcdn behaviour for Norwegian dependencies, **not a bug** —
  pixel-identical to `no.png` (md5 `70ef6743…`, 323 bytes). Both are valid trivia questions.
- `um` (United States Minor Outlying Islands) likewise returns the US flag. Also correct.

A naive "is the image blank?" heuristic produces false positives: Austria, Poland,
Latvia, Switzerland and Monaco are genuinely 2–3 colour flags. No blank-detection
filter is needed or wanted in the app.

Available widths: `w20` `w40` `w80` `w160` `w320` `w640` `w1280` `w2560`. The app uses
`w320` for the question and `w80` for a small progress thumbnail.

### 1.3 URL scheme

Both hosts 301-redirect `http://` to `https://`. The app uses **HTTPS directly** —
plain `http://` is blocked by Android's cleartext policy in release builds and by
ATS on iOS.

---

## 2. Game Rules (as specified)

- One flag is shown with **4 country name** options — 1 correct, 3 distractors.
- The player has **3 attempts** per question.
- Award on a **correct** selection:

| Attempt | Points |
|---|---|
| 1st (correct on first try) | **10** |
| 2nd (one wrong, then correct) | **8** |
| 3rd (two wrong, then correct) | **5** |
| All 3 wrong | **0** — correct answer revealed |

- A question is marked **solved** once its 3 attempts are exhausted — the country is
  revealed and the country is recorded in the solved set.
- A solved country is **never shown again** during the current run.
- When every country is solved, the run is complete and the player is offered a **reset**,
  which clears points and the solved set and starts a fresh run.

### 2.1 Resolved ambiguities

These were underspecified; the following decisions are baked into the plan.

1. **"Solved" means exhausted, not merely answered.** A country counts as solved as soon
   as it leaves the board — whether the player got it right on attempt 1 or failed all 3.
   Otherwise a re-run could re-show countries the player already failed, and the
   "not display them again" rule would not hold.
2. **Attempt 1 requires an immediate commit.** The first tap is scored immediately:
   correct → +10, wrong → deduct nothing, advance to attempt 2. There is no undo.
3. **Wrong answers are not penalised.** Only the final award is granted, so points are
   `+10`, `+8` or `+5` — never negative and never double-counted. A wrong tap awards 0
   and does not modify the total.
4. **Attempt counter is per question and resets on advance.**
5. **Feedback is shown before advancing.** After the deciding tap, a 1.5 s pause (or a
   "Next" button) lets the player see the reveal/highlight, then the next question loads.
6. **Distractors never repeat a solved country or the correct answer**, and all four
   option names are unique within a question.
7. **Option order is shuffled** per question so the correct answer is not always in the
   same slot.
8. **A network failure does not consume the run.** If the country list cannot be loaded,
   the app shows a retry screen and the persisted state is left untouched.
9. **Points are lifetime, not per-run.** The user's score persists across restarts; only
   an explicit reset clears it. This matches "user points should be persisted across
   sessions and app restarts."
10. **Highest score is tracked too**, so a reset does not destroy the user's best result.

---

## 3. Architecture

### 3.1 Layering (strict, one-directional dependencies)

```
   View (Widgets)          ← knows ViewModel only. No http, no storage, no json.
        │  watches
        ▼
   ViewModel (Provider)    ← holds all state + logic. No BuildContext, no widgets.
        │  calls
        ▼
   Repository              ← single source of truth. Owns cache + orchestration.
        ├──▶ CountryRemoteDataSource   (http, DTO → domain mapping)
        └──▶ GameProgressStore         (SharedPreferences, persisted state)
```

**Dependency rule:** `data → domain ← presentation`. Nothing in `data/` imports
Flutter widgets; nothing in `presentation/` imports `dart:io`/`http`.

### 3.2 Directory layout

```
lib/
├── main.dart                          # bootstrap: WidgetsFlutterBinding, DI, runApp
├── app.dart                           # CountryTriviaApp + MaterialApp + theme
│
├── core/
│   ├── constants/
│   │   └── app_constants.dart         # base URLs, points, attempts, storage keys
│   ├── error/
│   │   ├── failure.dart               # sealed Failure hierarchy
│   │   └── exceptions.dart
│   └── utils/
│       └── url_builder.dart           # flagcdn URL builder (lowercasing lives here)
│
├── data/
│   ├── models/
│   │   ├── country_model.dart         # @JsonKey(name:'Iso2') DTO  → Country
│   │   └── game_state_model.dart      # persisted snapshot  → GameState
│   ├── datasources/
│   │   ├── country_remote_data_source.dart
│   │   └── game_progress_store.dart   # SharedPreferences impl
│   └── repositories/
│       └── country_repository_impl.dart
│
├── domain/
│   ├── entities/
│   │   ├── country.dart               # name, iso2, iso3, flagUrl
│   │   ├── quiz_question.dart         # country + 4 options + shuffle
│   │   ├── answer_result.dart         # outcome of a single tap
│   │   └── game_state.dart            # score, solvedIso2, bestScore, runComplete
│   └── repositories/
│       └── country_repository.dart    # abstract contract
│
├── presentation/
│   ├── viewmodels/
│   │   └── quiz_view_model.dart       # ChangeNotifier — the heart of the app
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── quiz_screen.dart
│   │   ├── game_over_screen.dart
│   │   └── widgets/
│   │       ├── flag_image_view.dart   # cached, loading + error states
│   │       ├── option_tile.dart       # one answer button
│   │       ├── score_header.dart      # score, streak, progress bar
│   │       ├── attempts_indicator.dart
│   │       ├── reveal_banner.dart
│   │       ├── error_view.dart
│   │       └── loading_view.dart
│   └── theme/
│       └── app_theme.dart
│
└── di/
    └── service_locator.dart           # manual composition root (no codegen)
```

**Why a manual `service_locator.dart` over `get_it`/build_runner:** the graph is ~6
objects. Hand-wiring it keeps `build_runner` and codegen out of the build, keeps
`flutter analyze` fast, and makes the wiring greppable. If the graph grows past ~10
nodes, swap in `get_it` — the interfaces already make that a one-file change.

### 3.3 State management: Provider + MVVM

```dart
// di/service_locator.dart
final repository = CountryRepositoryImpl(
  remote: CountryRemoteDataSource(client: http.Client()),
  store: GameProgressStore(await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: ['ct.score', 'ct.solved', 'ct.bestScore',
                  'ct.poolSize', 'ct.schemaVersion'],
    ),
  )),
);

runApp(
  ChangeNotifierProvider<QuizViewModel>(
    create: (_) => QuizViewModel(repository)..initialize(),
    child: const CountryTriviaApp(),
  ),
);
```

- `QuizViewModel extends ChangeNotifier` — the single source of truth for the UI.
- Views use `context.watch<QuizViewModel>()` to rebuild and
  `context.read<QuizViewModel>()` for actions.
- `Selector<QuizViewModel, T>` is used for the score header so a score change does not
  rebuild the flag image.
- `main()` awaits `SharedPreferences` **before** `runApp`, so the first frame already
  has the restored score — no loading flash on a wrong score.

### 3.4 ViewModel state machine

```dart
enum QuizStatus { loading, ready, error, complete }

class QuizViewModel extends ChangeNotifier {
  QuizStatus  status;
  List<Country> allCountries;      // full pool, shuffled once per run
  QuizQuestion? current;
  int attempt;                    // 1..3, resets on advance
  int score;
  int bestScore;
  Set<String> solvedIso2;         // persisted
  AnswerResult? lastResult;       // drives the reveal animation
  bool get canGuess => status == QuizStatus.ready && lastResult == null;
}
```

Allowed transitions (enforced by guards, not by hope):

```
loading ──▶ ready ──▶ complete
   │          │  ▲         │
   │          │  └─────────┘ (reset)
   └──▶ error ┘ (retry re-enters loading)
```

Guards that make illegal states unrepresentable:
- `guess(country)` is a no-op unless `canGuess` — a double-tap or a stale widget tap
  after the reveal cannot score twice.
- `advance()` is a no-op unless `lastResult?.isDecided == true`.
- `nextQuestion()` returns `null` (→ `complete`) when `solvedIso2.length == allCountries.length`.

### 3.5 Question generation

```dart
QuizQuestion buildQuestion(Country answer, List<Country> pool) {
  final distractors = _shuffled(pool.where((c) => c.iso2 != answer.iso2))
      .take(3)
      .map((c) => c.name)
      .toList();
  return QuizQuestion(
    country: answer,
    options: _shuffled([answer.name, ...distractors]),
  );
}
```

- Fisher–Yates shuffle with `Random.secure`.
- Distractor pool is drawn from the **full** 222-country list (not just unsolved ones) —
  drawing from unsolved-only would leak the remaining count and skew difficulty.
- Question order is a shuffled pass over the unsolved list, advanced one at a time, so
  "solved countries never reappear" holds by construction and the ordering stays random.

---

## 4. Persistence

`shared_preferences: ^2.5.5` (latest). Chosen over a database: the payload is one integer
and a list of 2-char strings — a few KB at most. SQLite would be a large amount of
machinery for no benefit. If a high-score leaderboard or question history is ever added,
this is the layer to swap behind the `GameProgressStore` interface.

**API choice: `SharedPreferencesWithCache`, not the legacy `SharedPreferences`.**
Since 2.3.0 the package ships three APIs and the old `SharedPreferences.getInstance()`
singleton is **deprecated** — pub.dev explicitly urges new code to use
`SharedPreferencesAsync` or `SharedPreferencesWithCache`. Of the two:

- `SharedPreferencesAsync` has no local cache, so *every* getter is an async
  platform-channel round-trip. Every `getInt`/`getStringList` in the view model would
  become a `Future`, which pushes async into the render path for no benefit.
- `SharedPreferencesWithCache` loads once via an async `create()`, then exposes
  **synchronous** getters from a local cache. This is the exact semantics needed here:
  the score and solved set are read once at startup and are thereafter owned by the
  view model.

So: one `await` at bootstrap, synchronous reads everywhere after. The `allowList` is
populated with the five keys from §4.1, which also means a corrupt or unexpected
non-supported value in the store can never crash the load.

> `SharedPreferencesWithCache` is loaded from a cache, so cross-isolate writes made by
> other engines would not be seen. That does not apply here — this app is
> single-isolate, single-engine, and the view model is the only writer.

### 4.1 Keys

| Key | Type | Meaning |
|---|---|---|
| `ct.score` | `int` | current run score |
| `ct.solved` | `StringList` | ISO2 codes solved this run |
| `ct.bestScore` | `int` | all-time best |
| `ct.poolSize` | `int` | country count at run start — detects API growth |
| `ct.schemaVersion` | `int` | forward-compat guard for future migrations |

### 4.2 Write policy

`SharedPreferencesWithCache.setStringList` is an async platform-channel write. Writing on
every tap would be wasteful, so:

- **Points are committed once per decided question**, not per tap.
- Writes are `await`ed inside the repository so ordering is guaranteed.
- Writes are fire-and-forget-safe: a failed write logs a warning but never crashes the
  game or rolls back the in-memory score.

### 4.3 Restore-on-launch

`initialize()` in the view model:

1. Read `ct.solved`, `ct.score`, `ct.bestScore`.
2. Fetch the country list.
3. If the fetched list is empty → `error` state, retry available, **persisted state untouched**.
4. If `ct.poolSize` differs from the fetched count (API added/removed countries), the
   solved set is intersected with the live ISO2 set to drop stale entries, and
   `poolSize` is rewritten. Solved countries whose codes vanished are silently dropped
   rather than blocking run completion forever.
5. Rehydrate the first unsolved question and set `ready`.

This is what makes "points and solved flags survive restarts" true, including a kill
between two questions.

---

## 5. Dependencies

| Package | Version | Purpose |
|---|---|---|
| `provider` | `^6.1.5` | state management / DI (MVVM binding) |
| `http` | `^1.6.0` | CountriesNow REST call |
| `shared_preferences` | `^2.5.5` | persistence |
| `cached_network_image` | `^4.0.3` | flag disk+memory cache, avoids refetching on rebuild |
| `equatable` | `^3.0.0` | value equality for entities/view state |

All five verified compatible with Dart 3.13 / Flutter 3.47.1.
`intl` is deliberately omitted — no date formatting is required.

`cached_network_image` matters for more than speed: without it, a `setState` on answer
selection re-decodes the PNG on every tap, which is visible as a flash.

### 5.1 Platform configuration

`<uses-permission android:name="android.permission.INTERNET"/>` is **missing** from
`android/app/src/main/AndroidManifest.xml` (it exists only in the debug/profile
manifests). Release builds will have **no network access** and the app will fail with a
socket exception. This must be added to the main manifest as step 1 of execution.

iOS needs no change (HTTPS + ATS-compliant host).

---

## 6. Execution Plan — Ticket Breakdown

The plan is decomposed into **15 tickets** across **9 waves** (Wave 0 = preflight,
Wave 8 = release verification). Tickets in the same wave are marked **[PARALLEL]** and
have no dependency on each other, so they can be executed concurrently by different
people or interleaved in one sitting.

### 6.1 How to read the waves

| Marker | Meaning |
|---|---|
| **[P]** | **Parallelisable** — no intra-wave dependency. Safe to start together. |
| **[S]** | **Serial** — strictly blocking. Nothing downstream may start. |
| 🔴 | On the **critical path** — a delay here delays the whole project. |
| ⛔ | **Hard gate** — a bug here ships an app that looks completely broken. See §1.2 / §5.1. |

### 6.2 Dependency graph

```
                        ┌──────────────────────┐
                        │ T01 Preflight   [S]🔴│
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ T02 Platform + deps  │  [S]🔴 ⛔ INTERNET permission
                        │     [S]⛔            │
                        └──────────┬───────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼────────┐        ┌────────▼─────────┐      ┌─────────▼────────┐
│ T03 Core consts│        │ T04 Domain       │      │ T05 Data models  │
│  + URL builder │ [P]    │  entities        │ [P]  │ + remote source  │
│  [P]⛔         │        │  [P]             │      │  [P]⛔           │
└───────┬────────┘        └────────┬─────────┘      └─────────┬────────┘
        │                          │                          │
        └──────────────────────────┼──────────────────────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ T06 Storage + Repo   │  [S]🔴 implements contracts
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ T07 QuizViewModel    │  [S]🔴 the heart
                        └──────────┬───────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼────────┐        ┌────────▼─────────┐      ┌─────────▼────────┐
│ T08 Unit tests │        │ T09 DI + app     │      │ T10 Shared UI    │
│  for core+VM   │ [P]    │  shell + theme   │ [P]  │ widgets          │
│  [P]           │        │  [P]             │      │  [P]             │
└───────┬────────┘        └────────┬─────────┘      └─────────┬────────┘
        │                          │                          │
        └──────────────────────────┼──────────────────────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ T11 Quiz screen     │  [S]🔴 integrates VM + UI
                        └──────────┬───────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼────────┐        ┌────────▼─────────┐      ┌─────────▼────────┐
│ T12 Game over  │        │ T13 Manual QA     │      │ T14 Polish +     │
│ screen + reset│ [P]    │ checklist run     │ [P]  │ a11y + formats   │
│  [P]           │        │  [P]⛔            │      │  [P]             │
└───────┬────────┘        └────────┬─────────┘      └─────────┬────────┘
        │                          │                          │
        └──────────────────────────┼──────────────────────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ T15 Release build    │  [S]🔴 proves INTERNET fix
                        └──────────────────────┘
```

### 6.3 Concurrency summary

| Wave | Tickets | Parallel? | Serial total | Wall-clock, 3 people |
|---|---|---|---|---|
| 0 | T01 | ✗ serial | 0.5 h | 0.5 h |
| 1 | T02 | ✗ serial | 0.5 h | 0.5 h |
| 2 | T03, T04, T05 | ✓ **3-way** | 4.5 h | **1.5 h** |
| 3 | T06 | ✗ serial | 2.5 h | 2.5 h |
| 4 | T07 | ✗ serial | 3 h | 3 h |
| 5 | T08, T09, T10 | ✓ **3-way** | 6 h | **2.5 h** |
| 6 | T11 | ✗ serial | 3 h | 3 h |
| 7 | T12, T13, T14 | ✓ **3-way** | 4.5 h | **2 h** |
| 8 | T15 | ✗ serial | 1.5 h | 1.5 h |
| | **15 tickets** | | **26 h** | **17 h** |

**~35% saved (26 h → 17 h) by parallelising Waves 2, 5 and 7** — the three 3-way
fan-outs. Estimates are engineering hours of focused work, excluding context-switching
and review overhead. Even fully parallel, a wave costs its **longest** ticket, so
splitting a wave's tickets further buys nothing.

> **Critical-path warning.** `T02 → T06 → T07 → T11 → T15` is serial and cannot be
> parallelised. It is ~10.5 h of the 17 h optimised total — **more than half the
> project**. Parallel work only shaves the leaves. If the schedule slips, attack this
> chain first: start it the moment T02 lands, and never let it wait on test (T08) or
> polish (T14) tickets.

### 6.4 Parallel-execution safety rules

Wave-level `[P]` markers describe *code* dependencies. When several tickets are in
flight at once, these additional rules apply:

1. **One owner per file.** No two concurrent tickets may write the same file. T03 owns
   `url_builder.dart`, T05 owns `country_model.dart` — no overlap.
2. **Contracts are frozen at the end of Wave 2.** T04 and T05 both code against
   `domain/entities/` and `core/`. Once T03–T05 land, those signatures are **frozen for
   the rest of the project**. A ticket that needs a contract change must either be
   absorbed by the contract owner or explicitly re-opened with a ripple-risk note.
3. **T07 depends on T04 + T05 contracts, not their internals.** It codes against
   `CountryRepository` and `GameProgressStore`, so it can start as soon as those
   interfaces exist — the implementations landing later does not block it.
4. **T08 runs alongside T09/T10, not after them.** Tests for T07's view model can be
   written from the `QuizViewModel` contract as soon as T07 lands; the widget tests in
   T10 need the widgets to exist and are the one part of Wave 5 with a soft ordering
   preference (write the VM tests first, the widget tests second).
5. **Wave 7 QA (T13) is parallel but not independent** — it must wait for T12, or it
   will be verifying a game with no end screen. It is placed in Wave 7 only because
   the *reset* path is exercised there. If T12 slips, T13 also slips; the `[P]` marker
   reflects that T14 is genuinely independent, not that T13 is.

---

## 7. Ticket Details

### Wave 0 — Preflight

#### T01 — Preflight and branch setup `[S]🔴`

| | |
|---|---|
| **Depends on** | — |
| **Files** | `test/widget_test.dart` (delete), branch `feat/country-trivia` |
| **Size** | 0.5 h |

1. `flutter --version` — confirm 3.47.1 / Dart 3.13.1.
2. `flutter doctor` — record Android toolchain warnings.
3. Create branch `feat/country-trivia`.
4. **Delete the generated `test/widget_test.dart`.** It asserts on the counter demo and
   fails the moment `main.dart` changes. Leaving it in place produces a confusing
   failure that looks like a regression in T07.

**Done when:** `flutter analyze` is clean on the untouched project.

---

### Wave 1 — Platform and dependencies

#### T02 — INTERNET permission and dependencies `[S]🔴⛔`

| | |
|---|---|
| **Depends on** | T01 |
| **Files** | `android/app/src/main/AndroidManifest.xml`, `pubspec.yaml` |
| **Size** | 0.5 h |

1. **Add `<uses-permission android:name="android.permission.INTERNET"/>` to
   `android/app/src/main/AndroidManifest.xml`.** This permission is present only in the
   debug and profile manifests. **Without it, release builds have no network and the
   app fails with a socket exception.** This is the single most important line in the
   whole build.
2. Add `provider ^6.1.5`, `http ^1.6.0`, `shared_preferences ^2.5.5`,
   `cached_network_image ^4.0.3`, `equatable ^3.0.0`.
3. `flutter pub get`; resolve the `shared_preferences_android` transitive version if the
   solver complains about DataStore.
4. Set `android:label` to `Country Trivia`; update the `pubspec.yaml` description.

**Done when:** `flutter pub get` succeeds, `flutter analyze` is clean, and
`flutter run` launches the demo app on an emulator.

> ⛔ **Verification deferred.** This permission cannot be truly proven here — the debug
> manifest already grants it, so a debug run passes either way. It is proven in **T15**
> with a release build. Do not mark networking "done" until then.

---

### Wave 2 — Foundation `[P]` — 3-way parallel, no intra-wave dependencies

#### T03 — Core constants, failures, and flag URL builder `[P]⛔`

| | |
|---|---|
| **Depends on** | T02 |
| **Files** | `lib/core/constants/app_constants.dart`, `lib/core/error/failure.dart`, `lib/core/utils/url_builder.dart`, `test/core/url_builder_test.dart` |
| **Size** | 1.5 h |

1. `app_constants.dart` — base URLs (`https://countriesnow.space/api/v0.1`,
   `https://flagcdn.com`), `maxAttempts = 3`, `pointsForAttempt = [10, 8, 5]`,
   storage keys, `allowList` for the preferences cache.
2. `failure.dart` — `sealed class Failure` with `NetworkFailure`, `ParseFailure`,
   `StorageFailure`, `NoCountriesFailure`.
3. `url_builder.dart` — `flagUrl(String iso2, {int width = 320})`.
4. `test/core/url_builder_test.dart` — assert `flagUrl('US')` →
   `https://flagcdn.com/w320/us.png`.

⛔ **The `.toLowerCase()` is the whole ticket.** flagcdn returns **404 for uppercase
ISO2** and the API returns uppercase. Omit it and every flag fails at runtime with no
compile error. Isolate the logic in one function so there is exactly one place it can
go wrong, and cover it with a test.

**Done when:** the URL test passes and `flagUrl('US')` is lowercase in the URL.

#### T04 — Domain entities and repository contract `[P]`

| | |
|---|---|
| **Depends on** | T02 |
| **Files** | `lib/domain/entities/country.dart`, `quiz_question.dart`, `answer_result.dart`, `game_state.dart`, `lib/domain/repositories/country_repository.dart` |
| **Size** | 1.5 h |

1. `Country` — `name`, `iso2`, `iso3`, `flagUrl` (delegates to T03's builder),
   `Equatable`; `@override` equality on `iso2`.
2. `QuizQuestion` — `country` + `List<String> options` (exactly 4) + `isCorrect(String)`.
3. `AnswerResult` — `correct`, `pointsAwarded`, `attemptNumber`, `isDecided`.
4. `GameState` — `score`, `solvedIso2`, `bestScore`, `runComplete`.
5. `CountryRepository` — the **abstract contract**. This is the interface T06 and T07
   both code against, so it must be complete and frozen before Wave 3.

**Done when:** all four entities compile, are immutable, and
`CountryRepository` has no implementation (interface only).

#### T05 — Data models and remote data source `[P]⛔`

| | |
|---|---|
| **Depends on** | T02 |
| **Files** | `lib/data/models/country_model.dart`, `lib/data/datasources/country_remote_data_source.dart` |
| **Size** | 1.5 h |

1. `country_model.dart` — `fromJson` mapping **`Iso2` / `Iso3` with a capital `I`**
   (`@JsonKey(name: 'Iso2')`). Validate the envelope: `error: true` → `ParseFailure`.
   Validate that `data` is a non-empty list and each `Iso2` is 2 uppercase chars.
2. `country_remote_data_source.dart` — `GET /countries/iso`, 15 s timeout, map
   non-200 / empty body / timeout to `NetworkFailure`. Return `List<Country>`.

⛔ **The `Iso2` key casing is the whole ticket.** The live API returns
`{"name":"Afghanistan","Iso2":"AF","Iso3":"AFG"}`. Dart's default `fromJson` will not
match `iso2`, so all 222 records silently become null fields and the app renders
nothing. Validated against the live response during planning.

**Done when:** a temporary script prints **222** parsed countries with a correct,
lowercase flag URL for a sample.

> **Note on the temporary script:** do this inside a `test/` file or a
> `debugPrint` in the data source, not as a committed `main()` hack. T08 folds it into
> a proper unit test.

---

### Wave 3 — Persistence and repository

#### T06 — Preferences store and repository implementation `[S]🔴`

| | |
|---|---|
| **Depends on** | T03, T04, T05 (contracts + implementations) |
| **Files** | `lib/data/datasources/game_progress_store.dart`, `lib/data/repositories/country_repository_impl.dart` |
| **Size** | 2.5 h |

1. `GameProgressStore` — typed getters/setters over `SharedPreferencesWithCache`
   (sync getters after async `create()`). **Never leak `SharedPreferences` types past
   this class** — the view model must not be able to reach the plugin.
2. `CountryRepositoryImpl` —
   - in-memory `List<Country>` cache, fetched at most once per run;
   - **restore logic per §4.3**, including the `poolSize` staleness check that
     intersects solved codes with the live ISO2 set;
   - commit-on-decide write policy per §4.2 (one write per decided question, not per tap);
   - `resetGame()` clears score + solved, retains `bestScore`;
   - failed writes log a warning and **never** crash the game or roll back the
     in-memory score.

**Done when:** the repository round-trips score and solved set through the store, and
a stale solved code is dropped on load.

---

### Wave 4 — ViewModel

#### T07 — QuizViewModel state machine `[S]🔴`

| | |
|---|---|
| **Depends on** | T06 |
| **Files** | `lib/presentation/viewmodels/quiz_view_model.dart` |
| **Size** | 3 h |

1. `QuizViewModel extends ChangeNotifier` with the state from §3.4.
2. `initialize()` → restore + fetch + rehydrate (§4.3).
3. `guess(String countryName)` → guarded; returns `AnswerResult`.
4. `advance()` → guarded; persists; loads next or completes.
5. `resetGame()` → clears run, keeps `bestScore`.
6. Scoring in a single pure private method so it is unit-testable in isolation.
7. `buildQuestion` per §3.5 — Fisher–Yates with `Random.secure`, distractors from the
   **full** pool, options shuffled.

**Hard constraints (checked in review):**
- No `BuildContext`, no `import 'package:flutter/material.dart'`.
- `guess` is a no-op unless `canGuess` — a double-tap must not score twice.
- `advance` is a no-op unless the last result is decided.
- A solved country can never become the answer of a later question.

**Done when:** `flutter analyze` is clean and the file has no Flutter UI import.

---

### Wave 5 — `[P]` — 3-way parallel

#### T08 — Unit tests for core, data, and view model `[P]`

| | |
|---|---|
| **Depends on** | T07 (T03–T05 parts can start as soon as those land) |
| **Files** | `test/core/url_builder_test.dart`, `test/data/country_model_test.dart`, `test/presentation/quiz_view_model_test.dart`, `test/helpers/fakes.dart` |
| **Size** | 2.5 h |

Write a **fake repository** and an **in-memory store** so no test touches the network.
Cover the §8.1 table, with priority on:

- `flagUrl('US')` is lowercase ⛔
- `Iso2` parses; 222 records; `error:true` throws
- scoring → 10 / 8 / 5 / 0
- double-tap scores **once**
- a solved country never reappears
- all solved → `complete`
- `resetGame()` → score 0, solved empty, `bestScore` kept
- stale solved codes dropped; run still completes

**Done when:** `flutter test` passes with no network access.

#### T09 — DI, app shell, and theme `[P]`

| | |
|---|---|
| **Depends on** | T07 |
| **Files** | `lib/di/service_locator.dart`, `lib/app.dart`, `lib/main.dart`, `lib/presentation/theme/app_theme.dart` |
| **Size** | 1.5 h |

1. `service_locator.dart` — construct the graph, dispose the `http.Client`.
2. `app_theme.dart` — Material 3, seeded colour scheme, light + dark.
3. `main.dart` — `WidgetsFlutterBinding.ensureInitialized()`, `await` the preferences
   cache, then `MultiProvider` + `runApp`.
4. `app.dart` — `MaterialApp` wired to the provider tree.

**Done when:** `flutter run` boots to a `loading` state with no provider lookup errors.

#### T10 — Shared UI widgets `[P]`

| | |
|---|---|
| **Depends on** | T07 (for state shape); T04/T05 (for `Country`) |
| **Files** | `lib/presentation/screens/widgets/*.dart` |
| **Size** | 2 h |

1. `loading_view.dart`, `error_view.dart` (with a working Retry button).
2. `flag_image_view.dart` — `CachedNetworkImage` with placeholder, error state, and a
   fixed 3:2 box so the layout does not jump while loading.
3. `option_tile.dart` — idle / selected-correct / selected-wrong / revealed-correct /
   disabled states.
4. `attempts_indicator.dart` — 3 dots.
5. `score_header.dart` — score, best, `LinearProgressIndicator` of solved / total.
6. `reveal_banner.dart` — correct name + points earned.

All widgets take **explicit constructor params**, not a `BuildContext` read of the
view model. This is what makes T10 parallelisable with T09 and testable in isolation.

**Done when:** each widget renders in isolation without a provider.

---

### Wave 6 — Screen assembly

#### T11 — Quiz screen `[S]🔴`

| | |
|---|---|
| **Depends on** | T07, T09, T10 |
| **Files** | `lib/presentation/screens/quiz_screen.dart` |
| **Size** | 3 h |

1. Assemble the widgets from T10.
2. `context.watch<QuizViewModel>()` for state; `context.read<QuizViewModel>()` for
   actions.
3. Use `Selector` for the score header so a score change does not rebuild the flag image.
4. Auto-advance after the reveal delay, with a manual "Next" affordance as an
   alternative.
5. Accessibility: semantics labels on options and the flag, `minTapTarget` ≥ 48 dp,
   correct/wrong conveyed by icon **and** text, not colour alone.

**Done when:** a full run is playable end to end with no overflow at 320×568 and no
console exceptions.

---

### Wave 7 — `[P]` — 3-way parallel

#### T12 — Game over screen and reset flow `[P]`

| | |
|---|---|
| **Depends on** | T07, T09, T10 |
| **Files** | `lib/presentation/screens/game_over_screen.dart` |
| **Size** | 1.5 h |

1. Final score, best score, countries solved.
2. **Reset button** → `resetGame()` → fresh run at score 0, `bestScore` retained.

**Done when:** solving the last country shows the screen, and reset restarts cleanly.

#### T13 — Manual QA against the §8.2 checklist `[P]⛔`

| | |
|---|---|
| **Depends on** | T11, T12 |
| **Files** | none (verification only) |
| **Size** | 2 h |

Run the full §8.2 checklist. Highest-value items, in order:

1. Scoring 10 / 8 / 5 / 0 — the core spec.
2. Solved countries absent from later questions.
3. **Force-quit mid-run → relaunch → score and solved set restored** ⛔ the persistence
   requirement, and the one most likely to be silently broken.
4. All solved → completion → reset → fresh run at 0.
5. Airplane mode → error screen, retry works, **no state loss**.
6. Options reshuffle between questions.
7. Longest name ("South Georgia and the South Sandwich Islands", 44 chars) wraps
   without overflow.

⛔ **This is a verification ticket, not a coding ticket.** Its findings feed back into
T11/T12 as fixes, which is why it sits in Wave 7 rather than after the release build.

#### T14 — Formatting, lint cleanup, and accessibility polish `[P]`

| | |
|---|---|
| **Depends on** | T11, T12 |
| **Files** | repo-wide formatting, `analysis_options.yaml` if tightened |
| **Size** | 1 h |

1. `dart format .` — verify no diff on re-run.
2. `flutter analyze` — drive to 0 issues.
3. Dark mode, 320×568 and tablet widths.
4. Colour contrast; colour is never the only signal.

**Done when:** `flutter analyze` is 0 issues and `dart format` is idempotent.

---

### Wave 8 — Release verification

#### T15 — Release build and persistence proof `[S]🔴⛔`

| | |
|---|---|
| **Depends on** | T13, T14 |
| **Files** | none (verification only) |
| **Size** | 1.5 h |

1. `flutter build apk --release` — **this is the first build that actually exercises the
   T02 INTERNET permission.** If it was missed, the app fails here with a socket
   exception and nothing earlier would have caught it.
2. Install and play a full run on the release build.
3. Re-run the force-quit/relaunch persistence check on the release build.
4. Update `README.md` with real setup and run instructions.

⛔ **Do not consider the project done until this passes.** It is the only proof that
the two highest-severity risks (§9, #2 and #3) are actually mitigated.

**Done when:** the release APK builds, plays online, and restores state across a kill.

## 8. Testing Strategy

### 8.1 Unit tests (`test/`) — highest value, no device needed

| Test | Assertion |
|---|---|
| `country_model_test` | parses `Iso2` correctly; 222 records; throws on `error:true`; throws on malformed data |
| `url_builder_test` | `flagUrl('US')` → `https://flagcdn.com/w320/us.png` (**lowercase**) |
| `scoring_test` | 1st correct → 10; 2nd → 8; 3rd → 5; 3 wrong → 0 and `isDecided` |
| `quiz_view_model_test` | double-tap on the same option scores **once** |
| `quiz_view_model_test` | a solved country is never the answer of a subsequent question |
| `quiz_view_model_test` | after solving all 222 → `complete` |
| `quiz_view_model_test` | `resetGame()` → score 0, solved empty, `bestScore` retained |
| `game_progress_store_test` | write → read round-trip of score + solved set |
| `restore_test` | stale solved codes are dropped; run still completes |

Use a **fake repository** and an **in-memory preferences mock** so tests need no network.

### 8.2 Manual verification checklist

- Correct on attempt 1 → +10, green highlight, correct answer locked in.
- Wrong, then correct on attempt 2 → +8.
- Wrong, wrong, correct → +5.
- Three wrong → 0, answer revealed, no negative score.
- Options reshuffled across questions.
- Solved countries absent from later questions.
- All countries solved → completion screen → reset → fresh run from 0.
- Force-quit mid-run → relaunch → score and solved set restored.
- Airplane mode at launch → error screen with working retry, no state loss.
- Slow network → loading indicator, no blank screen.
- Long country name ("South Georgia and the South Sandwich Islands", 44 chars)
  wraps without overflow.
- Dark mode, 320×568 and tablet widths.

### 8.3 Optional: network smoke test

A `flutter test --tags network` test (excluded from the default run) that hits the live
CountriesNow endpoint and asserts ≥ 200 countries and a 200 from flagcdn for a sample
code. Useful for catching upstream changes; must not run in CI by default.

---

## 9. Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | `Iso2` key casing mismatch → every country fails to parse | **Critical** | Verified against the live API; asserted in `country_model_test`; checked at the T03–T05 gate |
| 2 | flagcdn requires **lowercase** ISO2 → all flags 404, app looks dead, no compile error | **Critical** | Logic isolated in `UrlBuilder.flagUrl`; dedicated unit test |
| 3 | Missing `INTERNET` permission in the release manifest | **Critical** | T02 step 1; release build verified in T15 |
| 4 | Double-tap / stale-widget-tap scores twice | High | `canGuess` guard; explicit unit test |
| 5 | App restart loses progress | High | Persist on every decided question; `initialize()` restore; kill-restart manual test |
| 6 | API down or reshaped → unplayable | Medium | Failure hierarchy, retry screen, persisted state left untouched; optional remote smoke test |
| 7 | API adds/removes countries mid-run → run can never complete | Medium | `poolSize` check; stale codes intersected out on load (§4.3) |
| 8 | Flag images refetched on every rebuild → flicker, bandwidth | Medium | `cached_network_image` |
| 9 | Distractors drawn from unsolved-only leak remaining count | Low | Draw from the full pool |
| 10 | 222 questions is a long run with no save/resume of position | Low | Position is implicit — the next unsolved country is derived, so resuming is free |
| 11 | Flags for Norwegian/US dependencies look identical to their parent | Low | Verified correct flagcdn behaviour; leave as-is, note in README |

---

## 10. Definition of Done

- [ ] `flutter analyze` — 0 issues
- [ ] `dart format .` — no changes on re-run
- [ ] `flutter test` — all pass, no network required
- [ ] Full run playable end to end
- [ ] Scoring verified for 10 / 8 / 5 / 0
- [ ] Solved countries never repeat until reset
- [ ] Score + solved set survive force-quit and relaunch
- [ ] Reset clears the run and keeps the best score
- [ ] Release APK builds and works online
- [ ] README updated

---

## 11. Suggested Commit Sequence

One commit per ticket, tagged with the ticket ID so the history maps onto §7. Tickets
marked `[P]` in the same wave may be committed in any order relative to each other.

```
T01  chore: preflight — drop generated counter test, add feature branch
T02  chore: add INTERNET permission and project dependencies
T03  feat(core): constants, failures, and flagcdn url builder
T04  feat(domain): entities and repository contract
T05  feat(data): country model and CountriesNow remote data source
T06  feat(data): preferences store and repository implementation
T07  feat(viewmodel): quiz state machine with scoring and guards
T08  test: unit tests for url builder, model, scoring, and view model
T09  feat(di): manual service locator, app shell, and theme
T10  feat(ui): shared widgets — flag image, option tile, score header
T11  feat(ui): quiz screen assembly
T12  feat(ui): game over screen and reset flow
T13  (verification — no commit unless it produces fixes)
T14  style: formatting, lint cleanup, and accessibility polish
T15  docs: update README
```
