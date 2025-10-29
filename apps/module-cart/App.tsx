import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { CartScreen } from "@pkg/cart-ui";
import { configureStore, AppStore } from "@pkg/state";

type AppProps = {
  store?: AppStore;
};

export default function App({ store }: AppProps) {
  const appStore = store || configureStore();

  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <CartScreen />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
