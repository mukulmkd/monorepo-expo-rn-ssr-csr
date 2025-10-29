import * as React from "react";
import WebApp from "./WebApp";
import { renderToString } from "react-dom/server";
import { configureStore } from "@pkg/state";
import { upsertProducts } from "@pkg/state";
import { getProducts } from "@pkg/core";

function parseUrl(url: string): { route: string; productId: string | null } {
  const urlObj = new URL(url, "http://localhost");
  const path = urlObj.pathname;
  const productId = urlObj.searchParams.get("productId");

  if (path === "/cart") {
    return { route: "cart", productId: null };
  } else if (path === "/plp") {
    return { route: "products", productId: null };
  } else if (path === "/pdp" && productId) {
    return { route: "product", productId };
  } else if (path === "/home" || path === "/") {
    return { route: "home", productId: null };
  }

  // Default to home
  return { route: "home", productId: null };
}

export async function render(url: string) {
  // Parse URL to determine route and productId
  const { route, productId } = parseUrl(url);

  // Fetch products on the server
  const products = await getProducts();

  // Create store and populate with server data
  const store = configureStore();
  store.dispatch(upsertProducts(products));

  // Render with populated store and route info
  const app = renderToString(
    <WebApp store={store} initialRoute={route} initialProductId={productId} />
  );

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
