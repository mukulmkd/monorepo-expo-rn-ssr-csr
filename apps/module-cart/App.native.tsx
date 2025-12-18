import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform, StyleSheet } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { Header, Footer, Navigation } from "@pkg/ui";
import { CartScreen } from "@pkg/cart-ui";
import {
  configureStore,
  AppStore,
  loadPersistedState,
  setCartItems,
  setProductsItems,
} from "@pkg/state";
import { NativeModules } from "react-native";

type AppProps = {
  store?: AppStore;
};

// Get NavigationBridge from native modules (may be undefined in Expo Go or web)
// Use try-catch to handle cases where NativeModules is not available
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;
}

export default function App({ store }: AppProps) {
  // Initialize store with lazy loading of persisted state
  // For native apps, we'll load persisted state immediately and hydrate
  const [appStore] = React.useState<AppStore>(() => {
    return store || configureStore();
  });

  // Load persisted state immediately on mount (for real native apps only)
  React.useEffect(() => {
    if (store) {
      return; // Store already provided, no need to load persisted state
    }

    // Skip persisted state loading for web or Expo Go
    if (Platform.OS === "web") {
      return;
    }

    // Only load persisted state if NavigationBridge exists (real native app)
    // In Expo Go, NavigationBridge will be undefined, so skip
    if (!NavigationBridge) {
      return; // Skip in Expo Go
    }

    // Load persisted state immediately and hydrate the store
    let mounted = true;
    loadPersistedState()
      .then((persistedState) => {
        if (!mounted) {
          return;
        }

        if (persistedState) {
          // Hydrate store by dispatching actions - this will trigger re-renders
          if (persistedState.cart && persistedState.cart.items) {
            appStore.dispatch(
              setCartItems({ items: persistedState.cart.items })
            );
          }
          if (persistedState.products && persistedState.products.items) {
            appStore.dispatch(
              setProductsItems({ items: persistedState.products.items })
            );
          }
        }
      })
      .catch((error) => {
        // Silently fail - use fresh store
      });

    return () => {
      mounted = false;
    };
  }, [store, appStore]);

  const handleProductPress = React.useCallback((productId: string) => {
    if (Platform.OS === "web") {
      // Web navigation - could use React Navigation or window.location
    } else if (NavigationBridge) {
      // Real native app - use native bridge to navigate to PDP
      NavigationBridge.navigateToPDP(productId);
    }
    // Expo Go - no navigation available
  }, []);

  // Always render immediately - no loading state needed since store is created synchronously
  return (
    <Provider store={appStore}>
      <SafeAreaProvider>
        <SafeAreaView style={{ flex: 1 }} edges={["top", "bottom"]}>
          <View style={{ flex: 1 }}>
            <Header />
            <Navigation />
            <View style={{ flex: 1 }}>
              {/* CartScreen now includes CartSVGThing internally - testing transitive dependency */}
              <CartScreen onProductPress={handleProductPress} />
            </View>
            <Footer />
          </View>
        </SafeAreaView>
      </SafeAreaProvider>
    </Provider>
  );
}
