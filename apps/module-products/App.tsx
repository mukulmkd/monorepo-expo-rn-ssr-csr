import * as React from "react";
import { Provider } from "react-redux";
import { View, Platform } from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { configureStore, AppStore } from "@pkg/state";
import { NativeModules } from "react-native";

type AppProps = {
  store?: AppStore;
};

// Get NavigationBridge from native modules (may be undefined in Expo Go or web)
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;
}

export default function App({ store }: AppProps) {
  const appStore = store || configureStore();

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

  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <ProductsScreen onProductPress={handleProductPress} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
