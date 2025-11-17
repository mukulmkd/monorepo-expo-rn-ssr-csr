# Module Distribution Checklist

Quick reference checklist for publishing and distributing modules via Verdaccio.

## Prerequisites

- [ ] Node.js >= 20 installed
- [ ] All workspace dependencies installed (`npm install` from repo root)
- [ ] Verdaccio is running (`npm run verdaccio:start`)
- [ ] Logged into Verdaccio (`npm login --registry http://localhost:4873`)
- [ ] npm scopes configured (`npm set @pkg:registry http://localhost:4873` and `@app:registry`)

## Development

- [ ] Module code is complete and tested
- [ ] Module exports correct component name (e.g., `ModuleProducts`)
- [ ] Module registers with `AppRegistry` in `index.js`
- [ ] All dependencies are listed in `package.json`
- [ ] Peer dependencies are correctly specified
- [ ] TypeScript types are exported (if applicable)

## Versioning

- [ ] Version number updated in `package.json`
- [ ] Version follows semantic versioning (e.g., `0.1.0`, `0.2.0`, `1.0.0`)
- [ ] Version change committed to git
- [ ] Changelog updated (if maintained)

## Publishing

- [ ] Verdaccio is running and accessible
- [ ] All packages published: `npm run verdaccio:publish-all`
- [ ] Verify packages are available: `npm view @app/module-products --registry http://localhost:4873`
- [ ] Check Verdaccio web UI: http://localhost:4873

## Native App Integration

- [ ] Native app has `.npmrc` configured
- [ ] Native app has installed packages: `npm install @app/module-products@<version>`
- [ ] Native app has entry point (`js/index.js`) that imports modules
- [ ] Native app has bundling scripts configured
- [ ] Bundles generated: `npm run bundle:products` (or equivalent)
- [ ] Bundles copied to correct native asset locations

## Testing

- [ ] Module loads in native Android app
- [ ] Module loads in native iOS app
- [ ] All functionality works as expected
- [ ] Navigation works correctly
- [ ] State management works (Redux)
- [ ] Assets load correctly (images, fonts, etc.)
- [ ] No console errors or warnings

## Documentation

- [ ] Module README is up to date (if applicable)
- [ ] Integration guide is accurate
- [ ] Breaking changes documented (if any)
- [ ] Migration guide provided (if needed)

## Release

- [ ] All tests passing
- [ ] Version tagged in git: `git tag v0.1.0`
- [ ] Release notes created
- [ ] Native teams notified of new version
- [ ] Native teams have updated their dependencies

## Troubleshooting

If publishing fails:
- [ ] Check Verdaccio is running
- [ ] Verify you're logged in
- [ ] Check version doesn't already exist
- [ ] Verify package.json is valid
- [ ] Check network connectivity

If integration fails:
- [ ] Verify `.npmrc` is correct
- [ ] Check package versions match
- [ ] Ensure bundles are regenerated after package updates
- [ ] Verify native app dependencies are compatible
- [ ] Check Metro bundler configuration

## Quick Commands

```bash
# Start Verdaccio
npm run verdaccio:start

# Publish all packages
npm run verdaccio:publish-all

# Check published version
npm view @app/module-products --registry http://localhost:4873

# In native app: Install package
npm install @app/module-products@0.1.0

# In native app: Bundle
npm run bundle:products
```

## Related Documentation

- **[LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md)** – Detailed Verdaccio setup
- **[MODULE_DISTRIBUTION.md](./MODULE_DISTRIBUTION.md)** – Distribution workflow
- **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** – Native app integration
- **[PACKAGES.md](./PACKAGES.md)** – Package documentation
