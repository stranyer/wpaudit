# 🚀 Deploy en Railway.dev con GitLab

## 📋 Requisitos Previos

- Cuenta en [Railway.dev](https://railway.app)
- Proyecto en GitLab: `https://gitlab.com/stranyer/just-speed-it`
- Dominio: `justspeedit.com` (en Hostinger)

## 🎯 Paso 1: Crear Proyecto en Railway

1. Ve a [railway.app](https://railway.app)
2. Click en **"New Project"**
3. Selecciona **"Deploy from GitHub repo"**
4. Click en **"Configure GitLab"**
5. Autoriza Railway para acceder a tu GitLab
6. Selecciona el repo `stranyer/just-speed-it`
7. Railway detectará automáticamente tu aplicación Node.js

## ⚙️ Paso 2: Configurar Variables de Entorno

En el dashboard de Railway, ve a **Variables** y agrega:

```
NODE_ENV=production
PORT=3000
API_PORT=3001
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
```

## 🔧 Paso 3: Configurar Dominio Custom

### En Railway:

1. Ve a **Settings** → **Domains**
2. Click en **"+ Custom Domain"**
3. Ingresa: `justspeedit.com`
4. Railway te dará un **CNAME target** (algo como: `your-app.up.railway.app`)

### En Hostinger:

1. Ve al **Panel de Control** de Hostinger
2. Navega a **Dominios** → **justspeedit.com** → **DNS Zone**
3. Agrega/Edita los siguientes registros:

```
Tipo: CNAME
Nombre: www
Apunta a: your-app.up.railway.app
TTL: 3600

Tipo: A (para el dominio raíz)
Nombre: @
Apunta a: [IP que Railway te proporcione]
TTL: 3600
```

**Nota**: Railway te dará instrucciones específicas en su dashboard.

## 🚀 Paso 4: Configurar Build y Start

Railway detectará automáticamente los scripts de `package.json`, pero vamos a asegurarnos:

Crea un archivo `railway.json` en la raíz del proyecto:

```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "NIXPACKS",
    "buildCommand": "npm install && npm run build:all"
  },
  "deploy": {
    "startCommand": "node start-prod.js",
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

## 📦 Paso 5: Instalar Chromium en Railway

Railway usa Nixpacks que puede instalar dependencias del sistema. Crea un archivo `nixpacks.toml`:

```toml
[phases.setup]
nixPkgs = ["nodejs", "chromium"]

[phases.install]
cmds = ["npm install"]

[phases.build]
cmds = ["npm run build:all"]

[start]
cmd = "node start-prod.js"
```

## 🔍 Paso 6: Verificar Deploy

1. Railway iniciará el build automáticamente
2. Monitorea los logs en tiempo real
3. Una vez completado, verás la URL: `https://your-app.up.railway.app`
4. Prueba la aplicación

## 🌐 Paso 7: Configurar SSL para Dominio Custom

Railway proporciona SSL automático para dominios custom:
- Espera 5-10 minutos después de configurar el CNAME
- Railway generará el certificado SSL automáticamente
- Tu sitio estará disponible en `https://justspeedit.com`

## 📊 Monitoreo y Debugging

### Ver Logs:
```bash
# En el dashboard de Railway, click en "Deployments"
# Selecciona tu deployment y verás logs en tiempo real
```

### Variables de Entorno:
- Se pueden modificar sin hacer redeploy
- Railway reiniciará automáticamente el servicio

### Rollback:
- Railway guarda todos los deploys
- Puedes hacer rollback a cualquier versión anterior

## 💰 Costos y Límites

**Free Tier:**
- $5 de crédito gratis/mes (~500 horas de ejecución)
- 512 MB RAM
- 1 GB de almacenamiento
- Sin límite de builds

**Cálculo aproximado:**
- Si tu app usa ~10 MB RAM y está activa 24/7
- Costo: ~$5/mes
- Con el crédito gratis: **GRATIS el primer mes**

## 🔄 Mantener el Servicio Activo

Railway no "duerme" las aplicaciones en el free tier, pero puedes configurar:

1. **Healthcheck interno**: Agrega un endpoint `/health` que devuelva 200
2. **Monitoring externo**: Usa [UptimeRobot](https://uptimerobot.com/) (gratis) para hacer ping cada 5 minutos

## 🐛 Troubleshooting

### Error: "Cannot find module 'chromium'"
- Verifica que `nixpacks.toml` incluye chromium
- Agrega `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser`

### Error: "Port already in use"
- Railway asigna el puerto automáticamente
- Usa `process.env.PORT` (ya lo tenemos configurado)

### Build timeout
- Railway tiene timeouts más generosos que Render
- Si aún así falla, contacta soporte (responden rápido)

## 🎉 Checklist Final

- [ ] Proyecto creado en Railway
- [ ] Variables de entorno configuradas
- [ ] `nixpacks.toml` creado y commiteado
- [ ] Deploy exitoso
- [ ] URL de Railway funcionando
- [ ] CNAME configurado en Hostinger
- [ ] SSL activo en dominio custom
- [ ] Monitoring configurado

## 📚 Recursos

- [Railway Docs](https://docs.railway.app/)
- [Nixpacks Docs](https://nixpacks.com/)
- [Railway Discord](https://discord.gg/railway) (soporte rápido)

