import * as React from "react";
import {
  View,
  Text,
  Button,
  ScrollView,
  Image,
  TouchableOpacity,
  Platform,
  useWindowDimensions,
} from "react-native";
import { useCallback, useEffect } from "react";
import { addToCart, upsertProducts, selectProductsArray } from "@pkg/state";
import { useDispatch, useSelector } from "react-redux";
import { useProducts, type Product } from "@pkg/core";

type ProductsScreenProps = {
  onProductPress?: (productId: string) => void;
};

export function ProductsScreen({ onProductPress }: ProductsScreenProps) {
  const dispatch = useDispatch();
  const products = useSelector(selectProductsArray) as Product[];
  const { data, loading, error } = useProducts();
  const { width } = useWindowDimensions();

  // Determine card width: 4 cards on web (desktop), 2 cards on mobile
  const isWeb = Platform.OS === "web";
  const isDesktop = isWeb && width >= 768;
  const cardWidth = isDesktop ? "23%" : "47%"; // 4 cards on desktop, 2 on mobile

  // If products are empty in store, fetch them (client-side fallback)
  useEffect(() => {
    if (products.length === 0 && data) {
      dispatch(upsertProducts(data));
    }
  }, [data, products.length, dispatch]);

  const onAdd = useCallback(
    (productId: string) => () => {
      dispatch(addToCart({ productId, quantity: 1 }));
    },
    [dispatch]
  );

  const displayProducts: Product[] =
    products.length > 0 ? products : data ?? [];

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
        <Text style={{ fontSize: 28, fontWeight: "bold" }}>Products</Text>
      </View>
      {loading && products.length === 0 && (
        <View
          style={{ flex: 1, justifyContent: "center", alignItems: "center" }}
        >
          <Text style={{ fontSize: 16, color: "#666" }}>Loading products…</Text>
        </View>
      )}
      {error && products.length === 0 && (
        <View
          style={{ flex: 1, justifyContent: "center", alignItems: "center" }}
        >
          <Text style={{ fontSize: 16, color: "#d32f2f" }}>
            Error loading products
          </Text>
        </View>
      )}
      {displayProducts.length > 0 && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 16 }}>
            {displayProducts.map((p: Product) => (
              <TouchableOpacity
                key={p.id}
                onPress={() => onProductPress?.(p.id)}
                style={{
                  backgroundColor: "#fff",
                  borderRadius: 12,
                  width: cardWidth,
                  padding: 12,
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
                  marginBottom: 16,
                }}
              >
                {p.image && (
                  <Image
                    source={{ uri: p.image }}
                    style={{
                      width: "100%",
                      height: 180,
                      borderRadius: 8,
                      marginBottom: 12,
                    }}
                    resizeMode="cover"
                  />
                )}
                <Text
                  style={{ fontSize: 16, fontWeight: "600", marginBottom: 4 }}
                  numberOfLines={2}
                >
                  {p.name}
                </Text>
                {p.brand && (
                  <Text
                    style={{ fontSize: 12, color: "#666", marginBottom: 4 }}
                  >
                    {p.brand}
                  </Text>
                )}
                <View
                  style={{
                    flexDirection: "row",
                    justifyContent: "space-between",
                    alignItems: "center",
                    marginTop: 8,
                  }}
                >
                  <Text
                    style={{
                      fontSize: 20,
                      fontWeight: "bold",
                      color: "#007bff",
                    }}
                  >
                    ${p.price}
                  </Text>
                  {p.rating && (
                    <View
                      style={{ flexDirection: "row", alignItems: "center" }}
                    >
                      <Text style={{ fontSize: 12, marginRight: 4 }}>⭐</Text>
                      <Text style={{ fontSize: 12 }}>
                        {p.rating.toFixed(1)}
                      </Text>
                    </View>
                  )}
                </View>
                <Button
                  title="Add to Cart"
                  onPress={onAdd(p.id)}
                  color="#007bff"
                />
              </TouchableOpacity>
            ))}
          </View>
        </ScrollView>
      )}
    </View>
  );
}
