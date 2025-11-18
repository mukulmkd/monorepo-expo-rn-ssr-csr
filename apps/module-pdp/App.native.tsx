import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore, loadPersistedState, setCartItems, setProductsItems } from "@pkg/state";
import { NativeModules } from "react-native";

type AppProps = {
  store?: AppStore;
  productId?: string;
};

// Get NavigationBridge from native modules (may be undefined in Expo Go or web)
// Use try-catch to handle cases where NativeModules is not available
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;
}

export default function App({ store, productId: initialProductId }: AppProps) {
  // Initialize store with lazy loading of persisted state
  // For native apps, we'll load persisted state immediately and hydrate
  const [appStore] = React.useState<AppStore>(() => {
    return store || configureStore();
  });

  // Get productId from initial props (passed from native)
  const productId = initialProductId || "1";

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
        if (mounted && persistedState) {
          // Hydrate store by dispatching actions - this will trigger re-renders
          if (persistedState.cart && persistedState.cart.items) {
            appStore.dispatch(setCartItems({ items: persistedState.cart.items }));
          }
          if (persistedState.products && persistedState.products.items) {
            appStore.dispatch(setProductsItems({ items: persistedState.products.items }));
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

  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <ProductDetailPage productId={productId} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
