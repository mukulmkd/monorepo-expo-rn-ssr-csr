# Expo Modules Core Source

This directory contains the source code for `expo-modules-core`, copied from `node_modules/expo-modules-core`.

## Purpose

This source is used to build:
- **Android AAR**: Built from `android/` directory
- **iOS Framework/SPM**: Built from `ios/` directory

## Structure

```
expo-modules-core-source/
├── android/          # Android source (Kotlin, Java, C++)
├── ios/               # iOS source (Swift, Objective-C, C++)
├── common/            # Shared C++ code
└── package.json       # Package metadata
```

## Building

### Android AAR

```bash
cd android
./gradlew assembleRelease
# AAR will be in: android/build/outputs/aar/
```

### iOS Framework

iOS builds are typically done via Xcode or SPM. The source is used by the native-kit generation scripts.

## Version

This source corresponds to the version specified in `package.json`:
- Check `package.json` for the current version
- Update by copying from `node_modules/expo-modules-core` when upgrading

## Notes

- This is a snapshot of the source at a specific version
- Do not modify this source directly - update from `node_modules` when needed
- The source is used by `vsco-native-kit` build process
