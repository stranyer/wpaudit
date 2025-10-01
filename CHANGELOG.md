# Changelog - Just Audit It

## [Unreleased] - 2025-10-01

### ✨ Added

#### Screenshot Capture Feature
- **Lighthouse Screenshots**: Captura automática de screenshots durante el análisis de Lighthouse
  - Screenshot final para mobile y desktop
  - Filmstrip frames (cada frame del loading process)
  - Guardado en `api/screenshots/{jobId}/`
  - Ruta estática `/screenshots` para servir las imágenes
  
- **Frontend Display**: 
  - Sección "Loading Screenshots" en report page
  - Vista side-by-side de Mobile vs Desktop
  - Diseño monocromático consistente con shadcn/ui
  
- **Technical Details**:
  - Fix para `__dirname` en ES modules worker threads
  - Interface `PerformanceData` extendida con `screenshots` y `filmstrip`
  - Screenshots disponibles vía: `http://localhost:3001/screenshots/{jobId}/{device}-final.jpg`

#### Landing Page Redesign
- Diseño completamente monocromático (negro, gris, blanco)
- Inspirado en RapidLoad.ai
- Logo negro cuadrado con icono de Zap
- Badge "Powered by Google Lighthouse"
- Stats/Trust elements: 10,000+ Sites, 60s scan time, 100% Free
- Features grid con iconos monocromáticos
- Sección "What's in Your Audit" con checkmarks negros
- Footer minimalista con copyright dinámico

#### Scanning Page Redesign
- Fondo blanco limpio (antes gradiente azul-morado)
- Iconos de pasos en cuadrados negros/grises
- Barra de progreso negra
- Botones negros con hover gris
- "Powered by Google Lighthouse" footer

#### Report Page Redesign
- Header sticky con logo negro
- Todas las cards con bordes grises sutiles (`border-gray-200`)
- Iconos de sección en cajas grises redondeadas
- Performance scores con barras negras/grises
- Tipografía consistente en escala de grises
- Sección de estimación con diseño monocromático

### 🔧 Technical Improvements

#### Lighthouse Integration
- Worker Threads implementation para evitar bloqueo del event loop
- Timeout de 45s para mobile y desktop (90s total)
- Fallback a Puppeteer si Lighthouse falla
- Configuración exacta de PageSpeed Insights (throttling, screen emulation)
- Scores redondeados a enteros (sin decimales)

#### WordPress Security Analysis
- Detección de plugins desactualizados
- Checks de vulnerabilidades comunes (XML-RPC, REST API, readme.html)
- Detección de plugins de seguridad activos
- WordPress version status (outdated check)

#### Logging & Debugging
- Custom logger implementado (`api/src/utils/logger.ts`)
- Logs a `debug.log` file
- Detailed performance tracking
- Error tracking con stack traces

### 🧹 Cleanup

#### Files Deleted
- `test-lighthouse.js`
- `test-scan.js`
- `test-api.js`
- `install-and-run.bat`
- `laragon-setup.bat`
- `setup-laragon.bat`
- `start-dev.bat`
- `start-dev.sh`
- `start-wpaudit.bat`
- `wpaudit.conf`
- `api/debug.log` (agregado a `.gitignore`)

#### .gitignore Updates
- Screenshots directory (excepto `.gitkeep`)
- Debug logs

### 📝 Documentation

#### New Files
- `ROADMAP.md`: Plan completo de mejoras (22 items)
  - Mejoras de alto impacto (5 items)
  - Diferenciadores únicos (4 items)
  - Mejoras UX/UI (4 items)
  - Mejoras técnicas (4 items)
  - Monetización (3 items)
  - Analytics & Growth (2 items)
  
- `CHANGELOG.md`: Este archivo

#### Updated Files
- `README.md`: Actualizado con features implementadas
- `GETTING_STARTED.md`: Roadmap de funcionalidades

### 🐛 Bug Fixes

- Fixed `__dirname` undefined error en ES modules (lighthouseRunner.ts)
- Fixed missing `meta` field en ScanResult
- Fixed missing `estimation` field en report
- Fixed SEO/Security/Accessibility/GDPR data structure mismatch
- Fixed report 404 error cuando scan no está guardado
- Fixed TypeScript errors relacionados con Lighthouse types
- Fixed MODULE_TYPELESS_PACKAGE_JSON warnings

### 🎯 Performance

- Lighthouse ejecutado en Worker Threads (no bloquea event loop)
- Timeout mechanism para prevenir scans stuck
- Fallback automático a Puppeteer si Lighthouse falla
- Screenshots guardados de forma asíncrona

---

## [0.1.0] - Initial Release

### Features
- WordPress detection (version, theme, plugins)
- Performance analysis con Lighthouse
- SEO, Security, Accessibility, GDPR analysis
- Actionable priorities generation
- Effort estimation (hours + bundle recommendation)
- Report generation con scores por categoría

---

**Formato**: Este changelog sigue [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

