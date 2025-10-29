# 🚀 Guía Rápida de Deploy - Koyeb

## ✅ Archivos creados para el deploy:
- `Dockerfile` - Configuración de Docker con Chromium
- `ecosystem.config.js` - PM2 para correr frontend + backend
- `.dockerignore` - Archivos a ignorar en Docker
- `DEPLOYMENT.md` - Guía completa de deployment

## 📝 Pasos Rápidos:

### 1️⃣ Subir a GitHub (5 minutos)

```bash
# Si no tienes repositorio en GitHub, créalo primero en github.com
# Luego ejecuta:

git add .
git commit -m "Ready for Koyeb deployment"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/TU_REPO.git
git push -u origin main
```

### 2️⃣ Deploy en Koyeb (5-10 minutos)

1. Ve a https://app.koyeb.com/
2. Click **"Create App"**
3. Selecciona **"GitHub"**
4. Autoriza Koyeb en tu cuenta de GitHub
5. Selecciona tu repositorio `wpaudit`

**Configuración del servicio:**
```
Builder: Docker
Dockerfile: Dockerfile (default)
Port: 3000
Regions: Elegir la más cercana (ej: Frankfurt, Paris, etc.)
Instance: Free (Nano - 0.5GB RAM)
```

**Variables de entorno:**
```
NODE_ENV = production
```

6. Click **"Deploy"**
7. Espera 5-10 minutos

### 3️⃣ Conectar tu dominio de Hostinger (10 minutos)

**En Koyeb:**
1. Ve a tu app → **"Domains"**
2. Click **"Add domain"**
3. Escribe tu dominio: `tudominio.com`
4. Copia los valores CNAME que te da Koyeb

**En Hostinger:**
1. Ve a **Dominios** → Tu dominio → **DNS Zone**
2. Agrega estos registros:

```
Tipo: CNAME
Host: @
Apunta a: [la URL que te dio Koyeb]
TTL: 3600
```

```
Tipo: CNAME  
Host: www
Apunta a: [la URL que te dio Koyeb]
TTL: 3600
```

3. Guarda cambios
4. Espera 5-60 minutos para propagación DNS

### 4️⃣ Verificar SSL

Koyeb activará automáticamente SSL (HTTPS) para tu dominio.
Puede tardar 5-10 minutos adicionales.

---

## 🎉 ¡Listo!

Tu aplicación estará disponible en:
- `https://tu-app.koyeb.app` (URL temporal de Koyeb)
- `https://tudominio.com` (tu dominio personalizado)

---

## ⚠️ Posibles Problemas:

### "Build failed" o "Out of memory"
→ El plan gratuito de Koyeb (0.5GB RAM) puede ser insuficiente para Lighthouse
→ **Solución**: Migrar a Railway ($5-10/mes con más recursos)

### "Chromium not found"
→ Revisa los logs de Koyeb
→ Verifica que el Dockerfile instaló Chromium correctamente

### La app se "duerme" o es lenta
→ Koyeb free tier NO tiene sleep
→ Puede ser lento por poca RAM
→ **Solución**: Upgrade a plan Eco ($5/mes) o usar Railway

---

## 💡 ¿Necesitas ayuda?

1. Revisa los logs en Koyeb Dashboard
2. Testea localmente con Docker:
   ```bash
   docker build -t wpaudit .
   docker run -p 3000:3000 wpaudit
   ```
3. Si no funciona en Koyeb, avísame y migramos a Railway

---

## 🔄 Próximos pasos después del deploy:

- [ ] Verificar que el scan funciona
- [ ] Probar con diferentes URLs
- [ ] Verificar que las screenshots se guardan
- [ ] Configurar monitoreo (opcional)
- [ ] Agregar Google Analytics (opcional)

