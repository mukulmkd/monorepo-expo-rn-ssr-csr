import * as React from "react";
import {
  View,
  Text,
  ScrollView,
  Image,
  TouchableOpacity,
  Button,
  Platform,
} from "react-native";
import { useSelector, useDispatch } from "react-redux";
import { removeFromCart } from "@pkg/state";
import type { AppState } from "@pkg/state";

type CartScreenProps = {
  onProductPress?: (productId: string) => void;
};

export function CartScreen({ onProductPress }: CartScreenProps) {
  const dispatch = useDispatch();
  const cartItems = useSelector((state: AppState) => state.cart.items);
  const products = useSelector((state: AppState) => state.products.items);
  const items = Object.values(cartItems);

  const total = React.useMemo(() => {
    return items.reduce((acc, item) => {
      const product = products[item.productId];
      return acc + (product ? product.price * item.quantity : 0);
    }, 0);
  }, [items, products]);

  if (items.length === 0) {
    return (
      <View
        style={{
          flex: 1,
          justifyContent: "center",
          alignItems: "center",
          padding: 32,
        }}
      >
        <Text style={{ fontSize: 24, fontWeight: "bold", marginBottom: 8 }}>
          Your Cart is Empty
        </Text>
        <Text style={{ fontSize: 16, color: "#666", textAlign: "center" }}>
          Add some products to get started!
        </Text>
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: "#f5f5f5" }}>
      <View
        style={{
          padding: 16,
          backgroundColor: "#fff",
          borderBottomWidth: 1,
          borderBottomColor: "#e0e0e0",
        }}
      >
        <Text style={{ fontSize: 28, fontWeight: "bold" }}>Shopping Cart</Text>
        <Text style={{ fontSize: 16, color: "#666", marginTop: 4 }}>
          {items.length} item{items.length !== 1 ? "s" : ""}
        </Text>
      </View>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
        {items.map((item) => {
          const product = products[item.productId];
          if (!product) return null;

          return (
            <View
              key={item.productId}
              style={{
                backgroundColor: "#fff",
                borderRadius: 12,
                padding: 16,
                marginBottom: 12,
                flexDirection: "row",
                ...(Platform.OS === "web"
                  ? {
                      boxShadow: "0 2px 4px rgba(0, 0, 0, 0.1)",
                    }
                  : {
                      shadowColor: "#000",
                      shadowOffset: { width: 0, height: 2 },
                      shadowOpacity: 0.1,
                      shadowRadius: 4,
                      elevation: 3,
                    }),
              }}
            >
              {product.image && (
                <TouchableOpacity
                  onPress={() => onProductPress?.(item.productId)}
                  style={{ marginRight: 16 }}
                >
                  <Image
                    source={{ uri: product.image }}
                    style={{ width: 100, height: 100, borderRadius: 8 }}
                    resizeMode="cover"
                  />
                </TouchableOpacity>
              )}
              <View style={{ flex: 1 }}>
                <TouchableOpacity
                  onPress={() => onProductPress?.(item.productId)}
                >
                  <Text
                    style={{ fontSize: 18, fontWeight: "600", marginBottom: 4 }}
                  >
                    {product.name}
                  </Text>
                </TouchableOpacity>
                <Text style={{ fontSize: 14, color: "#666", marginBottom: 8 }}>
                  ${product.price} each
                </Text>
                <View
                  style={{
                    flexDirection: "row",
                    justifyContent: "space-between",
                    alignItems: "center",
                  }}
                >
                  <Text style={{ fontSize: 16, fontWeight: "600" }}>
                    Qty: {item.quantity} × ${product.price} = $
                    {(product.price * item.quantity).toFixed(2)}
                  </Text>
                  <Button
                    title="Remove"
                    onPress={() =>
                      dispatch(removeFromCart({ productId: item.productId }))
                    }
                    color="#d32f2f"
                  />
                </View>
              </View>
            </View>
          );
        })}
      </ScrollView>
      <View
        style={{
          backgroundColor: "#fff",
          padding: 24,
          borderTopWidth: 1,
          borderTopColor: "#e0e0e0",
        }}
      >
        <View
          style={{
            flexDirection: "row",
            justifyContent: "space-between",
            marginBottom: 16,
          }}
        >
          <Text style={{ fontSize: 20, fontWeight: "600" }}>Total:</Text>
          <Text style={{ fontSize: 24, fontWeight: "bold", color: "#007bff" }}>
            ${total.toFixed(2)}
          </Text>
        </View>
        <Button title="Place Order" onPress={() => {}} color="#007bff" />
      </View>
    </View>
  );
}
