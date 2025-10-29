import { createSlice, PayloadAction } from "@reduxjs/toolkit";

export type CartItem = { productId: string; quantity: number };

type CartState = { items: Record<string, CartItem> };

const initialState: CartState = { items: {} };

const slice = createSlice({
  name: "cart",
  initialState,
  reducers: {
    addToCart(
      state,
      action: PayloadAction<{ productId: string; quantity?: number }>
    ) {
      const { productId, quantity = 1 } = action.payload;
      const current = state.items[productId]?.quantity || 0;
      state.items[productId] = { productId, quantity: current + quantity };
    },
    removeFromCart(state, action: PayloadAction<{ productId: string }>) {
      delete state.items[action.payload.productId];
    },
  },
});

export const { addToCart, removeFromCart } = slice.actions;
export const cartReducer = slice.reducer;
