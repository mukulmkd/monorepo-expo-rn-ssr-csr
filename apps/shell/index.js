import { registerRootComponent } from "expo";
import { Platform } from "react-native";
import React from "react";

// For web, directly load WebApp to avoid React Navigation
// For native, load the App with React Navigation
let RootComponent;

if (Platform.OS === "web") {
  // Directly export WebApp for web to avoid wrapper issues
  RootComponent = require("./web/WebApp").default;
} else {
  // Use NativeApp with React Navigation for iOS/Android
  RootComponent = require("./App").default;
}

// Export the selected component
export default RootComponent;

// Register with Expo - this wraps with DevTools in development
registerRootComponent(RootComponent);
