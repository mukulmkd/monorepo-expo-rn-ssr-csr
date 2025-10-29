import * as React from "react";
import { Provider } from "react-redux";
import { View, Button } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { CartScreen } from "@pkg/cart-ui";
import { configureStore, AppStore } from "@pkg/state";

type WebAppProps = {
  store?: AppStore;
};

export default function WebApp({ store }: WebAppProps) {
  const [route, setRoute] = React.useState<"products" | "cart">("products");
  // Use provided store or create new one (for client-side hydration)
  const appStore = store || configureStore();

  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ padding: 8, flexDirection: "row", gap: 8 }}>
          <Button title="Products" onPress={() => setRoute("products")} />
          <Button title="Cart" onPress={() => setRoute("cart")} />
        </View>
        <View style={{ flex: 1 }}>
          {route === "products" ? <ProductsScreen /> : <CartScreen />}
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
