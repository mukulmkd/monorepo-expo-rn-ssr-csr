import * as React from "react";
import { View, Text, ScrollView, Image, Button } from "react-native";
import { useDispatch, useSelector } from "react-redux";
import { addToCart } from "@pkg/state";
import { selectProductById } from "@pkg/state";
import { getProduct, Product } from "@pkg/core";
import { upsertProduct } from "@pkg/state";

type ProductDetailPageProps = {
  productId: string;
};

export function ProductDetailPage({ productId }: ProductDetailPageProps) {
  const dispatch = useDispatch();
  const product = useSelector((state: any) =>
    selectProductById(state, productId)
  );
  const [loading, setLoading] = React.useState(!product);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!product) {
      setLoading(true);
      getProduct(productId)
        .then((p) => {
          if (p) {
            dispatch(upsertProduct(p));
            setError(null);
          } else {
            setError("Product not found");
          }
        })
        .catch(() => setError("Failed to load product"))
        .finally(() => setLoading(false));
    }
  }, [productId, product, dispatch]);

  const onAddToCart = React.useCallback(() => {
    if (product) {
      dispatch(addToCart({ productId: product.id, quantity: 1 }));
    }
  }, [dispatch, product]);

  if (loading) {
    return (
      <View
        style={{
          flex: 1,
          justifyContent: "center",
          alignItems: "center",
          padding: 32,
        }}
      >
        <Text style={{ fontSize: 18 }}>Loading product...</Text>
      </View>
    );
  }

  if (error || !product) {
    return (
      <View
        style={{
          flex: 1,
          justifyContent: "center",
          alignItems: "center",
          padding: 32,
        }}
      >
        <Text style={{ fontSize: 18, color: "#d32f2f" }}>
          {error || "Product not found"}
        </Text>
      </View>
    );
  }

  return (
    <ScrollView style={{ flex: 1, backgroundColor: "#fff" }}>
      {product.image && (
        <Image
          source={{ uri: product.image }}
          style={{ width: "100%", height: 400 }}
          resizeMode="cover"
        />
      )}
      <View style={{ padding: 24 }}>
        <Text style={{ fontSize: 28, fontWeight: "bold", marginBottom: 8 }}>
          {product.name}
        </Text>
        {product.brand && (
          <Text style={{ fontSize: 16, color: "#666", marginBottom: 8 }}>
            {product.brand}
          </Text>
        )}
        <View
          style={{
            flexDirection: "row",
            alignItems: "center",
            marginBottom: 16,
          }}
        >
          <Text
            style={{
              fontSize: 32,
              fontWeight: "bold",
              color: "#007bff",
              marginRight: 16,
            }}
          >
            ${product.price}
          </Text>
          {product.rating && (
            <View style={{ flexDirection: "row", alignItems: "center" }}>
              <Text style={{ fontSize: 16, marginRight: 4 }}>⭐</Text>
              <Text style={{ fontSize: 16 }}>{product.rating.toFixed(1)}</Text>
            </View>
          )}
        </View>
        {product.description && (
          <View style={{ marginBottom: 24 }}>
            <Text style={{ fontSize: 18, fontWeight: "600", marginBottom: 8 }}>
              Description
            </Text>
            <Text style={{ fontSize: 16, color: "#666", lineHeight: 24 }}>
              {product.description}
            </Text>
          </View>
        )}
        <View style={{ marginTop: 24 }}>
          <Button title="Add to Cart" onPress={onAddToCart} color="#007bff" />
        </View>
      </View>
    </ScrollView>
  );
}
