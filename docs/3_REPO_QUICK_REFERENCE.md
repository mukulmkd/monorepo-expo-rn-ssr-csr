# 3-Repository Architecture - Quick Reference

## Answers to Your Questions

### Q1: Runtime Repository - Do we need a separate Git repository?

**Answer: NO - Use your existing runtime Git repository.**

- ✅ **Single repository** containing both Android (`mkd-rn-host`) and iOS (`MKDReactNativeRuntime`)
- ✅ Structure: `runtime-repo/android/` and `runtime-repo/ios/`
- ✅ You can version them together (recommended) or separately if needed

**Structure:**

```
your-runtime-repo/          # Your existing Git repo
├── android/
│   └── mkd-rn-host/
├── ios/
│   └── MKDReactNativeRuntime/
└── scripts/
```

---

### Q2: Module SPMs - Do we need 3 separate repositories?

**Answer: You have TWO options**

#### Option A: Separate Repositories (Original Recommendation)

For iOS SPM packages, create **3 separate GitHub repositories**:

- `MKDRNModuleProductsSPM.git`
- `MKDRNModuleCartSPM.git`
- `MKDRNModulePDPSPM.git`

**Why separate repos?**

- ✅ Industry standard for Swift Package Manager
- ✅ Independent versioning per module
- ✅ Better for CI/CD pipelines
- ✅ Cleaner dependency management

#### Option B: Single Repository (Alternate Strategy - Recommended for Scalability)

Use **one GitHub repository** for all module SPM packages:

- `react-native-modules.git` (contains all modules)

**Two sub-options:**

**B1: Shared Versioning** (Simpler)

- ✅ All modules version together (e.g., all at v1.0.0)
- ✅ Works with SPM natively
- ⚠️ All modules must version together

**B2: Independent Versioning** (More Flexible)

- ✅ Each module has its own version (e.g., products@1.0.0, cart@2.0.0)
- ✅ Single repository for all modules
- ⚠️ Requires manual version tracking via VERSIONS.md
- ⚠️ Xcode shows repository version, not per-module versions

**📖 See:**

- [Shared Versioning Guide](./3_REPO_MODULES_SPM_ALTERNATE_STRATEGY.md) - For Option B1
- [Independent Versioning Guide](./3_REPO_MODULES_SPM_INDEPENDENT_VERSIONING.md) - For Option B2

---

## Repository Summary

| Repository   | Purpose                  | Git Structure                                                                                           | Publishing                                            |
| ------------ | ------------------------ | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **Monorepo** | React Native development | Single repo                                                                                             | Verdaccio (npm)                                       |
| **Runtime**  | Android + iOS runtime    | Single repo (your existing)                                                                             | Maven Local/Artifactory (Android)<br>GitHub (iOS SPM) |
| **Modules**  | Module AARs + SPMs       | **Option A:** 3 separate GitHub repos (iOS)<br>**Option B:** Single repo (iOS)<br>Single repo (Android) | Maven Local/Artifactory (Android)<br>GitHub (iOS SPM) |

---

## Quick Migration Checklist

### Step 1: Runtime Repository

- [ ] Use existing runtime Git repository
- [ ] Create `android/` and `ios/` directories
- [ ] Copy `mkd-rn-host` from monorepo → `android/mkd-rn-host`
- [ ] Copy `MKDReactNativeRuntime` from monorepo → `ios/MKDReactNativeRuntime`
- [ ] Create build/publish scripts
- [ ] Set up GitHub repository for iOS SPM (if not already)

### Step 2: Module Repository (iOS)

**Choose one approach:**

**Option A: Separate Repositories**

- [ ] Create 3 GitHub repositories:
  - [ ] `MKDRNModuleProductsSPM`
  - [ ] `MKDRNModuleCartSPM`
  - [ ] `MKDRNModulePDPSPM`
- [ ] Copy SPM packages from monorepo to respective repos
- [ ] Create generation/publish scripts

**Option B: Single Repository (Recommended for Scalability)**

- [ ] Create single repository: `react-native-modules`
- [ ] Copy all SPM packages from monorepo to `ios/` directory
- [ ] Create generation/publish scripts
- [ ] See [Single Repository Strategy Guide](./3_REPO_MODULES_SPM_ALTERNATE_STRATEGY.md) for details

### Step 3: Module Repository (Android)

- [ ] Create single repository: `react-native-modules-android`
- [ ] Copy all `mkd-rn-module-*` from monorepo
- [ ] Create generation/publish scripts

### Step 4: Update Monorepo

- [ ] Remove `frameworks/` directory
- [ ] Remove `android-props/` directory
- [ ] Remove framework generation scripts from `package.json`
- [ ] Update documentation

---

## Workflow Summary

### Development

1. **Monorepo**: Develop React Native modules → Publish to Verdaccio
2. **Runtime Repo**: Build Android AAR / iOS SPM → Publish
3. **Module Repo**: Generate AARs/SPMs from Verdaccio → Publish

### Publishing

**Android AAR:**

```bash
# Runtime
npm run publish:android:local    # or central

# Modules
npm run publish:android:products:local
```

**iOS SPM:**

```bash
# Runtime
npm run publish:ios 1.0.0        # Creates Git tag on GitHub

# Modules
npm run publish:ios:products 1.0.0  # Creates Git tag on GitHub
```

---

## File Locations After Split

### Monorepo (Stays)

- `apps/` - React Native modules
- `packages/` - Shared packages
- `tools/verdaccio/` - Verdaccio config
- `docs/` - Documentation

### Runtime Repository (Moves)

- `frameworks/android/mkd-rn-host/` → `runtime-repo/android/mkd-rn-host/`
- `frameworks/ios/MKDReactNativeRuntime/` → `runtime-repo/ios/MKDReactNativeRuntime/`
- `android-props/` → `runtime-repo/android-props/`

### Module Repository (Moves)

- `frameworks/android/mkd-rn-module-*/` → `modules-repo/android/mkd-rn-module-*/`
- `frameworks/ios/MKDRNModule*SPM/` → Separate GitHub repos (one per module)

---

## Next Steps

1. ✅ Read full guide: [3_REPO_ARCHITECTURE.md](./3_REPO_ARCHITECTURE.md)
2. ✅ Set up GitHub repositories for iOS SPM packages
3. ✅ Migrate runtime code to your existing runtime repository
4. ✅ Migrate module code to module repositories
5. ✅ Test end-to-end workflow

---

## Need Help?

See the full documentation: [3_REPO_ARCHITECTURE.md](./3_REPO_ARCHITECTURE.md)
