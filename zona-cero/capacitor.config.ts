import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.zonacero.game',
  appName: 'Zona Cero',
  webDir: 'dist',
  backgroundColor: '#0b0d0b',
  android: {
    // El juego se sirve desde https://localhost dentro del WebView.
    allowMixedContent: false,
  },
  plugins: {
    Geolocation: {},
  },
};

export default config;
