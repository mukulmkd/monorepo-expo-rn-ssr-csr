import { AppRegistry } from "react-native";
import App from "./App.native";

// Register with AppRegistry for native integration
AppRegistry.registerComponent("ModuleCart", () => App);

// Also register with Expo for development
if (typeof require !== "undefined" && require.main === module) {
  const { registerRootComponent } = require("expo");
  registerRootComponent(App);
}
