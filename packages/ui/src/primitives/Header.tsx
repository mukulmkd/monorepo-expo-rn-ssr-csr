import * as React from "react";
import { View, Text } from "react-native";

export function Header() {
  return (
    <View style={{ padding: 16, backgroundColor: "#111" }}>
      <Text style={{ color: "#fff", fontSize: 18 }}>Shared Header</Text>
    </View>
  );
}
