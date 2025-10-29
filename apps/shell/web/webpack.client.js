const path = require("path");

module.exports = {
  mode: process.env.NODE_ENV === "production" ? "production" : "development",
  entry: path.join(__dirname, "client.tsx"),
  output: {
    path: path.join(__dirname, "../dist/client"),
    filename: "client.js",
    publicPath: "/static/",
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
  devtool: "source-map",
};
