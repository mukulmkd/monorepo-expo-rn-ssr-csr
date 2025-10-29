import * as React from "react";
import { View, Text, TouchableOpacity, Platform } from "react-native";
import { useSelector } from "react-redux";
import { useNavigation } from "../NavigationContext";

type RootState = {
  cart: { items: Record<string, { productId: string; quantity: number }> };
};

type HeaderProps = {
  onCartPress?: () => void;
};

export function Header({ onCartPress }: HeaderProps) {
  const cartItems = useSelector((state: RootState) => state.cart.items);
  const cartCount = Object.values(cartItems).reduce(
    (acc, it) => acc + it.quantity,
    0
  );
  const navigation = useNavigation();

  // For mobile, check if we can go back
  const [canGoBack, setCanGoBack] = React.useState(false);

  // Check if we can go back (for mobile)
  React.useEffect(() => {
    if (Platform.OS !== "web" && navigation.canGoBack) {
      const checkCanGoBack = () => {
        setCanGoBack(navigation.canGoBack?.() || false);
      };
      checkCanGoBack();
      // Check periodically to update back button visibility
      const interval = setInterval(checkCanGoBack, 100);
      return () => clearInterval(interval);
    }
  }, [navigation]);

  const handleCartButtonPress = React.useCallback(() => {
    if (onCartPress) {
      onCartPress();
    } else {
      navigation.navigate("cart");
    }
  }, [onCartPress, navigation]);

  const handleBackPress = React.useCallback(() => {
    if (Platform.OS !== "web" && canGoBack && navigation.goBack) {
      navigation.goBack();
    }
  }, [canGoBack, navigation]);

  return (
    <View
      style={{
        backgroundColor: "#1a1a1a",
        paddingVertical: 16,
        paddingHorizontal: 24,
        borderBottomWidth: 1,
        borderBottomColor: "#333",
      }}
    >
      <View
        style={{
          flexDirection: "row",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
          {Platform.OS !== "web" && canGoBack && (
            <TouchableOpacity
              onPress={handleBackPress}
              activeOpacity={0.7}
              style={{ paddingRight: 8 }}
            >
              <Text style={{ color: "#fff", fontSize: 24 }}>←</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity
            onPress={() => navigation.navigate("home")}
            activeOpacity={0.7}
          >
            <Text style={{ color: "#fff", fontSize: 24, fontWeight: "bold" }}>
              MyShopApp
            </Text>
          </TouchableOpacity>
        </View>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 16 }}>
          <TouchableOpacity
            onPress={handleCartButtonPress}
            style={{
              backgroundColor: "#007bff",
              paddingHorizontal: 16,
              paddingVertical: 8,
              borderRadius: 6,
              flexDirection: "row",
              alignItems: "center",
              cursor: "pointer",
            }}
            activeOpacity={0.7}
          >
            <Text
              style={{
                color: "#fff",
                fontSize: 14,
                fontWeight: "600",
                marginRight: 8,
              }}
            >
              Cart
            </Text>
            {cartCount > 0 && (
              <View
                style={{
                  backgroundColor: "#fff",
                  borderRadius: 10,
                  paddingHorizontal: 6,
                  paddingVertical: 2,
                  minWidth: 20,
                  alignItems: "center",
                }}
              >
                <Text
                  style={{ color: "#007bff", fontSize: 12, fontWeight: "bold" }}
                >
                  {cartCount}
                </Text>
              </View>
            )}
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}
