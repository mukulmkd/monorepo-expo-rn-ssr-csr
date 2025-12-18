import * as React from "react";
import { useState, useEffect, useRef } from "react";
import { Provider } from "react-redux";
import {
  View,
  Platform,
  ScrollView,
  TouchableOpacity,
  Alert,
  Text,
  StyleSheet,
  Image,
  Dimensions,
} from "react-native";
import { Header, Footer, Navigation } from "@pkg/ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import {
  configureStore,
  AppStore,
  loadPersistedState,
  setCartItems,
  setProductsItems,
} from "@pkg/state";
import { NativeModules } from "react-native";
import { RNCamera } from "react-native-camera";

type AppProps = {
  store?: AppStore;
  productId?: string;
};

// Get NavigationBridge from native modules (may be undefined in Expo Go or web)
// Use try-catch to handle cases where NativeModules is not available
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;
}

export default function App({ store, productId: initialProductId }: AppProps) {
  // Initialize store with lazy loading of persisted state
  // For native apps, we'll load persisted state immediately and hydrate
  const [appStore] = React.useState<AppStore>(() => {
    return store || configureStore();
  });

  // Get productId from initial props (passed from native)
  const productId = initialProductId || "1";

  // Camera state
  const cameraRef = useRef<RNCamera>(null);
  const [cameraType, setCameraType] = useState<"back" | "front">("back");
  const [isCameraActive, setIsCameraActive] = useState<boolean>(false);
  const [capturedPhoto, setCapturedPhoto] = useState<string | null>(null);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [cameraTimeout, setCameraTimeout] = useState(false);
  const [cameraInfo, setCameraInfo] = useState<string>(
    "Note: react-native-camera requires native code and won't work in Expo Go. You'll need a custom development build or bare React Native app."
  );

  // Note: react-native-camera permissions are handled at the native level
  // (AndroidManifest.xml for Android, Info.plist for iOS)
  // No JS permission API is available

  // Handle camera timeout (simulators don't have cameras)
  useEffect(() => {
    if (isCameraActive) {
      setCameraError(null);
      setCameraTimeout(false);

      // Set a timeout for camera initialization (5 seconds)
      const timeout = setTimeout(() => {
        setCameraTimeout(true);
        setCameraInfo(
          "Camera is taking too long to initialize. This may be because you're using a simulator. Please test on a real device."
        );
      }, 5000);

      return () => clearTimeout(timeout);
    } else {
      setCameraTimeout(false);
      setCameraError(null);
    }
  }, [isCameraActive]);

  // Load persisted state immediately on mount (for real native apps only)
  React.useEffect(() => {
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
    let mounted = true;
    loadPersistedState()
      .then((persistedState) => {
        if (mounted && persistedState) {
          // Hydrate store by dispatching actions - this will trigger re-renders
          if (persistedState.cart && persistedState.cart.items) {
            appStore.dispatch(
              setCartItems({ items: persistedState.cart.items })
            );
          }
          if (persistedState.products && persistedState.products.items) {
            appStore.dispatch(
              setProductsItems({ items: persistedState.products.items })
            );
          }
        }
      })
      .catch((error) => {
        // Silently fail - use fresh store
      });

    return () => {
      mounted = false;
    };
  }, [store, appStore]);

  const handleTakePicture = async () => {
    if (cameraRef.current) {
      try {
        const options = {
          quality: 0.8,
          base64: false,
          skipProcessing: false,
        };
        const data = await cameraRef.current.takePictureAsync(options);
        if (data && data.uri) {
          setCapturedPhoto(data.uri);
          setCameraInfo(`Photo captured: ${data.uri}`);
          Alert.alert("Success", "Photo captured successfully!");
        }
      } catch (error) {
        Alert.alert("Error", `Failed to take picture: ${error}`);
        setCameraInfo(`Error: ${error}`);
      }
    }
  };

  const handleToggleCamera = () => {
    setIsCameraActive(!isCameraActive);
    if (!isCameraActive) {
      setCapturedPhoto(null);
    }
  };

  const handleSwitchCamera = () => {
    setCameraType(cameraType === "back" ? "front" : "back");
  };

  const handleClearPhoto = () => {
    setCapturedPhoto(null);
    setCameraInfo("");
  };

  return (
    <Provider store={appStore}>
      <View style={{ flex: 1 }}>
        <Header />
        <Navigation />
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
        >
          <View style={styles.cameraSection}>
            <Text style={styles.sectionTitle}>
              Camera (react-native-camera)
            </Text>
            <Text style={styles.noteText}>
              ⚠️ Note: react-native-camera requires native code and won't work
              in Expo Go. You'll need a custom development build or bare React
              Native app. Permissions must be configured in AndroidManifest.xml
              (Android) and Info.plist (iOS).
            </Text>

            <>
              <TouchableOpacity
                style={styles.button}
                onPress={handleToggleCamera}
              >
                <Text style={styles.buttonText}>
                  {isCameraActive ? "Stop Camera" : "Start Camera"}
                </Text>
              </TouchableOpacity>

              {isCameraActive && (
                <View style={styles.cameraContainer}>
                  {cameraTimeout || cameraError ? (
                    <View style={styles.cameraErrorContainer}>
                      <Text style={styles.cameraErrorText}>
                        {cameraError ||
                          "Camera is taking too long to initialize."}
                        {"\n\n"}
                        This may be because you're using a simulator.
                        {"\n"}
                        Please test on a real device.
                      </Text>
                      <TouchableOpacity
                        style={styles.button}
                        onPress={() => {
                          setIsCameraActive(false);
                          setCameraTimeout(false);
                          setCameraError(null);
                        }}
                      >
                        <Text style={styles.buttonText}>Close Camera</Text>
                      </TouchableOpacity>
                    </View>
                  ) : (
                    <RNCamera
                      ref={cameraRef}
                      style={styles.camera}
                      type={cameraType}
                      captureAudio={false}
                      androidCameraPermissionOptions={{
                        title: "Permission to use camera",
                        message: "We need your permission to use your camera",
                        buttonPositive: "Ok",
                        buttonNegative: "Cancel",
                      }}
                      onCameraReady={() => {
                        console.log("Camera is ready");
                        setCameraTimeout(false);
                        setCameraError(null);
                        setCameraInfo("");
                      }}
                      onMountError={(error) => {
                        console.error("Camera mount error:", error);
                        setCameraError(
                          `Failed to initialize camera: ${
                            error.message || "Unknown error"
                          }. Please check permissions or test on a real device.`
                        );
                        setCameraTimeout(false);
                      }}
                    >
                      <View style={styles.cameraOverlay}>
                        <TouchableOpacity
                          style={styles.captureButton}
                          onPress={handleTakePicture}
                        >
                          <View style={styles.captureButtonInner} />
                        </TouchableOpacity>
                        <TouchableOpacity
                          style={styles.switchButton}
                          onPress={handleSwitchCamera}
                        >
                          <Text style={styles.switchButtonText}>Switch</Text>
                        </TouchableOpacity>
                      </View>
                    </RNCamera>
                  )}
                </View>
              )}

              {capturedPhoto && (
                <View style={styles.photoContainer}>
                  <Text style={styles.infoTitle}>Captured Photo:</Text>
                  <Image
                    source={{ uri: capturedPhoto }}
                    style={styles.capturedImage}
                    resizeMode="contain"
                  />
                  <TouchableOpacity
                    style={[styles.button, styles.deleteButton]}
                    onPress={handleClearPhoto}
                  >
                    <Text style={styles.buttonText}>Clear Photo</Text>
                  </TouchableOpacity>
                </View>
              )}

              {cameraInfo ? (
                <View style={styles.infoContainer}>
                  <Text style={styles.infoTitle}>Camera Info:</Text>
                  <Text style={styles.infoText}>{cameraInfo}</Text>
                </View>
              ) : null}
            </>
          </View>

          <View style={styles.productSection}>
            <Text style={styles.sectionTitle}>Product Details</Text>
            <ProductDetailPage productId={productId} />
          </View>
        </ScrollView>
        <Footer />
      </View>
    </Provider>
  );
}

const { width } = Dimensions.get("window");

const styles = StyleSheet.create({
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
  },
  cameraSection: {
    marginBottom: 24,
    padding: 16,
    backgroundColor: "#f5f5f5",
    borderRadius: 8,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: "600",
    marginBottom: 16,
  },
  noteText: {
    fontSize: 12,
    color: "#856404",
    backgroundColor: "#fff3cd",
    padding: 10,
    borderRadius: 6,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: "#ffc107",
  },
  button: {
    backgroundColor: "#007bff",
    padding: 12,
    borderRadius: 6,
    marginBottom: 12,
    alignItems: "center",
  },
  deleteButton: {
    backgroundColor: "#dc3545",
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  cameraContainer: {
    width: "100%",
    height: 300,
    marginBottom: 12,
    borderRadius: 8,
    overflow: "hidden",
    backgroundColor: "#000",
  },
  camera: {
    flex: 1,
  },
  cameraOverlay: {
    flex: 1,
    backgroundColor: "transparent",
    justifyContent: "flex-end",
    alignItems: "center",
    paddingBottom: 20,
  },
  captureButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: "#fff",
    borderWidth: 5,
    borderColor: "#007bff",
    justifyContent: "center",
    alignItems: "center",
    marginBottom: 10,
  },
  captureButtonInner: {
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: "#007bff",
  },
  switchButton: {
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    padding: 10,
    borderRadius: 6,
    marginTop: 10,
  },
  switchButtonText: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  photoContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: "#fff",
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#ddd",
  },
  capturedImage: {
    width: "100%",
    height: 200,
    marginTop: 12,
    marginBottom: 12,
    borderRadius: 6,
  },
  infoContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: "#fff",
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#ddd",
  },
  infoTitle: {
    fontSize: 14,
    fontWeight: "600",
    marginBottom: 8,
  },
  infoText: {
    fontSize: 12,
    color: "#333",
    fontFamily: "monospace",
  },
  errorContainer: {
    padding: 12,
    backgroundColor: "#f8d7da",
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#f5c6cb",
  },
  errorText: {
    color: "#721c24",
    fontSize: 14,
  },
  cameraErrorContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: 20,
    backgroundColor: "#f5f5f5",
    borderRadius: 8,
  },
  cameraErrorText: {
    fontSize: 14,
    color: "#dc3545",
    textAlign: "center",
    marginBottom: 20,
    lineHeight: 20,
  },
  productSection: {
    marginTop: 16,
  },
});
