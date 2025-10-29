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

  // Clean up the preloaded state from window
  delete (window as any).__PRELOADED_STATE__;

  const root = createRoot(rootEl);
  root.render(<App store={store} />);
}
