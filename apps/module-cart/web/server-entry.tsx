import * as React from "react";
import App from "../App";
import { renderToString } from "react-dom/server";
import { configureStore } from "@pkg/state";
import { upsertProducts } from "@pkg/state";
import { getProducts } from "@pkg/core";

export async function render(_url: string) {
  // Fetch products on the server (needed for cart to display product details)
  const products = await getProducts();

  // Create store and populate with server data
  const store = configureStore();
  store.dispatch(upsertProducts(products));

  // Render with populated store
  const app = renderToString(<App store={store} />);

  // Serialize Redux state for hydration
  const preloadedState = store.getState();

  return `<!DOCTYPE html>
  <html>
    <head>
      <meta charset=\"utf-8\" />
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
      <title>Cart</title>
      <style>
        html, body {
          margin: 0;
          padding: 0;
          height: 100%;
        }
        #root {
          min-height: 100vh;
          display: flex;
          flex-direction: column;
        }
      </style>
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
