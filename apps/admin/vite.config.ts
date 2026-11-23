import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
export default defineConfig({
  base: "./",
  publicDir: "../public",
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        admin: fileURLToPath(new URL("./index.html", import.meta.url)),
        setPassword: fileURLToPath(new URL("./set-password/index.html", import.meta.url)),
      },
    },
  },
  server: { port: 5173 },
});
