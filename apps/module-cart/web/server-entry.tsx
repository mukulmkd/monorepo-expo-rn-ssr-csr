import * as React from "react";
import App from "../App";
import { renderToString } from "react-dom/server";

export function render(_url: string) {
  const app = renderToString(<App />);
  return `<!DOCTYPE html>
  <html>
    <head>
      <meta charset=\"utf-8\" />
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
      <title>Cart</title>
    </head>
    <body>
      <div id=\"root\">${app}</div>
      <script src=\"/static/client.js\"></script>
    </body>
  </html>`;
}
