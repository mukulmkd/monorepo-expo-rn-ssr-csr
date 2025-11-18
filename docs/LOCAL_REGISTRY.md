# Local Verdaccio Registry

This guide walks through running a private Verdaccio registry on your machine and publishing the workspace packages so they can be consumed by the native Android and iOS apps.

## Prerequisites

- Node.js 20+
- All workspace dependencies installed (`npm install` from the repo root)

## 1. Start Verdaccio

```bash
npm run verdaccio:start
```

The registry listens on `http://localhost:4873` and stores data under `.verdaccio/` (ignored by git).

## 2. Create a Local npm User (first run only)

In a separate terminal:

```bash
npm adduser --registry http://localhost:4873
# Username: verdaccio
# Password: choose any value
# Email: optional
```

The credentials are saved in your global npm config and Verdaccio's `htpasswd` file.

## 3. Point Scoped Packages to Verdaccio

Configure npm so the monorepo scopes resolve from the local registry:

```bash
npm set @pkg:registry http://localhost:4873
npm set @app:registry http://localhost:4873
```

You can reset later with `npm config delete @pkg:registry` (same for `@app`).

## 4. Publish All Packages

With Verdaccio running and you logged in, publish every workspace package in dependency order:

```bash
npm run publish:verdaccio
```

The helper script will:

1. Install dependencies inside each package
2. Run the local build (if defined)
3. Publish to `http://localhost:4873`

If a version already exists, bump the `version` field before re-running the script.

## 5. Consume Packages in Other Projects

Native apps live in their own repositories. In each consumer project:

1. **Configure npm** (once per project)

   Create or update `.npmrc` at the project root:

   ```ini
   @pkg:registry=http://localhost:4873
   @app:registry=http://localhost:4873
   ```

   Or run the equivalent commands:

   ```bash
   npm set @pkg:registry http://localhost:4873
   npm set @app:registry http://localhost:4873
   ```

2. **Install the published modules**

   ```bash
   npm install @app/module-products@0.1.0
   npm install @app/module-cart@0.1.0
   npm install @app/module-pdp@0.1.0
   ```

   Replace versions with the latest ones published to Verdaccio.

3. **Bundle inside the native app**

   Each native project runs Metro locally to create the platform bundle (see `docs/NATIVE_APP_CONSUMPTION.md`).

## Package Documentation

For detailed information about available packages and their APIs, see [PACKAGES.md](./PACKAGES.md).

## 6. Stop Verdaccio

Use `Ctrl+C` in the Verdaccio terminal. To clear all published packages, run:

```bash
npm run verdaccio:reset
```

## 7. Republish After Restart or Changes

Whenever you stop Verdaccio and need to publish again:

1. **Restart Verdaccio**

   ```bash
   npm run verdaccio:start
   ```

2. **Log back in** (tokens are wiped when the server stops)

   ```bash
   npm login --registry http://localhost:4873
   ```

3. **Ensure registry mappings exist** (only if they were reset)

   ```bash
   npm set @pkg:registry http://localhost:4873
   npm set @app:registry http://localhost:4873
   ```

4. **Bump package versions if republishing**

5. **Publish**
   ```bash
   npm run publish:verdaccio
   ```

## Tips

- To inspect what is available, open http://localhost:4873 in the browser.
- Keep versions in sync; Verdaccio behaves like npm and blocks publishing the same version twice.
- When you're done, reset registry overrides:

  ```bash
  npm config delete @pkg:registry
  npm config delete @app:registry
  ```

- For automation in CI, set `VERDACCIO_REGISTRY` before running `publish:verdaccio` to point at a different registry URL.
