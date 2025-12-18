import * as FileSystem from "expo-file-system";
import { Platform } from "react-native";

/**
 * File storage utility using expo-file-system
 * Provides methods to save and load JSON data to/from the device's file system
 */
export class FileStorage {
  private static readonly BASE_DIR = FileSystem.documentDirectory || "";
  private static readonly STORAGE_DIR = `${FileStorage.BASE_DIR}module-products/`;

  /**
   * Ensure the storage directory exists
   */
  static async ensureDirectoryExists(): Promise<void> {
    try {
      const dirInfo = await FileSystem.getInfoAsync(FileStorage.STORAGE_DIR);
      if (!dirInfo.exists) {
        await FileSystem.makeDirectoryAsync(FileStorage.STORAGE_DIR, {
          intermediates: true,
        });
      }
    } catch (error) {
      console.error("Error creating storage directory:", error);
      throw error;
    }
  }

  /**
   * Save JSON data to a file
   * @param filename - Name of the file (without path)
   * @param data - Data to save (will be JSON stringified)
   * @returns Promise that resolves when file is saved
   */
  static async saveFile(filename: string, data: any): Promise<void> {
    if (Platform.OS === "web") {
      // Web fallback: use localStorage
      try {
        localStorage.setItem(
          `module-products-${filename}`,
          JSON.stringify(data)
        );
      } catch (error) {
        console.error("Error saving to localStorage:", error);
        throw error;
      }
      return;
    }

    try {
      await FileStorage.ensureDirectoryExists();
      const fileUri = `${FileStorage.STORAGE_DIR}${filename}`;
      const jsonString = JSON.stringify(data, null, 2);
      await FileSystem.writeAsStringAsync(fileUri, jsonString, {
        encoding: FileSystem.EncodingType.UTF8,
      });
    } catch (error) {
      console.error(`Error saving file ${filename}:`, error);
      throw error;
    }
  }

  /**
   * Load JSON data from a file
   * @param filename - Name of the file (without path)
   * @returns Promise that resolves with the parsed data, or null if file doesn't exist
   */
  static async loadFile<T = any>(filename: string): Promise<T | null> {
    if (Platform.OS === "web") {
      // Web fallback: use localStorage
      try {
        const data = localStorage.getItem(`module-products-${filename}`);
        return data ? JSON.parse(data) : null;
      } catch (error) {
        console.error("Error loading from localStorage:", error);
        return null;
      }
    }

    try {
      const fileUri = `${FileStorage.STORAGE_DIR}${filename}`;
      const fileInfo = await FileSystem.getInfoAsync(fileUri);

      if (!fileInfo.exists) {
        return null;
      }

      const jsonString = await FileSystem.readAsStringAsync(fileUri, {
        encoding: FileSystem.EncodingType.UTF8,
      });

      return JSON.parse(jsonString) as T;
    } catch (error) {
      console.error(`Error loading file ${filename}:`, error);
      return null;
    }
  }

  /**
   * Delete a file
   * @param filename - Name of the file (without path)
   * @returns Promise that resolves when file is deleted
   */
  static async deleteFile(filename: string): Promise<void> {
    if (Platform.OS === "web") {
      // Web fallback: use localStorage
      try {
        localStorage.removeItem(`module-products-${filename}`);
      } catch (error) {
        console.error("Error deleting from localStorage:", error);
        throw error;
      }
      return;
    }

    try {
      const fileUri = `${FileStorage.STORAGE_DIR}${filename}`;
      const fileInfo = await FileSystem.getInfoAsync(fileUri);

      if (fileInfo.exists) {
        await FileSystem.deleteAsync(fileUri, { idempotent: true });
      }
    } catch (error) {
      console.error(`Error deleting file ${filename}:`, error);
      throw error;
    }
  }

  /**
   * Check if a file exists
   * @param filename - Name of the file (without path)
   * @returns Promise that resolves to true if file exists, false otherwise
   */
  static async fileExists(filename: string): Promise<boolean> {
    if (Platform.OS === "web") {
      // Web fallback: use localStorage
      return localStorage.getItem(`module-products-${filename}`) !== null;
    }

    try {
      const fileUri = `${FileStorage.STORAGE_DIR}${filename}`;
      const fileInfo = await FileSystem.getInfoAsync(fileUri);
      return fileInfo.exists;
    } catch (error) {
      console.error(`Error checking file ${filename}:`, error);
      return false;
    }
  }

  /**
   * Get the URI of a file (useful for sharing or other operations)
   * @param filename - Name of the file (without path)
   * @returns The full URI of the file
   */
  static getFileUri(filename: string): string {
    return `${FileStorage.STORAGE_DIR}${filename}`;
  }
}
