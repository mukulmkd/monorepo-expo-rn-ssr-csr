import * as React from "react";
import { createRoot } from "react-dom/client";
import App from "../App";
import { configureStore } from "@pkg/state";
import { AppState } from "@pkg/state";

const rootEl = document.getElementById("root");
if (rootEl) {
  // Hydrate store with server-rendered state
  const preloadedState = (window as any).__PRELOADED_STATE__ as
    | AppState
    | undefined;
  const store = preloadedState
    ? configureStore(preloadedState)
    : configureStore();

  // Get productId from window global or URL
  const productId =
    (window as any).__PRODUCT_ID__ ||
    new URLSearchParams(window.location.search).get("productId") ||
    "1";

  // Clean up the preloaded state from window
  delete (window as any).__PRELOADED_STATE__;
  delete (window as any).__PRODUCT_ID__;

  const root = createRoot(rootEl);
  root.render(<App store={store} productId={productId} />);
}
