# Module Distribution Checklist

Quick reference checklist for building and distributing modules.

## Pre-Build

- [ ] Create `ModuleExport.tsx` component
- [ ] Update `index.js` to export module
- [ ] Add build scripts to `package.json`
- [ ] Install build dependencies

## Build

- [ ] Run `npm run build:bundle:ios`
- [ ] Run `npm run build:bundle:android`
- [ ] Verify bundles are created
- [ ] Verify assets are included
- [ ] Test bundles locally (if possible)

## Distribution

- [ ] Version the bundles (e.g., v1.0.0)
- [ ] Package bundles + assets
- [ ] Create integration documentation
- [ ] Document dependencies and requirements
- [ ] Create changelog

## Integration Testing

- [ ] Provide bundles to native teams
- [ ] Verify iOS integration works
- [ ] Verify Android integration works
- [ ] Test all functionality in native apps
- [ ] Document any issues found

## Release

- [ ] Tag version in git
- [ ] Update version numbers
- [ ] Document breaking changes (if any)
- [ ] Provide upgrade guide (if needed)
