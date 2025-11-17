import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore, loadPersistedState } from "@pkg/state";
import { NativeModules, Platform } from "react-native";

type AppProps = {
  store?: AppStore;
  productId?: string;
};

// Get NavigationBridge from native modules
const NavigationBridge = NativeModules.NavigationBridge;

export default function App({ store, productId: initialProductId }: AppProps) {
  const [appStore, setAppStore] = React.useState<AppStore | null>(null);

  // Get productId from initial props (passed from native)
  const productId = initialProductId || "1";

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
          <ProductDetailPage productId={productId} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
