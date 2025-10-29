import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore } from "@pkg/state";
import { AppState } from "@pkg/state";

// For standalone PDP module, get productId from URL params or use a default
// In a real app, this would come from navigation params or URL
export default function App() {
  // Extract productId from URL query params for web, or use a default
  const [productId, setProductId] = React.useState<string>("1");
  const [store] = React.useState<AppStore>(() => {
    // Initialize store from preloaded state if available
    if (typeof window !== "undefined") {
      const preloadedState = (window as any).__PRELOADED_STATE__ as
        | AppState
        | undefined;
      if (preloadedState) {
        const s = configureStore(preloadedState);
        delete (window as any).__PRELOADED_STATE__;
        return s;
      }
    }
    return configureStore();
  });

  React.useEffect(() => {
    if (typeof window !== "undefined") {
      // Get productId from URL or window global
      const params = new URLSearchParams(window.location.search);
      const id =
        params.get("productId") || (window as any).__PRODUCT_ID__ || "1";
      setProductId(id);
    }
  }, []);

  return (
    <Provider store={store}>
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
