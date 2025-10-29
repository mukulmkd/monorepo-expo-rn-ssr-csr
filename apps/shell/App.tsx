import * as React from "react";
import { Provider } from "react-redux";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { View } from "react-native";
import { configureStore } from "@pkg/state";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { CartScreen } from "@pkg/cart-ui";

const Stack = createNativeStackNavigator();
const store = configureStore();

export default function App() {
  return (
    <Provider store={store}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          <NavigationContainer>
            <Stack.Navigator>
              <Stack.Screen name="Products" component={ProductsScreen} />
              <Stack.Screen name="Cart" component={CartScreen} />
            </Stack.Navigator>
          </NavigationContainer>
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
