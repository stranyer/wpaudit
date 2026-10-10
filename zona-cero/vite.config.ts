import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import basicSsl from '@vitejs/plugin-basic-ssl';

// Configuración de Vite + Vitest para Zona Cero.
// `base: './'` permite servir el build desde el WebView de Capacitor (file://).
// Modo `lan` (npm run dev:lan): HTTPS con certificado autofirmado para abrir el juego
// desde el celular por la red local con GPS real (el navegador exige HTTPS para la ubicación).
export default defineConfig(({ mode }) => ({
  base: './',
  plugins: [react(), ...(mode === 'lan' ? [basicSsl({ name: 'zona-cero-lan' })] : [])],
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
}));
