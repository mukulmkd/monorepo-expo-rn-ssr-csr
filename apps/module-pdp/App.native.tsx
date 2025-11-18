import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore, loadPersistedState } from "@pkg/state";
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
  // Initialize store immediately - always create synchronously for instant rendering
  // For Expo development, we don't need persisted state
  const [appStore, setAppStore] = React.useState<AppStore>(
    store || configureStore()
  );

  // Get productId from initial props (passed from native)
  const productId = initialProductId || "1";

  // Optionally load persisted state in the background (for real native apps only)
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

    // Load persisted state asynchronously for native apps only
    // This happens in the background and updates the store if needed
    let mounted = true;
    loadPersistedState()
      .then((persistedState) => {
        if (mounted && persistedState) {
          // Recreate store with persisted state
          setAppStore(configureStore(persistedState));
        }
      })
      .catch((error) => {
        console.warn(
          "Failed to load persisted state, using fresh store:",
          error
        );
      });

    return () => {
      mounted = false;
    };
  }, [store]);

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
