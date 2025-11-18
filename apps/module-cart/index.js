import { AppRegistry, Platform } from "react-native";
import { registerRootComponent } from "expo";

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
// This registers it as "main" which Expo expects - must be called unconditionally
registerRootComponent(App);
