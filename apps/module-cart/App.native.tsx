import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { CartScreen } from "@pkg/cart-ui";
import { configureStore, AppStore, loadPersistedState } from "@pkg/state";
import { NativeModules, Platform } from "react-native";

type AppProps = {
  store?: AppStore;
};

// Get NavigationBridge from native modules
const NavigationBridge = NativeModules.NavigationBridge;

export default function App({ store }: AppProps) {
  const [appStore, setAppStore] = React.useState<AppStore | null>(null);

  // Load persisted state and create store
  React.useEffect(() => {
    if (store) {
      setAppStore(store);
      return;
    }

    let mounted = true;
    loadPersistedState()
      .then((persistedState) => {
        if (mounted) {
          setAppStore(configureStore(persistedState || undefined));
        }
      })
      .catch((error) => {
        console.warn(
          "Failed to load persisted state, using fresh store:",
          error
        );
        if (mounted) {
          setAppStore(configureStore());
        }
      });

    return () => {
      mounted = false;
    };
  }, [store]);

  const handleProductPress = React.useCallback((productId: string) => {
    if (Platform.OS !== "web" && NavigationBridge) {
      // Use native bridge to navigate to PDP
      NavigationBridge.navigateToPDP(productId);
    } else {
      // Web navigation - could use React Navigation or window.location
      console.log("Navigate to PDP:", productId);
    }
  }, []);

  // All hooks must be called before conditional returns
  if (!appStore) {
    return (
      <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
        {/* Loading state - all hooks have been called */}
      </View>
    );
  }

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
