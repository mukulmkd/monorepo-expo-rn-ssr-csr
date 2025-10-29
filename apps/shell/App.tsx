import React, { useRef, useCallback, useMemo } from "react";
import { Provider } from "react-redux";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { View, Platform, Text } from "react-native";
import { configureStore } from "@pkg/state";
import { Header, Footer, Navigation, NavigationContext } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { CartScreen } from "@pkg/cart-ui";
import { Homepage } from "@pkg/homepage-ui";
import { ProductDetailScreen } from "./screens/ProductDetailScreen";

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();
const store = configureStore();

// Wrapper components to pass onProductPress prop to screens
function HomepageWrapper() {
  const navigationContext = React.useContext(NavigationContext);
  const handleProductPress = useCallback(
    (productId: string) => {
      if (navigationContext) {
        navigationContext.navigate("product", { productId });
      }
    },
    [navigationContext]
  );
  return <Homepage onProductPress={handleProductPress} />;
}

function ProductsScreenWrapper() {
  const navigationContext = React.useContext(NavigationContext);
  const handleProductPress = useCallback(
    (productId: string) => {
      if (navigationContext) {
        navigationContext.navigate("product", { productId });
      }
    },
    [navigationContext]
  );
  return <ProductsScreen onProductPress={handleProductPress} />;
}

function CartScreenWrapper() {
  const navigationContext = React.useContext(NavigationContext);
  const handleProductPress = useCallback(
    (productId: string) => {
      if (navigationContext) {
        navigationContext.navigate("product", { productId });
      }
    },
    [navigationContext]
  );
  return <CartScreen onProductPress={handleProductPress} />;
}

// Bottom Tab Navigator for mobile (Home, Products, Cart)
function BottomTabNavigator() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: "#007bff",
        tabBarInactiveTintColor: "#666",
        tabBarStyle: {
          backgroundColor: "#fff",
          borderTopWidth: 1,
          borderTopColor: "#e0e0e0",
          paddingBottom: 8,
          paddingTop: 8,
          height: 60,
        },
      }}
    >
      <Tab.Screen
        name="HomeTab"
        component={HomepageWrapper}
        options={{
          tabBarLabel: "Home",
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>🏠</Text>,
        }}
      />
      <Tab.Screen
        name="ProductsTab"
        component={ProductsScreenWrapper}
        options={{
          tabBarLabel: "Products",
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>🛍️</Text>,
        }}
      />
      <Tab.Screen
        name="CartTab"
        component={CartScreenWrapper}
        options={{
          tabBarLabel: "Cart",
          tabBarIcon: () => <Text style={{ fontSize: 20 }}>🛒</Text>,
        }}
      />
    </Tab.Navigator>
  );
}

// Main Stack Navigator (includes tabs + product detail)
function MainNavigator() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="MainTabs"
        component={BottomTabNavigator}
        options={{ headerShown: false }}
      />
      <Stack.Screen
        name="Product"
        component={ProductDetailScreen}
        options={{ headerShown: false }}
      />
    </Stack.Navigator>
  );
}

export default function App() {
  // For native apps, use React Navigation
  const navigationRef = useRef<any>(null);

  const navigate = useCallback((route: string, params?: any) => {
    if (navigationRef.current?.isReady()) {
      if (route === "cart") {
        navigationRef.current.navigate("MainTabs", { screen: "CartTab" });
      } else if (route === "products") {
        navigationRef.current.navigate("MainTabs", { screen: "ProductsTab" });
      } else if (route === "product" && params?.productId) {
        navigationRef.current.navigate("Product", {
          productId: params.productId,
        });
      } else if (route === "home") {
        navigationRef.current.navigate("MainTabs", { screen: "HomeTab" });
      } else {
        navigationRef.current.navigate(route);
      }
    }
  }, []);

  const canGoBack = useCallback(() => {
    return navigationRef.current?.canGoBack() || false;
  }, []);

  const goBack = useCallback(() => {
    if (navigationRef.current?.canGoBack()) {
      navigationRef.current.goBack();
    }
  }, []);

  const navigationContextValue = useMemo(
    () => ({ navigate, canGoBack, goBack }),
    [navigate, canGoBack, goBack]
  );

  return (
    <SafeAreaProvider>
      <Provider store={store}>
        <NavigationContext.Provider value={navigationContextValue}>
          <SafeAreaView style={{ flex: 1 }} edges={["top", "bottom"]}>
            <View style={{ flex: 1 }}>
              <Header />
              {/* Hide top Navigation on mobile - bottom tabs handle navigation */}
              {Platform.OS === "web" && <Navigation />}
              <View style={{ flex: 1 }}>
                <NavigationContainer ref={navigationRef}>
                  <MainNavigator />
                </NavigationContainer>
              </View>
              {Platform.OS === "web" && <Footer />}
            </View>
          </SafeAreaView>
        </NavigationContext.Provider>
      </Provider>
    </SafeAreaProvider>
  );
}
