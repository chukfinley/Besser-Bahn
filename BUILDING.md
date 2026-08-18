# Building Besser-Bahn (reproducible builds)

The release APKs are byte-for-byte reproducible **only** when the exact toolchain
below is used. The Android dex output depends on the JDK that runs R8, so the JDK
version matters as much as the Flutter version.

## Exact toolchain (release 2.0.0+1, tag `2.0.0+1`)

| Tool    | Version                                  |
|---------|------------------------------------------|
| Flutter | **3.41.9** (stable) — ships Dart 3.11.5  |
| JDK     | **21** (OpenJDK 21, e.g. Android Studio JBR 21.0.7) |
| AGP     | 8.9.1   (`android/settings.gradle`)      |
| Gradle  | 8.12    (`android/gradle/wrapper/...`)   |
| Kotlin  | 2.2.0   (`android/settings.gradle`)      |

R8 runs in full mode (`android.enableR8.fullMode=true`, committed in
`flutter-app/android/gradle.properties`).

> **JDK version is load-bearing.** Building with JDK 17 instead of JDK 21 makes
> R8 take different enum-switch optimization decisions (it keeps the
> `$SwitchMap` synthetic class instead of folding it to `Enum.ordinal()`), which
> changes `classes.dex` and breaks reproducibility. Use **JDK 21**.

## Current toolchain

The current development toolchain uses:

| Tool    | Version |
|---------|---------|
| Flutter | **3.44.3** (stable) — ships Dart **3.12.2** |
| Dart    | **3.12.2** |
| JDK     | **21** |
| AGP     | 8.9.1 |
| Gradle  | 8.12 |
| Kotlin  | 2.2.0 |

## Build

`RB` means **reproducible build**. The `rb-strip-buildid.sh` script is required
for reproducible builds and must run **after** `flutter pub get` and **before**
`flutter build`.

```sh
cd flutter-app
flutter pub get
./scripts/rb-strip-buildid.sh
flutter build apk --release --split-per-abi   # or appbundle, as released
