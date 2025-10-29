import * as React from "react";
import { View, Text } from "react-native";
import { useSelector } from "react-redux";

type RootState = {
  cart: { items: Record<string, { productId: string; quantity: number }> };
};

export function CartScreen() {
  const items = useSelector((s: RootState) => s.cart.items);
  const count = Object.values(items).reduce((acc, it) => acc + it.quantity, 0);
  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontSize: 18, marginBottom: 8 }}>Cart</Text>
      <Text>Items in cart: {count}</Text>
    </View>
  );
}
