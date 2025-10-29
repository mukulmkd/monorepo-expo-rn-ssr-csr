import React, {
  useState,
  useCallback,
  useMemo,
  useEffect,
  useRef,
} from "react";
import { Provider } from "react-redux";
import { View, Text } from "react-native";
import { Header, Footer, Navigation, NavigationContext } from "@pkg/ui";
import { ProductsScreen } from "@pkg/products-ui";
import { CartScreen } from "@pkg/cart-ui";
import { Homepage } from "@pkg/homepage-ui";
import { ProductDetailPage } from "@pkg/pdp-ui";
import { configureStore, AppStore } from "@pkg/state";

type WebAppProps = {
  store?: AppStore;
  initialRoute?: string;
  initialProductId?: string | null;
};

type Route = "home" | "products" | "product" | "cart";

// Parse URL to get route and productId
function parseUrl(): { route: Route; productId: string | null } {
  if (typeof window === "undefined") {
    return { route: "home", productId: null };
  }

  const path = window.location.pathname;
  const searchParams = new URLSearchParams(window.location.search);
  const productId = searchParams.get("productId");

  if (path === "/cart") {
    return { route: "cart", productId: null };
  } else if (path === "/plp") {
    return { route: "products", productId: null };
  } else if (path === "/pdp" && productId) {
    return { route: "product", productId };
  } else if (path === "/home" || path === "/") {
    return { route: "home", productId: null };
  }

  // Default to home
  return { route: "home", productId: null };
}

// Get URL from route and productId
function getUrlFromRoute(route: Route, productId: string | null): string {
  if (route === "cart") return "/cart";
  if (route === "products") return "/plp";
  if (route === "product" && productId) return `/pdp?productId=${productId}`;
  return "/home";
}

export default function WebApp({
  store,
  initialRoute,
  initialProductId,
}: WebAppProps) {
  // Initialize route from URL or props (for SSR)
  const [routeState, setRouteState] = useState(() => {
    if (initialRoute && initialProductId) {
      return { route: initialRoute as Route, productId: initialProductId };
    }
    if (initialRoute) {
      return { route: initialRoute as Route, productId: null };
    }
    return parseUrl();
  });

  const [route, setRoute] = useState<Route>(routeState.route);
  const [selectedProductId, setSelectedProductId] = useState<string | null>(
    routeState.productId
  );

  // Use provided store or create new one (for client-side hydration)
  // IMPORTANT: Use useMemo to ensure store is only created once, preserving cart state
  const appStore = useMemo(() => {
    if (store) return store;
    // For CSR (Expo web), initialize store from preloaded state if available
    if (typeof window !== "undefined") {
      const preloadedState = (window as any).__PRELOADED_STATE__ as
        | any
        | undefined;
      if (preloadedState) {
        const s = configureStore(preloadedState);
        delete (window as any).__PRELOADED_STATE__;
        return s;
      }
    }
    return configureStore();
  }, [store]);

  // Sync URL with route changes (for browser back/forward)
  useEffect(() => {
    if (typeof window === "undefined") return;

    const handlePopState = () => {
      const parsed = parseUrl();
      setRoute(parsed.route);
      setSelectedProductId(parsed.productId);
    };

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  // Update URL when route changes (but not on initial mount or back/forward)
  // Use a ref to track if this is the initial mount
  const isInitialMount = useRef(true);
  useEffect(() => {
    if (typeof window === "undefined") return;

    // Skip URL update on initial mount (URL is already correct from SSR or initial load)
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }

    const url = getUrlFromRoute(route, selectedProductId);
    const currentUrl = window.location.pathname + window.location.search;
    if (currentUrl !== url) {
      window.history.pushState(
        { route, productId: selectedProductId },
        "",
        url
      );
    }
  }, [route, selectedProductId]);

  // Unified navigation handler for both context and props
  const navigate = useCallback((route: string, params?: any) => {
    if (route === "cart") {
      setRoute("cart");
      setSelectedProductId(null);
    } else if (route === "home") {
      setRoute("home");
      setSelectedProductId(null);
    } else if (route === "products" || route === "all products") {
      setRoute("products");
      setSelectedProductId(null);
    } else if (route === "product") {
      const productId = params?.productId;
      if (productId) {
        setSelectedProductId(productId);
        setRoute("product");
      }
    } else {
      setRoute(route as Route);
    }
  }, []);

  const handleNavigate = useCallback(
    (path: string) => {
      navigate(path);
    },
    [navigate]
  );

  const handleProductPress = useCallback(
    (productId: string) => {
      navigate("product", { productId });
    },
    [navigate]
  );

  const navigationContextValue = useMemo(() => {
    return {
      navigate,
      canGoBack: () => false, // Web doesn't use React Navigation back
      goBack: () => {}, // Web doesn't use React Navigation back
    };
  }, [navigate]);

  return (
    <Provider store={appStore}>
      <NavigationContext.Provider value={navigationContextValue}>
        <View style={{ flex: 1, backgroundColor: "#fff" }}>
          <Header />
          <Navigation onNavigate={handleNavigate} />
          <View style={{ flex: 1 }} key={route}>
            {route === "home" && (
              <Homepage onProductPress={handleProductPress} />
            )}
            {route === "products" && (
              <ProductsScreen onProductPress={handleProductPress} />
            )}
            {route === "product" && selectedProductId ? (
              <ProductDetailPage
                key={selectedProductId}
                productId={selectedProductId}
              />
            ) : route === "product" ? (
              <View
                style={{
                  flex: 1,
                  justifyContent: "center",
                  alignItems: "center",
                }}
              >
                <Text>Loading product...</Text>
              </View>
            ) : null}
            {route === "cart" && (
              <CartScreen key="cart" onProductPress={handleProductPress} />
            )}
          </View>
          <View
            style={{
              position: "absolute",
              bottom: 10,
              left: 10,
              backgroundColor: "rgba(0,0,0,0.7)",
              padding: 8,
              borderRadius: 4,
              zIndex: 9999,
            }}
          >
            <Text style={{ color: "#fff", fontSize: 12 }}>Route: {route}</Text>
          </View>
          <Footer />
        </View>
      </NavigationContext.Provider>
    </Provider>
  );
}
