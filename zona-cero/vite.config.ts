import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// Configuración de Vite + Vitest para Zona Cero.
// `base: './'` permite servir el build desde el WebView de Capacitor (file://).
export default defineConfig({
  base: './',
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
  },
  build: {
    target: 'es2022',
    sourcemap: false,
    chunkSizeWarningLimit: 1600,
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
