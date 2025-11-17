import { Platform } from "react-native";
import type { AppState } from "./store";

// Dynamically import AsyncStorage only in native environments
let AsyncStorage: any = null;
if (Platform.OS !== "web") {
  try {
    AsyncStorage = require("@react-native-async-storage/async-storage").default;
  } catch (e) {
    console.warn("AsyncStorage not available:", e);
  }
}

const CART_STORAGE_KEY = "@myshopapp:cart";
const PRODUCTS_STORAGE_KEY = "@myshopapp:products";

/**
 * Load persisted cart state from AsyncStorage
 */
export async function loadCartState(): Promise<AppState["cart"] | null> {
  if (!AsyncStorage || Platform.OS === "web") {
    return null;
  }
  try {
    const cartData = await AsyncStorage.getItem(CART_STORAGE_KEY);
    if (cartData) {
      return JSON.parse(cartData);
    }
  } catch (error) {
    console.warn("Failed to load cart state from storage:", error);
  }
  return null;
}

/**
 * Save cart state to AsyncStorage
 */
export async function saveCartState(cart: AppState["cart"]): Promise<void> {
  if (!AsyncStorage || Platform.OS === "web") {
    return;
  }
  try {
    await AsyncStorage.setItem(CART_STORAGE_KEY, JSON.stringify(cart));
  } catch (error) {
    console.warn("Failed to save cart state to storage:", error);
  }
}

/**
 * Load persisted products state from AsyncStorage
 */
export async function loadProductsState(): Promise<AppState["products"] | null> {
  if (!AsyncStorage || Platform.OS === "web") {
    return null;
  }
  try {
    const productsData = await AsyncStorage.getItem(PRODUCTS_STORAGE_KEY);
    if (productsData) {
      return JSON.parse(productsData);
    }
  } catch (error) {
    console.warn("Failed to load products state from storage:", error);
  }
  return null;
}

/**
 * Save products state to AsyncStorage
 */
export async function saveProductsState(
  products: AppState["products"]
): Promise<void> {
  if (!AsyncStorage || Platform.OS === "web") {
    return;
  }
  try {
    await AsyncStorage.setItem(PRODUCTS_STORAGE_KEY, JSON.stringify(products));
  } catch (error) {
    console.warn("Failed to save products state to storage:", error);
  }
}

/**
 * Load all persisted state
 */
export async function loadPersistedState(): Promise<Partial<AppState> | null> {
  try {
    const [cart, products] = await Promise.all([
      loadCartState(),
      loadProductsState(),
    ]);

    const state: Partial<AppState> = {};
    if (cart) state.cart = cart;
    if (products) state.products = products;

    return Object.keys(state).length > 0 ? state : null;
  } catch (error) {
    console.warn("Failed to load persisted state:", error);
    return null;
  }
}
