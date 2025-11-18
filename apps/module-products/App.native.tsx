import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform, DeviceEventEmitter } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
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

  // Function to load and hydrate persisted state
  const loadAndHydrateState = React.useCallback(() => {
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
    loadPersistedState()
      .then((persistedState) => {
        if (persistedState) {
          // Hydrate store by dispatching actions - this will trigger re-renders
          if (persistedState.cart && persistedState.cart.items) {
            appStore.dispatch(
              setCartItems({ items: persistedState.cart.items })
            );
          } else {
            // Clear cart if no persisted items
            appStore.dispatch(setCartItems({ items: {} }));
          }
          if (persistedState.products && persistedState.products.items) {
            appStore.dispatch(
              setProductsItems({ items: persistedState.products.items })
            );
          }
        } else {
          // Clear cart if no persisted state
          appStore.dispatch(setCartItems({ items: {} }));
        }
      })
      .catch((error) => {
        // Silently fail - use fresh store
      });
  }, [store, appStore]);

  // Load persisted state immediately on mount (for real native apps only)
  React.useEffect(() => {
    loadAndHydrateState();
  }, [loadAndHydrateState]);

  // Listen for reload event from native side (when view appears)
  React.useEffect(() => {
    if (Platform.OS === "web" || !NavigationBridge) {
      return; // Skip for web or Expo Go
    }

    // Listen for native event to reload state
    const subscription = DeviceEventEmitter.addListener(
      "ReloadPersistedState",
      () => {
        loadAndHydrateState();
      }
    );

    return () => {
      subscription.remove();
    };
  }, [loadAndHydrateState]);

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
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <ProductsScreen onProductPress={handleProductPress} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
