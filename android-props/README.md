# Android Properties Configuration

This folder contains centralized Android build configuration files that are used by all AAR generation and publishing scripts.

## Files

### `local.properties`
Contains the Android SDK location. This file is copied to each generated AAR project (host and modules) during generation.

**Format:**
```properties
sdk.dir=/path/to/android/sdk
```

**Example:**
```properties
sdk.dir=/Users/username/Library/Android/sdk
```

### `artifactory.properties`
Contains Artifactory credentials for publishing AARs to a central Maven repository. This file is used by the `publish-aar.sh` script when publishing to Artifactory (central location).

**Note:** This file contains sensitive credentials and should NOT be committed to git. It's already in `.gitignore`.

**Format:**
```properties
artifactory_contextUrl=https://your-artifactory-url.com/artifactory
mobileRepo=repository-name
artifactory_user=username
artifactory_password=password
```

### `artifactory.properties.example`
Example template for `artifactory.properties`. Copy this file to `artifactory.properties` and fill in your credentials.

## Usage

### For AAR Generation
The scripts automatically use these files:
- `generate-react-native-runtime-host-aar.sh` - Copies `local.properties` to host project
- `generate-module-framework-aar.sh` - Copies `local.properties` to each module project

### For AAR Publishing
The `publish-aar.sh` script reads `artifactory.properties` when publishing to Artifactory:
```bash
./scripts/publish-aar.sh AAR=mkd-rn-host LOCATION=central
```

## Benefits

1. **Centralized Configuration** - All Android properties in one place
2. **Version Control Friendly** - Only `local.properties` and `artifactory.properties.example` are tracked
3. **Easy Updates** - Update once, affects all generated projects
4. **Clean Separation** - `frameworks/android` can be deleted and regenerated without losing configuration

## Setup

1. **Create `local.properties`:**
   ```bash
   echo "sdk.dir=/path/to/your/android/sdk" > android-props/local.properties
   ```

2. **Create `artifactory.properties` (optional, for Artifactory publishing):**
   ```bash
   cp android-props/artifactory.properties.example android-props/artifactory.properties
   # Edit and fill in your credentials
   ```

## Notes

- `local.properties` should be committed to git (it's just a path)
- `artifactory.properties` should NOT be committed (contains credentials)
- Both files are copied to generated projects automatically
- If `local.properties` is missing, scripts will try to use `ANDROID_HOME` environment variable as fallback

