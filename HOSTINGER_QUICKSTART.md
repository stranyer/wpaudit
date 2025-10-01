# 🚀 Guía Rápida - Deploy en Hostinger

## ⚡ Setup en 15 Minutos

### 1️⃣ Preparación Local (5 min)

```bash
# En tu máquina local (Windows)
cd C:\laragon\www\wpaudit

# Build Frontend
cd frontend
npm run build
cd ..

# Build API
cd api
npm run build
cd ..

# Comprimir todo el proyecto
# Usa WinRAR o 7zip para crear: wpaudit.zip
```

**Incluir en el ZIP:**
- ✅ `api/` (completo)
- ✅ `frontend/` (completo)  
- ✅ `package.json`
- ✅ `ecosystem.config.js`
- ✅ `deploy.sh`
- ❌ NO incluir `node_modules` (muy pesado)
- ❌ NO incluir `.git`

---

### 2️⃣ Subir a Hostinger (5 min)

**Opción A: File Manager (Más fácil)**

1. Login a hPanel (https://hpanel.hostinger.com)
2. Ir a **Files → File Manager**
3. Navegar a `/domains/tudominio.com/public_html/`
4. Upload `wpaudit.zip`
5. Click derecho → **Extract**
6. Borrar `wpaudit.zip`

**Opción B: FTP**

1. Usar FileZilla
2. Host: `ftp.tudominio.com`
3. Usuario: tu usuario FTP
4. Subir carpeta completa

---

### 3️⃣ Configurar Node.js App (3 min)

1. En hPanel → **Advanced → Setup Node.js App**

2. **Configuración:**
   ```
   Node.js version: 18.x
   Application mode: Production
   Application root: /domains/tudominio.com/public_html
   Application startup file: start-dev.js
   ```

3. Click **Create**

---

### 4️⃣ Instalar Dependencias (2 min)

En hPanel → **Advanced → Terminal SSH**:

```bash
cd ~/domains/tudominio.com/public_html

# Instalar root
npm install

# Instalar API
cd api
npm install
cd ..

# Instalar Frontend
cd frontend
npm install
cd ..
```

---

### 5️⃣ Configurar Variables de Entorno (1 min)

Crear archivo `.env` en la raíz:

```bash
nano .env
```

Pegar:

```env
NODE_ENV=production
FRONTEND_URL=https://tudominio.com
API_URL=https://tudominio.com
```

Guardar: `Ctrl+X`, `Y`, `Enter`

Crear `frontend/.env.local`:

```bash
nano frontend/.env.local
```

Pegar:

```env
NEXT_PUBLIC_API_URL=https://tudominio.com/api
```

---

### 6️⃣ Iniciar Aplicación

**En hPanel → Node.js App:**

1. Click en tu aplicación
2. Click **"Restart Application"**
3. Esperar 30 segundos

---

### 7️⃣ Configurar Nginx (Reverse Proxy)

Crear `.htaccess` en `/domains/tudominio.com/public_html/`:

```apache
<IfModule mod_rewrite.c>
  RewriteEngine On
  
  # API Routes
  RewriteCond %{REQUEST_URI} ^/api
  RewriteRule ^api/(.*)$ http://localhost:3001/$1 [P,L]
  
  # Frontend Routes
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule ^(.*)$ http://localhost:3000/$1 [P,L]
</IfModule>
```

---

## ✅ Verificación

1. **Frontend**: https://tudominio.com
2. **API Health**: https://tudominio.com/api/health
3. **Escanear un sitio**

---

## 🔧 Troubleshooting

### ❌ Error: "Application not running"

```bash
cd ~/domains/tudominio.com/public_html
pm2 restart all
# o
node start-dev.js
```

### ❌ Error: "Cannot find Chromium"

Chromium NO está disponible en hosting compartido. 

**Solución**: Usar un VPS o cambiar a:
- DigitalOcean ($6/mes)
- Linode ($5/mes)
- Vultr ($5/mes)

### ❌ Error: "Port already in use"

```bash
pkill node
pm2 restart all
```

### ❌ Frontend carga, API no

Verificar que el proxy reverso esté configurado en `.htaccess`

---

## 📊 Monitoring

### Ver Logs:

```bash
# API
tail -f ~/domains/tudominio.com/public_html/api/debug.log

# PM2 (si está instalado)
pm2 logs
```

### Restart:

```bash
cd ~/domains/tudominio.com/public_html
pm2 restart all
```

---

## 🔄 Updates Futuros

### Método 1: FTP
1. Subir archivos modificados
2. SSH: `pm2 restart all`

### Método 2: Git (Si tu plan lo permite)

```bash
cd ~/domains/tudominio.com/public_html
git pull
npm install
cd frontend && npm run build && cd ..
cd api && npm run build && cd ..
pm2 restart all
```

---

## ⚠️ Limitaciones de Hosting Compartido

1. **Chromium NO disponible** → Lighthouse no funcionará
2. **Memoria limitada** → Solo 2-3 scans simultáneos
3. **CPU compartida** → Scans más lentos

### 💡 Recomendación

Para producción seria:
- **VPS** (DigitalOcean, Linode, Vultr) - $5-10/mes
- **Permite Chromium/Lighthouse**
- **Recursos dedicados**
- **Mejor performance**

---

## 📞 Ayuda

- **Hostinger Support**: Chat 24/7 en hPanel
- **Node.js Docs**: https://support.hostinger.com/en/articles/6555993

---

**Última actualización**: Octubre 2025

