import * as React from "react";
import { View, Text, ScrollView, TouchableOpacity } from "react-native";
import { useNavigation } from "@pkg/ui";

type HomepageProps = {
  onProductPress?: (productId: string) => void;
};

export function Homepage({ onProductPress }: HomepageProps) {
  const navigation = useNavigation();

  return (
    <ScrollView style={{ flex: 1, backgroundColor: "#f5f5f5" }}>
      {/* Hero Section */}
      <View
        style={{
          backgroundColor: "#1a1a1a",
          padding: 32,
          alignItems: "center",
        }}
      >
        <Text
          style={{
            color: "#fff",
            fontSize: 32,
            fontWeight: "bold",
            marginBottom: 8,
          }}
        >
          Welcome to MyShopApp
        </Text>
        <Text
          style={{
            color: "#ccc",
            fontSize: 16,
            marginBottom: 24,
            textAlign: "center",
          }}
        >
          Discover amazing products and great deals
        </Text>
        <TouchableOpacity
          onPress={() => navigation.navigate("products")}
          style={{
            backgroundColor: "#007bff",
            paddingHorizontal: 24,
            paddingVertical: 12,
            borderRadius: 8,
          }}
          activeOpacity={0.7}
        >
          <Text
            style={{
              color: "#fff",
              fontSize: 16,
              fontWeight: "600",
            }}
          >
            Go to PLP
          </Text>
        </TouchableOpacity>
      </View>

      {/* Additional Content Section */}
      <View style={{ padding: 32, alignItems: "center" }}>
        <Text
          style={{
            fontSize: 20,
            fontWeight: "600",
            marginBottom: 16,
            textAlign: "center",
          }}
        >
          Start Shopping
        </Text>
        <Text
          style={{
            fontSize: 14,
            color: "#666",
            textAlign: "center",
            lineHeight: 22,
          }}
        >
          Browse our wide selection of products. Click the button above or use
          the navigation menu to explore our product catalog.
        </Text>
      </View>
    </ScrollView>
  );
}
