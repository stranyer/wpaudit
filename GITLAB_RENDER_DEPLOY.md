# 🚀 Deploy en Render.com con GitLab

## ⏱️ Tiempo Total: 15 minutos

---

## 📋 Paso 1: Preparar GitLab (5 min)

### 1.1 Crear repositorio en GitLab

1. Ve a https://gitlab.com/projects/new
2. Nombre: `wpaudit` o `justspeedit`
3. Visibility: Private o Public (tu elección)
4. **NO** inicializar con README
5. Click **"Create project"**

### 1.2 Subir tu código

En tu terminal de Windows (en la carpeta del proyecto):

```bash
# Si ya tienes Git configurado
git remote add origin https://gitlab.com/TU-USUARIO/wpaudit.git
git branch -M main
git push -u origin main
```

Si es la primera vez con Git:

```bash
git init
git add .
git commit -m "Initial commit: WordPress Audit Tool"
git branch -M main
git remote add origin https://gitlab.com/TU-USUARIO/wpaudit.git
git push -u origin main
```

✅ Tu código ahora está en GitLab

---

## 🌐 Paso 2: Deploy en Render.com (5 min)

### 2.1 Crear cuenta en Render

1. Ve a https://render.com
2. Click **"Sign Up"**
3. Puedes usar:
   - **Email** (recomendado si usas GitLab)
   - GitHub (si tienes)
   - GitLab OAuth (si prefieres)

### 2.2 Conectar GitLab

**Opción A: Via GitLab OAuth** (Más fácil)

1. En Render Dashboard → Settings → **"Connected Accounts"**
2. Click **"Connect GitLab"**
3. Autoriza Render en GitLab
4. Listo

**Opción B: Via Git URL** (Manual)

1. En GitLab, copia la URL HTTPS de tu repo:
   ```
   https://gitlab.com/TU-USUARIO/wpaudit.git
   ```
2. En Render, usa "Public Git Repository" y pega la URL

### 2.3 Crear nuevo Web Service

1. En Render Dashboard → Click **"New +"** → **"Web Service"**

2. Conectar repositorio:
   - Si usaste OAuth: Busca `wpaudit` en la lista
   - Si usaste URL: Ya debería estar conectado

3. Click **"Connect"**

4. Configuración del servicio:

```
Name: justspeedit
Region: Oregon (US West)
Branch: main
Runtime: Node
Root Directory: (dejar vacío)

Build Command:
npm install && cd frontend && npm install && npm run build && cd ../api && npm install && npm run build && cd ..

Start Command:
node start-dev.js

Instance Type: Free
```

5. **Variables de Entorno** (Advanced):

Click **"Add Environment Variable"** para cada una:

```
NODE_ENV = production
PORT = 3000
API_PORT = 3001
```

6. Click **"Create Web Service"**

### 2.4 Esperar el deploy (3-5 min)

- Verás logs en tiempo real
- Primera vez puede tardar 5-7 minutos
- Al terminar dirá: **"Your service is live 🎉"**
- Tu URL será: `https://justspeedit.onrender.com`

✅ ¡Tu sitio ya está online!

---

## 🔧 Paso 3: Configurar Auto-Deploy desde GitLab (Bonus)

### 3.1 Webhook automático

Render crea un webhook automáticamente en GitLab cuando conectas con OAuth.

Para verificar:

1. GitLab → Tu proyecto → **Settings → Webhooks**
2. Deberías ver un webhook de Render
3. Cada `git push` ahora hace auto-deploy

### 3.2 Si necesitas configurar manualmente:

1. En Render → Tu servicio → **Settings → "Deploy Hook"**
2. Copia la URL del webhook
3. En GitLab → **Settings → Webhooks**
4. Pega la URL
5. Trigger: **"Push events"**
6. Branch: `main`
7. Click **"Add webhook"**

✅ Auto-deploy configurado

---

## 🔧 Paso 4: Configurar Cron Job (3 min)

**Mismo proceso que con GitHub** - Ver [CRON_SETUP.md](./CRON_SETUP.md)

Resumen rápido:

1. Crear cuenta en https://cron-job.org
2. Crear cronjob:
   ```
   URL: https://justspeedit.onrender.com/api/health
   Intervalo: Cada 10 minutos
   ```
3. Tu sitio se mantiene despierto 24/7

✅ Uptime 100% gratis

---

## 🌐 Paso 5: Conectar Dominio Custom (2 min)

### 5.1 En Render Dashboard

1. Tu Web Service → Tab **"Settings"**
2. Sección **"Custom Domain"**
3. Click **"Add Custom Domain"**
4. Ingresa: `justspeedit.com`
5. Render te muestra el CNAME record

### 5.2 En Hostinger DNS

1. Login a Hostinger → **hPanel**
2. **Domains** → Click en `justspeedit.com` → **DNS Zone**
3. Agregar/Editar records:

**Para dominio raíz (@):**
```
Type: CNAME
Name: @
Value: justspeedit.onrender.com
TTL: 14400
```

**Para www:**
```
Type: CNAME
Name: www
Value: justspeedit.onrender.com
TTL: 14400
```

4. **Save DNS Zone**

### 5.3 SSL Automático

- Render detecta el dominio en 5-10 minutos
- Genera certificado SSL gratis (Let's Encrypt)
- `https://justspeedit.com` funciona automáticamente

✅ Dominio configurado

---

## 🔄 Workflow de Updates

### Cada vez que quieras actualizar:

```bash
# 1. Hacer cambios en tu código local
# 2. Commit
git add .
git commit -m "feat: nueva funcionalidad"

# 3. Push a GitLab
git push

# 4. Render auto-deploy (automático en 3-5 min)
```

### Ver el progreso:

1. Render Dashboard → Tu servicio → Tab **"Events"**
2. Verás: "Deploy triggered by commit..."
3. Click para ver logs en tiempo real

---

## 📊 Monitoreo

### GitLab CI/CD (Opcional - Avanzado)

Puedes agregar un `.gitlab-ci.yml` para tests antes de deploy:

```yaml
stages:
  - test
  - deploy

test:
  stage: test
  script:
    - npm install
    - cd frontend && npm run build
    - cd ../api && npm run build

deploy:
  stage: deploy
  script:
    - echo "Deployed to Render"
  only:
    - main
```

---

## 🚨 Troubleshooting

### ❌ Error: "Repository not found"

**Causa**: Permisos de GitLab

**Solución**:
1. GitLab → Proyecto → **Settings → General**
2. **Visibility**: Asegúrate que Render tenga acceso
3. Si es privado, reconecta con OAuth

### ❌ Error: "Build failed"

**Causa**: Dependencias o compilación

**Solución**:
```bash
# Probar localmente primero:
npm install
cd frontend && npm run build && cd ..
cd api && npm run build && cd ..

# Si funciona, commitea:
git add .
git commit -m "fix: build configuration"
git push
```

### ❌ Error: "Deploy webhook not working"

**Causa**: Webhook no configurado

**Solución**:
1. Render → Settings → Copiar "Deploy Hook URL"
2. GitLab → Settings → Webhooks → Agregar
3. Test webhook: GitLab → Test → Push events

---

## 💰 Ventajas de GitLab + Render

| Feature | Incluido |
|---------|----------|
| GitLab CI/CD | ✅ Gratis (400 min/mes) |
| Private Repos | ✅ Ilimitados (gratis) |
| Render Deploy | ✅ Auto-deploy |
| SSL Certificate | ✅ Gratis |
| Custom Domain | ✅ Gratis |
| **Costo Total** | **$0/mes** |

---

## 🔐 Security Tips

### 1. Variables de Entorno Sensibles

**NUNCA** commitees:
- `.env`
- API keys
- Secrets

Usa Render Environment Variables:
1. Render → Settings → Environment
2. Add variables ahí (encriptadas)

### 2. Branch Protection

GitLab → Settings → Repository → Protected Branches:
```
Branch: main
Allowed to push: Maintainers
Allowed to merge: Maintainers
```

### 3. Deploy Tokens (Producción)

Para producción seria, usa Deploy Tokens en lugar de OAuth:

1. GitLab → Settings → Repository → Deploy Tokens
2. Name: `render-deploy`
3. Scopes: `read_repository`
4. Usa el token en Render

---

## 📞 Soporte

- **Render + GitLab**: https://render.com/docs/deploy-from-gitlab
- **GitLab CI/CD**: https://docs.gitlab.com/ee/ci/
- **Render Community**: https://community.render.com

---

## ✅ Checklist Final

- [ ] Código en GitLab
- [ ] Cuenta en Render creada
- [ ] GitLab conectado a Render (OAuth o URL)
- [ ] Web Service creado
- [ ] Variables de entorno configuradas
- [ ] Deploy exitoso
- [ ] Cron-job configurado
- [ ] DNS de Hostinger actualizado
- [ ] SSL funcionando
- [ ] Auto-deploy desde GitLab probado

---

**Última actualización**: Octubre 2025
**Tiempo de setup**: 15 minutos
**Costo mensual**: $0

¡Tu aplicación está lista para producción con GitLab! 🎉

