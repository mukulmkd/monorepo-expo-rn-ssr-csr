import * as React from "react";
import { View, Text, TouchableOpacity, Platform } from "react-native";
import { useNavigation } from "../NavigationContext";

type NavigationItem = {
  label: string;
  items?: string[];
};

type NavigationProps = {
  onNavigate?: (path: string) => void;
};

export function Navigation({ onNavigate }: NavigationProps) {
  const [activeDropdown, setActiveDropdown] = React.useState<string | null>(
    null
  );
  const navigation = useNavigation();

  const navItems: NavigationItem[] = [
    {
      label: "Home",
    },
    {
      label: "Products",
      items: ["All Products", "Electronics", "Fashion", "Home & Garden"],
    },
    {
      label: "Categories",
      items: ["Men", "Women", "Kids", "Accessories"],
    },
    {
      label: "Deals",
      items: ["Flash Sale", "Clearance", "New Arrivals"],
    },
    {
      label: "About",
    },
  ];

  const handlePress = (label: string) => {
    const route =
      label === "Home"
        ? "home"
        : label === "Products" || label === "All Products"
        ? "products"
        : label.toLowerCase();

    if (onNavigate) {
      onNavigate(route);
    } else {
      navigation.navigate(route);
    }
    setActiveDropdown(null);
  };

  return (
    <View
      style={{
        backgroundColor: "#2a2a2a",
        paddingVertical: 12,
        paddingHorizontal: 24,
        borderBottomWidth: 1,
        borderBottomColor: "#333",
      }}
    >
      <View style={{ flexDirection: "row", gap: 24, flexWrap: "wrap" }}>
        {navItems.map((item) => (
          <View key={item.label} style={{ position: "relative" }}>
            <TouchableOpacity
              onPress={() => {
                if (item.items) {
                  setActiveDropdown(
                    activeDropdown === item.label ? null : item.label
                  );
                } else {
                  handlePress(item.label);
                }
              }}
              style={{
                paddingVertical: 8,
                paddingHorizontal: 12,
                borderRadius: 4,
              }}
            >
              <Text style={{ color: "#fff", fontSize: 14, fontWeight: "500" }}>
                {item.label} {item.items ? "▼" : ""}
              </Text>
            </TouchableOpacity>
            {activeDropdown === item.label && item.items && (
              <View
                style={{
                  position: "absolute",
                  top: "100%",
                  left: 0,
                  backgroundColor: "#fff",
                  borderRadius: 8,
                  padding: 8,
                  minWidth: 180,
                  marginTop: 4,
                  ...(Platform.OS === "web"
                    ? {
                        boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)",
                      }
                    : {
                        shadowColor: "#000",
                        shadowOffset: { width: 0, height: 2 },
                        shadowOpacity: 0.2,
                        shadowRadius: 4,
                        elevation: 5,
                      }),
                  zIndex: 1000,
                }}
              >
                {item.items.map((subItem) => (
                  <TouchableOpacity
                    key={subItem}
                    onPress={() => {
                      handlePress(subItem);
                      setActiveDropdown(null);
                    }}
                    style={{
                      paddingVertical: 10,
                      paddingHorizontal: 12,
                      borderRadius: 4,
                    }}
                  >
                    <Text style={{ color: "#333", fontSize: 14 }}>
                      {subItem}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            )}
          </View>
        ))}
      </View>
      {/* Overlay to close dropdown when clicking outside */}
      {activeDropdown && (
        <TouchableOpacity
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 999,
          }}
          onPress={() => setActiveDropdown(null)}
          activeOpacity={1}
        />
      )}
    </View>
  );
}
