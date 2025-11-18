import { AppRegistry, Platform } from "react-native";

// Import both App components
// Metro will automatically resolve platform-specific extensions when bundling,
// but we need to handle runtime platform detection for Expo development
import AppBase from "./App";
import AppNative from "./App.native";

// Select the appropriate App component based on platform
// For web: use App.tsx (simpler)
// For iOS/Android/Expo Go: use App.native.tsx (handles NavigationBridge gracefully)
const App = Platform.OS === "web" ? AppBase : AppNative;

// Register with AppRegistry for native integration (when bundled into native apps)
// Native apps will look for "ModuleCart" when creating RCTRootView
AppRegistry.registerComponent("ModuleCart", () => App);

// Register with Expo for development (Expo Go, web via Expo, etc.)
// This registers it as "main" which Expo expects
// expo is a peerDependency, so it may not be available in native app bundles
// In that case, AppRegistry.registerComponent above is sufficient
let registerRootComponent;
try {
  // Try to import expo - this will work in Expo development but may fail in native bundles
  // If it fails, we'll just use AppRegistry (which is sufficient for native apps)
  registerRootComponent = require("expo").registerRootComponent;
  if (registerRootComponent) {
    registerRootComponent(App);
  }
} catch (e) {
  // expo not available - this is fine for native app bundles
  // Native apps use AppRegistry.registerComponent above
}
