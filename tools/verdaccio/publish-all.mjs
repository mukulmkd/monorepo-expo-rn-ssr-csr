#!/usr/bin/env node

import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const registry =
  process.env.VERDACCIO_REGISTRY ?? "http://localhost:4873";

const packages = [
  { name: "@pkg/core", location: "../../packages/core" },
  { name: "@pkg/state", location: "../../packages/state" },
  { name: "@pkg/ui", location: "../../packages/ui" },
  { name: "@pkg/homepage-ui", location: "../../packages/homepage-ui" },
  { name: "@pkg/products-ui", location: "../../packages/products-ui" },
  { name: "@pkg/cart-ui", location: "../../packages/cart-ui" },
  { name: "@pkg/pdp-ui", location: "../../packages/pdp-ui" },
  { name: "@app/module-products", location: "../../apps/module-products" },
  { name: "@app/module-cart", location: "../../apps/module-cart" },
  { name: "@app/module-pdp", location: "../../apps/module-pdp" }
];

function run(command, cwd) {
  execSync(command, {
    cwd,
    stdio: "inherit"
  });
}

function isPublished(name, version) {
  try {
    execSync(`npm view ${name}@${version} version --registry ${registry}`, {
      stdio: "ignore"
    });
    return true;
  } catch {
    return false;
  }
}

try {
  console.log(`Using registry: ${registry}`);

  for (const pkg of packages) {
    const cwd = resolve(__dirname, pkg.location);
    console.log(`\n📦 Publishing ${pkg.name}`);

     const pkgJson = JSON.parse(
      readFileSync(resolve(cwd, "package.json"), "utf8")
    );
    const currentVersion = pkgJson.version;

    if (isPublished(pkg.name, currentVersion)) {
      console.log(
        `⚠️  ${pkg.name}@${currentVersion} already exists in registry, skipping`
      );
      continue;
    }

    run("npm install", cwd);
    run("npm run build --if-present", cwd);
    run(`npm publish --registry ${registry}`, cwd);
  }

  console.log("\n✅ All packages published to Verdaccio");
} catch (error) {
  console.error("\n❌ Publishing failed");
  console.error(error.message ?? error);
  process.exit(1);
}

