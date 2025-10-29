import { createSlice, PayloadAction, createSelector } from "@reduxjs/toolkit";
import type { Product } from "@pkg/core";

type ProductsState = { items: Record<string, Product> };

const initialState: ProductsState = { items: {} };

const slice = createSlice({
  name: "products",
  initialState,
  reducers: {
    upsertProducts(state, action: PayloadAction<Product[]>) {
      for (const p of action.payload) state.items[p.id] = p;
    },
    upsertProduct(state, action: PayloadAction<Product>) {
      state.items[action.payload.id] = action.payload;
    },
  },
});

export const { upsertProducts, upsertProduct } = slice.actions;
export const productsReducer = slice.reducer;

// Memoized selector to get products as array
// Using any to avoid circular dependency with AppState
export const selectProductsArray = createSelector(
  [(state: any) => state.products.items],
  (items) => Object.values(items)
);

export const selectProductById = (state: any, id: string) =>
  state.products.items[id];
