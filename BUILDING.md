# Building Besser-Bahn (reproducible builds)

The release APKs are byte-for-byte reproducible **only** when the exact toolchain
below is used. The Android dex output depends on the JDK that runs R8, so the JDK
version matters as much as the Flutter version.

## Exact toolchain (current)

| Tool    | Version                                             |
|---------|-----------------------------------------------------|
| Flutter | **3.47.0** (stable) — ships Dart 3.13.0             |
| JDK     | **21** (OpenJDK 21, e.g. Android Studio JBR 21.0.7)  |
| AGP     | 8.12.3  (`android/settings.gradle`)                 |
| Gradle  | 8.14.3  (`android/gradle/wrapper/...`)              |
| Kotlin  | 2.2.21  (`android/settings.gradle`)                 |

The Flutter version is pinned a second time in `flutter-app/pubspec.yaml`
(`environment: flutter:`) — IzzyOnDroid's RB script parses that line and clones
exactly that tag, so the two must always agree.

The four versions move together: Flutter 3.47 refuses to build below Gradle
8.14, AGP 8.11.1 and Kotlin 2.2.20, so a Flutter bump is never a one-line
change. Every one of them also changes the dex output, which means the toolchain
above defines a new RB baseline.

**Older tags need the older toolchain.** Releases up to 2.3.1 were built with
Flutter 3.41.9 (Dart 3.11.5), Gradle 8.12, AGP 8.9.1 and Kotlin 2.2.0. Rebuild
those tags with that set, not with the table above.

R8 runs in full mode (`android.enableR8.fullMode=true`, committed in
`flutter-app/android/gradle.properties`).

> **JDK version is load-bearing.** Building with JDK 17 instead of JDK 21 makes
> R8 take different enum-switch optimization decisions (it keeps the
> `$SwitchMap` synthetic class instead of folding it to `Enum.ordinal()`), which
> changes `classes.dex` and breaks reproducibility. Use **JDK 21**.

## Build

`RB` = reproducible build. `rb-strip-buildid.sh` runs **after** `flutter pub get`
and **before** `flutter build` — see the section below for why.

```sh
cd flutter-app
flutter pub get
./scripts/rb-strip-buildid.sh                 # REQUIRED for RB — see below
flutter build apk --release --split-per-abi   # or appbundle, as released
```

The `rb-strip-buildid.sh` step must run on **both** the release build and the RB
rebuild, otherwise `lib/*/libdartjni.so` differs.

## Known cosmetic diff: `lib/*/libdartjni.so`

The Dart JNI native lib (`jni` pub package, pulled in transitively via
`flutter_secure_storage`) embeds a unique build-id — an upstream Flutter issue —
so every build produces a different `.so`. `scripts/rb-strip-buildid.sh` patches
the package's `CMakeLists.txt` in the pub cache to add `-Wl,--build-id=none`,
which makes the lib deterministic. It is idempotent and safe to re-run.

The equivalent IzzyOnDroid recipe step is:

```yaml
- flutter pub get
- sed -i -e 's/-Wl,/-Wl,--build-id=none,/' ${PUB_CACHE}/hosted/*/jni-*/src/CMakeLists.txt
```

## Continuous integration

`.github/workflows/flutter-ci.yml` runs `flutter analyze` and `flutter test` on
every pull request that touches `flutter-app/`. It takes the SDK version from
`flutter-app/pubspec.yaml` (`flutter-version-file`), so CI always uses the same
Flutter as the release build — there is no second version to keep in sync.

## Per-release checklist

- Bump `version:` in `flutter-app/pubspec.yaml` (e.g. `2.0.5+6`).
- **Git tag + GitHub release use the PLAIN semver only — `2.0.5`, never
  `2.0.5+6`.** The `+N` is Flutter's internal build number; Gradle derives the
  `versionCode` from the semver alone (`major*10000+minor*100+patch`, +ABI
  offset) and strips the `+N`, so it never reaches users. A `+N` in the release
  tag is just noise and breaks the clean semver convention F-Droid/Obtainium
  expect. (Older tags `2.0.0+1 … 2.0.4+5` predate this rule; don't copy them.)
- **Pre-releases are `X.Y.Z-rc.N`** (`2.1.0-rc.1`), tagged as such and flagged
  as a pre-release on GitHub. Gradle maps `-rc.N` to `final-10+N`, so the RC
  ranks below its own final release but above the previous one — a tester on
  `2.1.0-rc.1` (20091) is still offered `2.1.0` (20100). Only `rc.1 … rc.9`;
  the build fails loudly on anything else rather than compute a silly code.
  Don't hand-write a `versionCode`, and don't ship an RC as a plain patch bump.
- Bump the exact `flutter:` version in `flutter-app/pubspec.yaml` to the Flutter
  version you actually build with (IzzyOnDroid's RB script parses that line).
- Update the table above and the GitHub release notes with the Flutter **and**
  JDK version used.
