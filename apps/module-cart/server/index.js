const express = require("express");
const path = require("path");
require("module-alias/register");
const { addAlias } = require("module-alias");
addAlias("react-native", "react-native-web");
const esbuild = require("esbuild");
// Client plugin: alias react-native to react-native-web, ensure React deduplication
const clientAliasPlugin = {
  name: "client-alias",
  setup(build) {
    build.onResolve({ filter: /^react-native$/ }, () => ({
      path: require.resolve("react-native-web"),
    }));
    const reactPath = require.resolve("react");
    const reactDomPath = require.resolve("react-dom");
    build.onResolve({ filter: /^react$/ }, () => ({ path: reactPath }));
    build.onResolve({ filter: /^react-dom$/ }, () => ({ path: reactDomPath }));
    build.onResolve({ filter: /^react-dom\/client$/ }, () => ({
      path: require.resolve("react-dom/client"),
    }));
  },
};

// Server plugin: only alias react-native, let React be external
const serverAliasPlugin = {
  name: "server-alias",
  setup(build) {
    build.onResolve({ filter: /^react-native$/ }, () => ({
      path: require.resolve("react-native-web"),
    }));
    build.onResolve({ filter: /^react$/ }, () => ({ external: true }));
    build.onResolve({ filter: /^react-dom$/ }, () => ({ external: true }));
    build.onResolve({ filter: /^react-dom\/server$/ }, () => ({
      external: true,
    }));
  },
};

const app = express();
const PORT = process.env.PORT || 3003;

app.use("/static", express.static(path.join(__dirname, "../dist/client")));
app.get("/health", (_req, res) => res.status(200).send("ok"));

app.get("/api/products", async (_req, res) => {
  try {
    const r = await fetch("https://dummyjson.com/products?limit=10");
    const data = await r.json();
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: "upstream_failed" });
  }
});
// Build client bundle (nodemon will restart on changes)
const clientBuild = esbuild.build({
  entryPoints: [path.join(__dirname, "../web/client.tsx")],
  bundle: true,
  outfile: path.join(__dirname, "../dist/client/client.js"),
  platform: "browser",
  format: "iife",
  target: "es2019",
  sourcemap: true,
  define: {
    "process.env.NODE_ENV": JSON.stringify(
      process.env.NODE_ENV || "development"
    ),
  },
  jsx: "automatic",
  loader: {
    ".png": "file",
    ".jpg": "file",
    ".jpeg": "file",
    ".svg": "file",
  },
  assetNames: "assets/[name]-[hash]",
  plugins: [clientAliasPlugin],
});

clientBuild.catch((err) => console.error("Client build failed", err));

const serverOutfile = path.join(__dirname, "../dist/server/server.js");
const serverBuild = esbuild.build({
  entryPoints: [path.join(__dirname, "../web/server-entry.tsx")],
  bundle: true,
  outfile: serverOutfile,
  platform: "node",
  format: "cjs",
  target: "node20",
  jsx: "automatic",
  external: ["react", "react-dom", "react-dom/server"],
  plugins: [serverAliasPlugin],
});

serverBuild.catch((err) => console.error("Server build failed", err));

app.use(async (req, res) => {
  try {
    delete require.cache[serverOutfile];
    const { render } = require(serverOutfile);
    const html = await render(req.url);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.end(html);
  } catch (e) {
    console.error(e);
    res.status(500).send("SSR error");
  }
});

app.listen(PORT, () => console.log(`Cart SSR on http://localhost:${PORT}`));
