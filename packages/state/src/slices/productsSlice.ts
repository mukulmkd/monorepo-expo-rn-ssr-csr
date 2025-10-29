import { createSlice, PayloadAction, createSelector } from "@reduxjs/toolkit";

export type Product = { id: string; name: string; price: number };

type ProductsState = { items: Record<string, Product> };

const initialState: ProductsState = { items: {} };

const slice = createSlice({
  name: "products",
  initialState,
  reducers: {
    upsertProducts(state, action: PayloadAction<Product[]>) {
      for (const p of action.payload) state.items[p.id] = p;
    },
  },
});

export const { upsertProducts } = slice.actions;
export const productsReducer = slice.reducer;

// Memoized selector to get products as array
// Using any to avoid circular dependency with AppState
export const selectProductsArray = createSelector(
  [(state: any) => state.products.items],
  (items) => Object.values(items)
);
