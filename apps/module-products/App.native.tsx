import * as React from "react";
import { Provider } from "react-redux";
import {
  View,
  Platform,
  DeviceEventEmitter,
  Text,
  TouchableOpacity,
} from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import {
  configureStore,
  AppStore,
  loadPersistedState,
  setCartItems,
  setProductsItems,
} from "@pkg/state";
import { NativeModules } from "react-native";
import { FileStorage } from "./utils/fileStorage";

type AppProps = {
  store?: AppStore;
};

// Get NavigationBridge from native modules (may be undefined in Expo Go or web)
// Use try-catch to handle cases where NativeModules is not available
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;
}

export default function App({ store }: AppProps) {
  // Initialize store with lazy loading of persisted state
  // For native apps, we'll load persisted state immediately and hydrate
  const [appStore] = React.useState<AppStore>(() => {
    return store || configureStore();
  });

  // Function to load and hydrate persisted state
  const loadAndHydrateState = React.useCallback(() => {
    if (store) {
      return; // Store already provided, no need to load persisted state
    }

    // Skip persisted state loading for web or Expo Go
    if (Platform.OS === "web") {
      return;
    }

    // Only load persisted state if NavigationBridge exists (real native app)
    // In Expo Go, NavigationBridge will be undefined, so skip
    if (!NavigationBridge) {
      return; // Skip in Expo Go
    }

    // Load persisted state immediately and hydrate the store
    loadPersistedState()
      .then((persistedState) => {
        if (persistedState) {
          // Hydrate store by dispatching actions - this will trigger re-renders
          if (persistedState.cart && persistedState.cart.items) {
            appStore.dispatch(
              setCartItems({ items: persistedState.cart.items })
            );
          } else {
            // Clear cart if no persisted items
            appStore.dispatch(setCartItems({ items: {} }));
          }
          if (persistedState.products && persistedState.products.items) {
            appStore.dispatch(
              setProductsItems({ items: persistedState.products.items })
            );
          }
        } else {
          // Clear cart if no persisted state
          appStore.dispatch(setCartItems({ items: {} }));
        }
      })
      .catch((error) => {
        // Silently fail - use fresh store
      });
  }, [store, appStore]);

  // Load persisted state immediately on mount (for real native apps only)
  React.useEffect(() => {
    loadAndHydrateState();
  }, [loadAndHydrateState]);

  // File system test state (visible in Expo Go)
  const [fileSystemStatus, setFileSystemStatus] = React.useState<string>("");
  const [savedData, setSavedData] = React.useState<any>(null);
  const [fileExists, setFileExists] = React.useState<boolean>(false);

  // Example: Save app metadata using expo-file-system (works in Expo Go)
  React.useEffect(() => {
    if (Platform.OS === "web") {
      return; // Skip for web
    }

    // Save app metadata to file system (works in both Expo Go and native apps)
    const saveAppMetadata = async () => {
      try {
        const metadata = {
          lastOpened: new Date().toISOString(),
          platform: Platform.OS,
          version: "0.1.9",
          testData: "This is test data from expo-file-system",
        };
        await FileStorage.saveFile("app-metadata.json", metadata);
        setFileSystemStatus("✅ App metadata saved successfully!");
        setSavedData(metadata);
        setFileExists(true);
        console.log("App metadata saved successfully", metadata);
      } catch (error) {
        setFileSystemStatus(`❌ Error: ${error}`);
        console.error("Error saving app metadata:", error);
      }
    };

    // Load existing metadata on mount
    const loadAppMetadata = async () => {
      try {
        const metadata = await FileStorage.loadFile("app-metadata.json");
        if (metadata) {
          setSavedData(metadata);
          setFileExists(true);
          setFileSystemStatus("✅ Loaded existing metadata");
          console.log("Loaded existing metadata", metadata);
        } else {
          // If no metadata exists, save new one
          saveAppMetadata();
        }
      } catch (error) {
        console.error("Error loading app metadata:", error);
        // Try to save new metadata if load fails
        saveAppMetadata();
      }
    };

    loadAppMetadata();
  }, []);

  // Listen for reload event from native side (when view appears)
  React.useEffect(() => {
    if (Platform.OS === "web" || !NavigationBridge) {
      return; // Skip for web or Expo Go
    }

    // Listen for native event to reload state
    const subscription = DeviceEventEmitter.addListener(
      "ReloadPersistedState",
      () => {
        loadAndHydrateState();
      }
    );

    return () => {
      subscription.remove();
    };
  }, [loadAndHydrateState]);

  const handleProductPress = React.useCallback((productId: string) => {
    if (Platform.OS === "web") {
      // Web navigation - could use React Navigation or window.location
    } else if (NavigationBridge) {
      // Real native app - use native bridge to navigate to PDP
      NavigationBridge.navigateToPDP(productId);
    }
    // Expo Go - no navigation available
  }, []);

  // Test file system operations (for Expo Go testing)
  const handleTestFileSystem = React.useCallback(async () => {
    try {
      setFileSystemStatus("Testing file system...");

      // Test 1: Save a test file
      const testData = {
        timestamp: new Date().toISOString(),
        message: "Hello from expo-file-system!",
        randomNumber: Math.floor(Math.random() * 1000),
      };
      await FileStorage.saveFile("test-file.json", testData);

      // Test 2: Check if file exists
      const exists = await FileStorage.fileExists("test-file.json");
      setFileExists(exists);

      // Test 3: Load the file
      const loaded = await FileStorage.loadFile("test-file.json");

      if (loaded) {
        setSavedData(loaded);
        setFileSystemStatus(
          `✅ Success! Saved and loaded: ${JSON.stringify(loaded, null, 2)}`
        );
      } else {
        setFileSystemStatus("❌ File saved but couldn't load");
      }
    } catch (error) {
      setFileSystemStatus(`❌ Error: ${error}`);
      console.error("File system test error:", error);
    }
  }, []);

  const handleDeleteTestFile = React.useCallback(async () => {
    try {
      await FileStorage.deleteFile("test-file.json");
      setFileExists(false);
      setSavedData(null);
      setFileSystemStatus("✅ Test file deleted");
    } catch (error) {
      setFileSystemStatus(`❌ Error deleting: ${error}`);
    }
  }, []);

  // Always render immediately - no loading state needed since store is created synchronously
  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <View style={{ flex: 1 }}>
          {/* File System Test UI (visible in Expo Go) */}
          {Platform.OS !== "web" && (
            <View
              style={{
                padding: 16,
                backgroundColor: "#f0f0f0",
                borderBottomWidth: 1,
                borderBottomColor: "#ddd",
              }}
            >
              <View style={{ marginBottom: 8 }}>
                <Text style={{ fontWeight: "bold", marginBottom: 4 }}>
                  📁 Expo File System Test
                </Text>
                <Text style={{ fontSize: 12, color: "#666" }}>
                  {fileSystemStatus || "Ready to test..."}
                </Text>
              </View>
              {savedData && (
                <View
                  style={{
                    marginBottom: 8,
                    padding: 8,
                    backgroundColor: "#fff",
                    borderRadius: 4,
                  }}
                >
                  <Text
                    style={{
                      fontSize: 10,
                      fontWeight: "bold",
                      marginBottom: 4,
                    }}
                  >
                    Saved Data:
                  </Text>
                  <Text style={{ fontSize: 10, fontFamily: "monospace" }}>
                    {JSON.stringify(savedData, null, 2)}
                  </Text>
                </View>
              )}
              <View style={{ flexDirection: "row", gap: 8 }}>
                <TouchableOpacity
                  style={{
                    flex: 1,
                    backgroundColor: "#007AFF",
                    padding: 12,
                    borderRadius: 4,
                    alignItems: "center",
                  }}
                  onPress={handleTestFileSystem}
                >
                  <Text style={{ color: "#fff", fontWeight: "bold" }}>
                    Test Save/Load
                  </Text>
                </TouchableOpacity>
                {fileExists && (
                  <TouchableOpacity
                    style={{
                      flex: 1,
                      backgroundColor: "#FF3B30",
                      padding: 12,
                      borderRadius: 4,
                      alignItems: "center",
                    }}
                    onPress={handleDeleteTestFile}
                  >
                    <Text style={{ color: "#fff", fontWeight: "bold" }}>
                      Delete File
                    </Text>
                  </TouchableOpacity>
                )}
              </View>
            </View>
          )}
          <ProductsScreen onProductPress={handleProductPress} />
        </View>
        <Footer />
      </View>
    </Provider>
  );
}
