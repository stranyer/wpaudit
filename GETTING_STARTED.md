# Getting Started with Just Audit It

Este documento te guía en los primeros pasos para ejecutar el proyecto.

## Requisitos

- **Node.js 18+** (recomendado 20.x)
- **npm** o **yarn**
- **Docker Desktop** (para Redis)
- **Git** (para control de versiones)

## Instalación Rápida (Windows)

### Opción 1: Script Automático

1. Abre PowerShell o CMD en la carpeta del proyecto
2. Ejecuta:

```bash
install-and-run.bat
```

Este script:
- Instalará todas las dependencias
- Iniciará Redis en Docker
- Lanzará el frontend y el backend
- Abrirá dos ventanas de terminal (API y Frontend)

### Opción 2: Manual

1. **Instalar dependencias:**

```bash
# Root
npm install

# Frontend
cd frontend
npm install

# API
cd ../api
npm install
cd ..
```

2. **Iniciar Redis:**

```bash
docker run -d -p 6379:6379 --name wpaudit-redis redis:alpine
```

3. **Iniciar servidores:**

En una terminal:
```bash
cd api
npm run dev
```

En otra terminal:
```bash
cd frontend
npm run dev
```

## Acceso

- **Frontend**: http://localhost:3000
- **API**: http://localhost:3001
- **Health Check**: http://localhost:3001/health

## Uso Básico

1. Abre http://localhost:3000
2. Ingresa una URL de WordPress (ejemplo: https://jsesurplus.com)
3. Haz clic en "Run Free Audit"
4. Espera 60-90 segundos mientras se analiza
5. Serás redirigido al reporte completo

## Estructura del Proyecto

```
wpaudit/
├── frontend/              # Next.js frontend
│   ├── app/               # App router pages
│   │   ├── page.tsx       # Landing page
│   │   └── report/        # Report pages
│   ├── components/        # React components (shadcn/ui)
│   └── lib/               # Utilities
├── api/                   # Express API
│   └── src/
│       ├── routes/        # API routes
│       ├── services/      # Business logic
│       └── index.ts       # Entry point
└── package.json           # Root package.json
```

## Funcionalidades Implementadas (MVP)

✅ Landing page con input de URL
✅ Validación de URL
✅ Detección de WordPress (versión, tema, plugins)
✅ Análisis de performance con Lighthouse
✅ Core Web Vitals (LCP, CLS, INP)
✅ Detección de plugins populares
✅ Generación de recomendaciones priorizadas
✅ Scorecards por categoría
✅ Estimación de horas y bundle recomendado
✅ Página de reporte detallado

## Próximos Pasos (V2)

⏳ Generación de PDF
⏳ Envío de email con reporte
⏳ Catálogo extendido de plugins
⏳ Análisis de SEO profundo
⏳ Análisis de seguridad mejorado
⏳ Multi-idioma (EN/ES)

## Troubleshooting

### Error: Redis connection failed

**Solución**: Asegúrate de que Docker esté corriendo y que Redis esté iniciado:

```bash
docker ps | findstr redis
```

Si no aparece, inicia Redis:

```bash
docker run -d -p 6379:6379 --name wpaudit-redis redis:alpine
```

### Error: Port 3000 already in use

**Solución**: Cambia el puerto en `frontend/package.json`:

```json
"scripts": {
  "dev": "next dev -p 3002"
}
```

### Error: Port 3001 already in use

**Solución**: Cambia el puerto en `api/env`:

```
PORT=3002
```

### Error: Lighthouse failed to run

**Solución**: Lighthouse requiere Chrome/Chromium. Asegúrate de tener Chrome instalado.

## Configuración Avanzada

### Variables de Entorno

Crea archivos `.env` basados en `env.example`:

**Frontend** (`frontend/.env.local`):
```
NEXT_PUBLIC_API_URL=http://localhost:3001
```

**API** (`api/.env`):
```
PORT=3001
REDIS_URL=redis://localhost:6379
NODE_ENV=development
```

### Base de Datos (Producción)

Para producción, configura PostgreSQL:

```bash
docker run -d -p 5432:5432 \
  -e POSTGRES_DB=wpaudit \
  -e POSTGRES_USER=wpaudit \
  -e POSTGRES_PASSWORD=wpaudit \
  --name wpaudit-postgres \
  postgres:15-alpine
```

Luego actualiza `DATABASE_URL` en `api/.env`.

## Testing

Sitios de prueba recomendados:

1. https://jsesurplus.com (mencionado en tu brief)
2. https://coachingourselves.com (mencionado en tu brief)
3. https://wordpress.org (WordPress puro)
4. https://woocommerce.com (WooCommerce)

## Desarrollo

### Agregar nuevos plugins para detección

Edita `api/src/services/scanService.ts`, busca `pluginPatterns`:

```typescript
const pluginPatterns = {
  'tu-plugin': { 
    pattern: /patron-regex/i, 
    confidence: 0.9, 
    impact: 'high' as const 
  },
}
```

### Agregar nueva métrica

1. Actualiza la interfaz `ScanResult` en `api/src/services/scanService.ts`
2. Actualiza el método `generateReport()`
3. Actualiza la UI en `frontend/app/report/[reportId]/page.tsx`

## Despliegue

### Vercel (Frontend)

```bash
cd frontend
vercel
```

### Railway/Render (API)

1. Conecta tu repositorio
2. Configura variables de entorno
3. Asegúrate de tener Redis disponible

## Soporte

Para problemas o preguntas:
1. Revisa la documentación en README.md
2. Consulta los issues en GitHub
3. Contacta al equipo de desarrollo

---

**Just Audit It** - Audit your WordPress. Fix what actually slows you down.
