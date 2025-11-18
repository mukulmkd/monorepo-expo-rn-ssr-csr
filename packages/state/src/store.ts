import {
  combineReducers,
  configureStore as rtkConfigureStore,
  Middleware,
} from "@reduxjs/toolkit";
import { cartReducer } from "./slices/cartSlice";
import { productsReducer } from "./slices/productsSlice";
import { saveCartState, saveProductsState } from "./persistence";

const rootReducer = combineReducers({
  cart: cartReducer,
  products: productsReducer,
});

export type AppState = ReturnType<typeof rootReducer>;

export type AppPreloadedState = Partial<AppState>;

// Middleware to persist cart and products state
const persistenceMiddleware: Middleware =
  (store) => (next) => (action: any) => {
    const result = next(action);
    const state = store.getState() as AppState;

    // Persist cart state whenever it changes
    if (action?.type?.startsWith("cart/")) {
      saveCartState(state.cart).catch(() => {
        // Failed to persist cart state
      });
    }

    // Persist products state whenever it changes
    if (action?.type?.startsWith("products/")) {
      saveProductsState(state.products).catch(() => {
        // Failed to persist products state
      });
    }

    return result;
  };

export function configureStore(preloadedState?: AppPreloadedState) {
  return rtkConfigureStore({
    reducer: rootReducer,
    preloadedState: preloadedState as AppState | undefined,
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware().concat(persistenceMiddleware),
  });
}

export type AppStore = ReturnType<typeof configureStore>;
