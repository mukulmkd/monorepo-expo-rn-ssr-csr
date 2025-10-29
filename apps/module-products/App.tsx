import * as React from "react";
import { Provider } from "react-redux";
import { View } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { configureStore } from "@pkg/state";

const store = configureStore();

export default function App() {
  return (
    <Provider store={store}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <ProductsScreen />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
