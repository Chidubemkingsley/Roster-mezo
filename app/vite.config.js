import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  server: {
    host: "127.0.0.1",
    port: 5173,
  },
  preview: {
    host: "127.0.0.1",
    port: 4173,
  },
  build: {
    outDir: "dist",
    target: "es2022",
    rollupOptions: {
      input: {
        home: resolve(import.meta.dirname, "index.html"),
        trade: resolve(import.meta.dirname, "trade.html"),
        secondary: resolve(import.meta.dirname, "secondary.html"),
        vault: resolve(import.meta.dirname, "vault.html"),
        activity: resolve(import.meta.dirname, "activity.html"),
      },
    },
  },
});
