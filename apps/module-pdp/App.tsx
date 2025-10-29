import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore } from "@pkg/state";

type AppProps = {
  store?: AppStore;
  productId?: string;
};

export default function App({ store, productId: initialProductId }: AppProps) {
  const appStore = store || configureStore();

  // Extract productId from URL query params for web, or use prop/default
  const [productId, setProductId] = React.useState<string>(
    initialProductId || "1"
  );

  React.useEffect(() => {
    if (typeof window !== "undefined") {
      // Get productId from URL or window global
      const params = new URLSearchParams(window.location.search);
      const id =
        params.get("productId") ||
        (window as any).__PRODUCT_ID__ ||
        initialProductId ||
        "1";
      setProductId(id);
    }
  }, [initialProductId]);

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
