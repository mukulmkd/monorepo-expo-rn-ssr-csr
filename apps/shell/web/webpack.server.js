const path = require("path");

module.exports = {
  mode: process.env.NODE_ENV === "production" ? "production" : "development",
  target: "node",
  entry: path.join(__dirname, "server-entry.tsx"),
  output: {
    path: path.join(__dirname, "../dist/server"),
    filename: "server.js",
    libraryTarget: "commonjs2",
  },
  resolve: {
    extensions: [".ts", ".tsx", ".js"],
    alias: { "react-native$": "react-native-web" },
  },
  module: {
    rules: [
      {
        test: /\.(ts|tsx|js)$/,
        exclude: /node_modules/,
        use: {
          loader: "babel-loader",
          options: { presets: ["babel-preset-expo"] },
        },
      },
    ],
  },
  externalsPresets: { node: true },
  devtool: "source-map",
};
