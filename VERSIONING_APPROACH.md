# Versioning Approach for Native Kit AARs and SPMs

## Overview
This document outlines the approach for versioning the generated Android AARs and iOS SPM packages.

## Current State

### Android AAR
- **Location**: `vsco-native-kit/android/build.gradle`
- **Current Version**: Hardcoded to `1.0.0` (line 81)
- **Publishing**: Maven Local with group `com.vsco`, artifact `vsco-native-kit`

### iOS SPM
- **Location**: `vsco-native-kit/ios/VSCONativeKit/Package.swift`
- **Current Version**: No explicit version (SPM uses Git tags)
- **Publishing**: Git repository with tags

## Versioning Approaches

### Option 1: Single Source of Truth (Recommended)
Use a single version file that both scripts read from.

**Structure:**
```
vsco-native-kit/
  VERSION.txt          # Single source: "1.0.0"
  android/
    build.gradle       # Reads from VERSION.txt
  ios/
    VSCONativeKit/
      Package.swift    # Uses Git tags (derived from VERSION.txt)
```

**Implementation:**
1. Create `vsco-native-kit/VERSION.txt` with version number
2. Android script reads version and updates `build.gradle`
3. iOS uses Git tags (can be automated from VERSION.txt)
4. Both scripts can auto-increment or use semantic versioning

**Pros:**
- Single source of truth
- Easy to maintain
- Consistent versions across platforms

**Cons:**
- Requires script modifications
- Need to handle Git tagging for SPM

### Option 2: Package.json Version
Use the root `package.json` version as the source.

**Structure:**
```json
// package.json
{
  "version": "1.0.0",
  "nativeKit": {
    "version": "1.0.0"  // Or use root version
  }
}
```

**Implementation:**
1. Read version from `package.json`
2. Android script updates `build.gradle`
3. iOS uses Git tags (can be derived from package.json)

**Pros:**
- Integrates with npm/package ecosystem
- Can use npm version commands
- Familiar to JavaScript developers

**Cons:**
- Couples native kit version to npm package version
- May not align with native release cycles

### Option 3: Environment Variable / Script Parameter
Pass version as a parameter to the generation scripts.

**Usage:**
```bash
./scripts/generate-native-kit-android.sh --version 1.2.3
./scripts/generate-native-kit-ios.sh --version 1.2.3
```

**Implementation:**
1. Script accepts `--version` parameter
2. Defaults to current version if not provided
3. Updates both Android and iOS accordingly

**Pros:**
- Flexible per-build
- Can be integrated into CI/CD
- No file dependencies

**Cons:**
- Must remember to pass version
- Risk of version mismatch if forgotten

### Option 4: Semantic Versioning with Auto-increment
Automatically increment version based on changes.

**Structure:**
```
vsco-native-kit/
  VERSION.txt          # "1.0.0"
  CHANGELOG.md         # Tracks changes
```

**Implementation:**
1. Script detects changes (new packages, modified code)
2. Auto-increments patch/minor/major based on change type
3. Updates VERSION.txt and build files
4. Creates Git tag for iOS SPM

**Pros:**
- Automated version management
- Reduces manual errors
- Follows semantic versioning

**Cons:**
- Complex to implement
- May increment when not needed
- Requires change detection logic

## Recommended Approach: Hybrid (Option 1 + Option 3)

### Implementation Plan

1. **Create VERSION.txt** (default version source)
   ```
   vsco-native-kit/VERSION.txt
   Content: 1.0.0
   ```

2. **Script Modifications:**
   - Both scripts read from `VERSION.txt` by default
   - Accept `--version` parameter to override
   - Android: Update `build.gradle` version
   - iOS: Create/update Git tag (for SPM)

3. **Version File Format:**
   ```
   1.0.0
   ```
   Or with metadata:
   ```
   version=1.0.0
   build=123
   date=2024-12-16
   ```

4. **Script Flow:**
   ```bash
   # Read version
   if [ -n "$VERSION" ]; then
       NATIVE_KIT_VERSION="$VERSION"
   elif [ -f "$KIT_DIR/VERSION.txt" ]; then
       NATIVE_KIT_VERSION=$(cat "$KIT_DIR/VERSION.txt" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+" | head -1)
   else
       NATIVE_KIT_VERSION="1.0.0"  # Default
   fi
   
   # Update Android build.gradle
   sed -i '' "s/version = '.*'/version = '$NATIVE_KIT_VERSION'/" build.gradle
   
   # For iOS: Create Git tag
   git tag "v$NATIVE_KIT_VERSION" 2>/dev/null || true
   ```

5. **Git Tagging for SPM:**
   - SPM packages use Git tags for versioning
   - Format: `v1.0.0` or `1.0.0`
   - Script should create tag if it doesn't exist
   - Tag should point to current commit

## Version Numbering Strategy

### Semantic Versioning (Recommended)
- **MAJOR.MINOR.PATCH** (e.g., 1.2.3)
- **MAJOR**: Breaking changes (API changes, incompatible dependencies)
- **MINOR**: New features (new packages, new functionality)
- **PATCH**: Bug fixes, small improvements

### Examples:
- `1.0.0` → `1.0.1`: Fixed a bug
- `1.0.1` → `1.1.0`: Added new package (react-native-gesture-handler)
- `1.1.0` → `2.0.0`: Breaking change (React Native upgrade, API changes)

## Implementation Checklist

### Phase 1: Setup (No Script Changes)
- [ ] Create `vsco-native-kit/VERSION.txt` with initial version
- [ ] Document versioning strategy
- [ ] Decide on version numbering approach

### Phase 2: Android Script Updates
- [ ] Add version reading logic
- [ ] Update `build.gradle` version dynamically
- [ ] Add `--version` parameter support
- [ ] Test version updates

### Phase 3: iOS Script Updates
- [ ] Add version reading logic
- [ ] Create Git tag for SPM versioning
- [ ] Add `--version` parameter support
- [ ] Test Git tagging

### Phase 4: Automation (Optional)
- [ ] Auto-increment patch version on rebuild
- [ ] Detect changes and suggest version bump
- [ ] Integration with CI/CD

## Usage Examples

### Basic Usage (Default Version)
```bash
# Uses version from VERSION.txt
./scripts/generate-native-kit-android.sh
./scripts/generate-native-kit-ios.sh
```

### Override Version
```bash
# Override with specific version
./scripts/generate-native-kit-android.sh --version 1.2.3
./scripts/generate-native-kit-ios.sh --version 1.2.3
```

### Update Version File
```bash
# Update VERSION.txt
echo "1.2.3" > vsco-native-kit/VERSION.txt

# Regenerate with new version
./scripts/generate-native-kit-android.sh
./scripts/generate-native-kit-ios.sh
```

## Notes

1. **SPM Versioning**: iOS SPM packages require Git tags. The script should:
   - Check if tag exists
   - Create tag if missing
   - Use tag format: `v1.0.0` or `1.0.0`

2. **Maven Versioning**: Android AARs use Maven coordinates:
   - Group: `com.vsco`
   - Artifact: `vsco-native-kit`
   - Version: From VERSION.txt or parameter

3. **Version Consistency**: Both platforms should use the same version number for the same release.

4. **Git Integration**: For iOS SPM, ensure:
   - Repository is initialized
   - Changes are committed before tagging
   - Tags are pushed to remote

