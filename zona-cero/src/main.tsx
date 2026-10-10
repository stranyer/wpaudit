import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
// Solo el subset latino (incluye acentos y ñ): menos archivos y menos peso.
import '@fontsource/black-ops-one/latin-400.css';
import '@fontsource/oswald/latin-400.css';
import '@fontsource/oswald/latin-500.css';
import '@fontsource/oswald/latin-600.css';
import '@fontsource/oswald/latin-700.css';
import './ui/styles/global.css';
import { App } from './App';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
