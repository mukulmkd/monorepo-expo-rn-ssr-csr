import * as React from "react";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { useRoute } from "@react-navigation/native";

// Wrapper component for React Navigation
export function ProductDetailScreen() {
  const route = useRoute();
  const productId = (route.params as any)?.productId || "1";
  return <ProductDetailPage productId={productId} />;
}
