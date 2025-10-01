# Deployment Guide - Hostinger

## 📋 Requisitos Previos

- Cuenta Hostinger con soporte Node.js (Business o Premium)
- Acceso a hPanel
- Git instalado en tu máquina local
- Dominio configurado (ej: justaudit.it)

---

## 🚀 OPCIÓN 1: Deploy Simplificado (RECOMENDADO para Hostinger)

### Paso 1: Preparar el Proyecto

1. **Build del Frontend:**
```bash
cd frontend
npm run build
```

2. **El build genera una carpeta `frontend/.next` que Next.js necesita**

### Paso 2: Configurar en Hostinger

1. **Ir a hPanel → Advanced → Setup Node.js App**

2. **Crear aplicación:**
   - Node.js version: `18.x` o superior
   - Application mode: `Production`
   - Application root: `/domains/tudominio.com/public_html`
   - Application URL: `https://tudominio.com`
   - Application startup file: `server.js`

3. **Subir archivos por FTP/FileManager:**
   - Sube toda la carpeta del proyecto
   - O usa Git (si Hostinger lo permite en tu plan)

### Paso 3: Instalar Dependencias

En la terminal de Hostinger (hPanel → Advanced → Terminal):

```bash
cd ~/domains/tudominio.com/public_html
npm install
cd frontend && npm install && npm run build && cd ..
cd api && npm install && npm run build && cd ..
```

### Paso 4: Variables de Entorno

Crear archivo `.env` en la raíz:

```env
NODE_ENV=production
FRONTEND_PORT=3000
API_PORT=3001
FRONTEND_URL=https://tudominio.com
API_URL=https://api.tudominio.com
```

Crear `api/.env`:

```env
NODE_ENV=production
PORT=3001
FRONTEND_URL=https://tudominio.com
```

Crear `frontend/.env.local`:

```env
NEXT_PUBLIC_API_URL=https://api.tudominio.com
```

### Paso 5: Iniciar la Aplicación

Desde hPanel → Node.js App → Click en "Start Application"

---

## 🐳 OPCIÓN 2: Deploy Completo (Si tienes VPS)

Si tienes un VPS o servidor dedicado, usa Docker.

### Archivos necesarios ya creados:
- `Dockerfile`
- `docker-compose.yml`
- `.dockerignore`

### Comandos:

```bash
# Build y start
docker-compose up -d

# Ver logs
docker-compose logs -f

# Restart
docker-compose restart

# Stop
docker-compose down
```

---

## 🔧 OPCIÓN 3: PM2 (Recomendado para mejor control)

### Instalar PM2 globalmente:

```bash
npm install -g pm2
```

### Usar el archivo `ecosystem.config.js`:

```bash
# Iniciar
pm2 start ecosystem.config.js

# Ver estado
pm2 status

# Ver logs
pm2 logs

# Restart
pm2 restart all

# Stop
pm2 stop all

# Auto-start on reboot
pm2 startup
pm2 save
```

---

## 📝 Configuración de Subdominios

### Para API en subdominio (api.tudominio.com):

1. **Crear subdominio en hPanel:**
   - Ir a Domains → Subdomains
   - Crear `api.tudominio.com`

2. **Configurar proxy reverso:**
   
En `.htaccess` del subdominio:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ http://localhost:3001/$1 [P,L]
```

---

## 🔒 HTTPS / SSL

Hostinger incluye SSL gratis con Let's Encrypt:

1. Ir a hPanel → Advanced → SSL
2. Activar SSL para tu dominio
3. Force HTTPS redirect

---

## 📊 Monitoreo

### Logs en Hostinger:

```bash
# API logs
tail -f ~/domains/tudominio.com/api/debug.log

# PM2 logs (si usas PM2)
pm2 logs
```

### Health Check:

```bash
curl https://api.tudominio.com/health
```

---

## 🚨 Troubleshooting

### Error: "Cannot find Chromium"

Instala dependencias de Chromium:

```bash
# En terminal SSH de Hostinger
sudo apt-get install -y \
  chromium-browser \
  fonts-liberation \
  libappindicator3-1 \
  libasound2 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcups2 \
  libdbus-1-3 \
  libgdk-pixbuf2.0-0 \
  libnspr4 \
  libnss3 \
  libx11-xcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxrandr2 \
  xdg-utils
```

### Error: "Port already in use"

```bash
# Encontrar proceso
lsof -i :3000
lsof -i :3001

# Matar proceso
kill -9 <PID>
```

### Error: "Memory limit"

Ajustar en `ecosystem.config.js`:

```javascript
max_memory_restart: '500M'
```

---

## 📈 Optimizaciones Post-Deploy

1. **Comprimir respuestas:**
   - Ya configurado en `api/src/index.ts` con `compression()`

2. **Rate Limiting:**
   - Implementar con `express-rate-limit` (TODO)

3. **CDN para screenshots:**
   - Mover a Cloudflare R2 o AWS S3 (TODO)

4. **Database:**
   - Por ahora usa memoria (reiniciar = pérdida de datos)
   - TODO: Implementar Redis o PostgreSQL

---

## 🔄 Updates / Redeploy

### Método 1: FTP
1. Subir archivos actualizados
2. Restart app desde hPanel

### Método 2: Git
```bash
git pull
npm install
npm run build
pm2 restart all
```

### Método 3: Script automático
```bash
./deploy.sh
```

---

## 📞 Soporte

- **Hostinger Support**: https://www.hostinger.com/contact
- **Documentación Node.js**: https://support.hostinger.com/en/articles/6555993-how-to-deploy-a-node-js-app

---

**Última actualización**: Octubre 2025

