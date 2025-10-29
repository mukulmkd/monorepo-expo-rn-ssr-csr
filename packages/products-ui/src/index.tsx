import * as React from "react";
import { View, Text, Button, ScrollView } from "react-native";
import { useCallback, useEffect } from "react";
import { addToCart, upsertProducts, selectProductsArray } from "@pkg/state";
import { useDispatch, useSelector } from "react-redux";
import { useProducts } from "@pkg/core";

export function ProductsScreen() {
  const dispatch = useDispatch();
  const products = useSelector(selectProductsArray);
  const { data, loading, error } = useProducts();

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

  const displayProducts = products.length > 0 ? products : data || [];

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontSize: 18, marginBottom: 8 }}>Products</Text>
      {loading && products.length === 0 && <Text>Loading products…</Text>}
      {error && products.length === 0 && <Text>Error loading products</Text>}
      {displayProducts.length > 0 && (
        <ScrollView>
          {displayProducts.map((p) => (
            <View key={p.id} style={{ marginBottom: 12 }}>
              <Text>
                {p.name} - ${p.price}
              </Text>
              <Button title="Add to Cart" onPress={onAdd(p.id)} />
            </View>
          ))}
        </ScrollView>
      )}
    </View>
  );
}
