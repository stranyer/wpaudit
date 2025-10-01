# 🚀 Deploy en Render.com - Guía Completa

## ⏱️ Tiempo Total: 15 minutos

---

## 📋 Paso 1: Preparar GitHub (5 min)

### 1.1 Crear repositorio en GitHub

1. Ve a https://github.com/new
2. Nombre: `wpaudit` o `justspeedit`
3. Privado o Público (tu elección)
4. **NO** inicializar con README
5. Click **Create repository**

### 1.2 Subir tu código

En tu terminal de Windows (en la carpeta del proyecto):

```bash
git remote add origin https://github.com/TU-USUARIO/wpaudit.git
git branch -M main
git push -u origin main
```

✅ Tu código ahora está en GitHub

---

## 🌐 Paso 2: Deploy en Render.com (5 min)

### 2.1 Crear cuenta

1. Ve a https://render.com
2. Click **"Sign Up"**
3. Usa **"Sign up with GitHub"** (más fácil)
4. Autoriza Render a acceder a tus repos

### 2.2 Crear nuevo Web Service

1. En Dashboard → Click **"New +"** → **"Web Service"**

2. Conectar tu repositorio:
   - Busca `wpaudit` o tu repo
   - Click **"Connect"**

3. Configuración:
   ```
   Name: justspeedit
   Region: Oregon (US West)
   Branch: main
   Runtime: Node
   Build Command: npm install && cd frontend && npm install && npm run build && cd ../api && npm install && npm run build && cd ..
   Start Command: node start-dev.js
   Plan: Free
   ```

4. **Environment Variables** (Click "Advanced"):
   ```
   NODE_ENV=production
   PORT=3000
   API_PORT=3001
   ```

5. Click **"Create Web Service"**

### 2.3 Esperar el deploy (3-5 min)

- Verás logs en tiempo real
- Al terminar dirá: **"Your service is live"**
- Tu URL será: `https://justspeedit.onrender.com`

✅ ¡Tu sitio ya está online!

---

## 🔧 Paso 3: Configurar Cron Job (3 min)

### 3.1 Crear cuenta en cron-job.org

1. Ve a https://cron-job.org/en/signup/
2. Crea cuenta gratuita
3. Verifica tu email

### 3.2 Crear nuevo Cron Job

1. Login → Dashboard → **"Create cronjob"**

2. Configuración:
   ```
   Title: Keep JustSpeedIt Awake
   Address: https://justspeedit.onrender.com/api/health
   
   Schedule:
   - Every: 10 minutes
   
   Execution:
   - Enabled: ✅
   
   Notification:
   - Only on errors (opcional)
   ```

3. Click **"Create cronjob"**

✅ Tu sitio ahora se mantiene despierto 24/7

---

## 🌐 Paso 4: Conectar Dominio Custom (2 min)

### 4.1 En Render Dashboard

1. Tu Web Service → Tab **"Settings"**
2. Sección **"Custom Domain"**
3. Click **"Add Custom Domain"**
4. Ingresa: `justspeedit.com`
5. Render te mostrá un **CNAME record**

### 4.2 En Hostinger DNS

1. Login a Hostinger → **hPanel**
2. **Domains** → Click en `justspeedit.com` → **DNS Zone**
3. Agregar/Editar records:

**Record 1:**
```
Type: CNAME
Name: @
Value: justspeedit.onrender.com
TTL: 14400
```

**Record 2:**
```
Type: CNAME
Name: www
Value: justspeedit.onrender.com
TTL: 14400
```

4. **Save DNS Zone**

### 4.3 SSL Automático

- Render detecta el dominio automáticamente
- Genera certificado SSL gratis (Let's Encrypt)
- En 5-10 minutos: `https://justspeedit.com` funciona

✅ Dominio configurado con SSL

---

## ✅ Verificación Final

Prueba estos URLs:

1. **Frontend**: https://justspeedit.com
2. **API Health**: https://justspeedit.com/api/health
3. **Escanear**: Ingresa una URL de WordPress

---

## 🔄 Updates Futuros

### Opción 1: Auto-deploy (Recomendado)

Cada vez que hagas `git push`:
1. Render detecta el cambio
2. Hace rebuild automático
3. Deploy en 3-5 minutos

```bash
# Hacer cambios en tu código
git add .
git commit -m "feat: nueva funcionalidad"
git push
```

### Opción 2: Manual desde Render

1. Render Dashboard → Tu servicio
2. Click **"Manual Deploy"** → **"Deploy latest commit"**

---

## 📊 Monitoreo

### Ver Logs en Tiempo Real:

1. Render Dashboard → Tu servicio → Tab **"Logs"**
2. Stream en vivo de todos los logs

### Metrics:

1. Tab **"Metrics"**
2. CPU, Memory, Request count
3. Response times

---

## 🚨 Troubleshooting

### ❌ Error: "Build failed"

**Causa**: Dependencias faltantes o error de compilación

**Solución**:
```bash
# Localmente, verifica que todo compila:
cd frontend && npm run build && cd ..
cd api && npm run build && cd ..

# Si funciona local, commitea y push
git add .
git commit -m "fix: build errors"
git push
```

### ❌ Error: "Application failed to respond"

**Causa**: Puerto incorrecto o app no inició

**Solución**:
1. Verifica Start Command: `node start-dev.js`
2. Chequea logs en Render Dashboard
3. Asegúrate que `PORT` env var = `3000`

### ❌ Dominio no funciona

**Causa**: DNS aún no propagó (puede tardar hasta 24h)

**Solución**:
1. Verifica records DNS en Hostinger
2. Usa https://dnschecker.org para ver propagación
3. Espera 1-24 horas

### ❌ Lighthouse falla

**Causa**: Chromium no instaló correctamente

**Solución**:
1. Render instala Chromium automáticamente
2. Si falla, agrega al `render.yaml`:
   ```yaml
   buildCommand: apt-get update && apt-get install -y chromium && npm install...
   ```

---

## 💰 Costos

| Recurso | Free Tier | Límites |
|---------|-----------|---------|
| Web Service | ✅ Gratis | 750 horas/mes |
| Build Minutes | ✅ Gratis | 500 min/mes |
| Bandwidth | ✅ Gratis | 100 GB/mes |
| SSL Certificate | ✅ Gratis | Ilimitado |
| Custom Domain | ✅ Gratis | Ilimitado |
| Disk Storage | ✅ Gratis | 1 GB |
| **TOTAL** | **$0/mes** | **∞** |

---

## 🎯 Siguiente Paso: Optimizaciones

Una vez funcionando, considera:

1. **Redis Cache** (Render Redis: $5/mes)
   - Cachear resultados 24h
   - Reduce uso de recursos

2. **Analytics** (Free)
   - Agregar Google Analytics
   - Posthog.com (gratis hasta 1M events)

3. **Rate Limiting**
   - Implementar en API
   - 3 scans/hora por IP

4. **Monetización**
   - Stripe integration
   - Premium features

---

## 📞 Soporte

- **Render Docs**: https://render.com/docs
- **Render Status**: https://status.render.com
- **Community**: https://community.render.com

---

**Última actualización**: Octubre 2025
**Estimado de setup**: 15 minutos
**Costo mensual**: $0

¡Tu aplicación está lista para producción! 🎉

