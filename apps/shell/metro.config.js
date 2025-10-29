const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const config = getDefaultConfig(__dirname);

// Ensure React resolves to a single instance from workspace root
const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");

// Force resolution of React from workspace root to avoid duplicate instances
const workspaceReact = path.resolve(workspaceRoot, "node_modules/react");
const workspaceReactDom = path.resolve(workspaceRoot, "node_modules/react-dom");

config.resolver = {
  ...config.resolver,
  // Prioritize workspace root node_modules
  nodeModulesPaths: [
    path.resolve(workspaceRoot, "node_modules"),
    ...(config.resolver?.nodeModulesPaths || []),
    path.resolve(projectRoot, "node_modules"),
  ],
  // Explicitly resolve React packages from workspace root
  extraNodeModules: {
    ...config.resolver?.extraNodeModules,
    react: workspaceReact,
    "react-dom": workspaceReactDom,
    "react-native": path.resolve(workspaceRoot, "node_modules/react-native"),
    // Ensure Expo also uses workspace React
    "@expo/metro-runtime": path.resolve(
      workspaceRoot,
      "node_modules/@expo/metro-runtime"
    ),
  },
};

// Ensure Metro watcher includes workspace root
config.watchFolders = [...(config.watchFolders || []), workspaceRoot];

module.exports = config;
