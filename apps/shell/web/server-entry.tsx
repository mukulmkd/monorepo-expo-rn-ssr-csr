import * as React from "react";
import WebApp from "./WebApp";
import { renderToString } from "react-dom/server";
import { configureStore } from "@pkg/state";
import { upsertProducts } from "@pkg/state";
import { getProducts } from "@pkg/core";

export async function render(url: string) {
  // Fetch products on the server
  const products = await getProducts();

  // Create store and populate with server data
  const store = configureStore();
  store.dispatch(upsertProducts(products));

  // Render with populated store
  const app = renderToString(<WebApp store={store} />);

  // Serialize Redux state for hydration
  const preloadedState = store.getState();

  return `<!DOCTYPE html>
  <html>
    <head>
      <meta charset=\"utf-8\" />
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
      <title>Shell</title>
    </head>
    <body>
      <div id=\"root\">${app}</div>
      <script>
        window.__PRELOADED_STATE__ = ${JSON.stringify(preloadedState)};
      </script>
      <script src=\"/static/client.js\"></script>
    </body>
  </html>`;
}
