import * as React from "react";
import { View, Text } from "react-native";

export function Footer() {
  return (
    <View
      style={{
        backgroundColor: "#1a1a1a",
        paddingVertical: 24,
        paddingHorizontal: 24,
        borderTopWidth: 1,
        borderTopColor: "#333",
      }}
    >
      <View
        style={{
          borderTopWidth: 1,
          borderTopColor: "#333",
          marginTop: 16,
          paddingTop: 16,
          alignItems: "center",
        }}
      >
        <Text style={{ color: "#aaa", fontSize: 12 }}>
          © 2025 MyShopApp. All rights reserved.
        </Text>
      </View>
    </View>
  );
}
