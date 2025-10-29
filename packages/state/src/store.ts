import { configureStore as rtkConfigureStore } from "@reduxjs/toolkit";
import { cartReducer } from "./slices/cartSlice";
import { productsReducer } from "./slices/productsSlice";

export function configureStore(preloadedState?: any) {
  return rtkConfigureStore({
    reducer: {
      cart: cartReducer,
      products: productsReducer,
    },
    preloadedState,
  });
}

export type AppStore = ReturnType<typeof configureStore>;
export type AppState = ReturnType<
  ReturnType<typeof configureStore>["getState"]
>;
