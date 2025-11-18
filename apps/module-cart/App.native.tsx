import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { CartScreen } from "@pkg/cart-ui";
import { configureStore, AppStore, loadPersistedState } from "@pkg/state";
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
  // Initialize store immediately - always create synchronously for instant rendering
  // For Expo development, we don't need persisted state
  const [appStore, setAppStore] = React.useState<AppStore>(
    store || configureStore()
  );

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

  const handleProductPress = React.useCallback((productId: string) => {
    if (Platform.OS === "web") {
      // Web navigation - could use React Navigation or window.location
      console.log("Navigate to PDP:", productId);
    } else if (NavigationBridge) {
      // Real native app - use native bridge to navigate to PDP
      NavigationBridge.navigateToPDP(productId);
    } else {
      // Expo Go - just log for now (could add in-app navigation later)
      console.log("Navigate to PDP:", productId, "(Expo Go - NavigationBridge not available)");
    }
  }, []);

  // Always render immediately - no loading state needed since store is created synchronously
  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <CartScreen onProductPress={handleProductPress} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
