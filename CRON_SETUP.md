# ⏰ Configurar Cron Job - Mantener Render Despierto

## 🎯 Objetivo

Hacer ping cada 10 minutos para evitar que Render.com duerma tu aplicación (free tier).

---

## 📝 Paso a Paso

### 1. Crear Cuenta en cron-job.org

1. Ve a: https://cron-job.org/en/signup/
2. Completa el formulario:
   ```
   Email: tu-email@gmail.com
   Password: [tu contraseña segura]
   ```
3. Click **"Sign up"**
4. Revisa tu email y **verifica la cuenta**

---

### 2. Login y Crear Cron Job

1. https://cron-job.org/en/members/
2. Login con tus credenciales
3. Dashboard → Click **"CREATE CRONJOB"**

---

### 3. Configuración del Cron Job

#### General Settings:
```
Title: Keep Just Speed It Awake
```

#### URL:
```
https://justspeedit.onrender.com/api/health
```

O si ya configuraste tu dominio:
```
https://justspeedit.com/api/health
```

#### Schedule:
```
☑ Every 10 minutes
```

Alternativamente, configuración manual:
```
Minutes: */10
Hours: *
Days: *
Months: *
Weekdays: *
```

#### Request Settings:
```
Request method: GET
Request timeout: 30 seconds
```

#### Execution:
```
☑ Enabled
```

#### Notification (Opcional):
```
☐ None
```
O si quieres alertas:
```
☑ Only on errors
Email: tu-email@gmail.com
```

---

### 4. Guardar y Activar

1. Click **"CREATE CRONJOB"**
2. Verás tu cron job en la lista
3. Status debería ser: ✅ **Enabled**

---

## ✅ Verificación

### Inmediatamente:

1. En cron-job.org → Tu cronjob → **"Run now"**
2. Deberías ver:
   ```
   Status: 200 OK
   Response time: ~500ms
   ```

### Monitorear:

1. Tab **"History"** muestra todas las ejecuciones
2. Cada 10 minutos verás una nueva entrada
3. Todas deberían ser: ✅ Success (200)

---

## 📊 Dashboard de Cron-job.org

### Lo que verás:

```
┌─────────────────────────────────────────────┐
│ Keep Just Speed It Awake        ✅ Enabled │
├─────────────────────────────────────────────┤
│ URL: justspeedit.com/api/health            │
│ Schedule: Every 10 minutes                  │
│ Last execution: 2 minutes ago ✅            │
│ Next execution: in 8 minutes                │
│ Success rate: 100% (144/144)                │
└─────────────────────────────────────────────┘
```

---

## 🔧 Troubleshooting

### ❌ Error: "Connection timeout"

**Causa**: Tu app en Render está dormida y tarda >30s en despertar

**Solución**:
1. Aumenta timeout a 60 segundos
2. O cambia intervalo a cada 5 minutos

### ❌ Error: "404 Not Found"

**Causa**: URL incorrecta

**Solución**:
1. Verifica que `/api/health` existe
2. Prueba manualmente en navegador: `https://justspeedit.com/api/health`
3. Deberías ver: `{"status":"ok","timestamp":"..."}`

### ❌ Error: "Too many requests"

**Causa**: Cron configurado muy frecuente

**Solución**:
1. Cambia a cada 10-15 minutos
2. Render free tier tolera hasta 6 pings/hora

---

## 💡 Tips

### Ping inteligente:

Si agregas este endpoint al API (`api/src/index.ts`):

```typescript
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    memory: process.memoryUsage()
  })
})
```

Puedes monitorear:
- Cuánto tiempo lleva corriendo
- Uso de memoria
- Si reinició recientemente

---

## 📈 Estadísticas Esperadas

Con cron cada 10 minutos:

| Métrica | Valor |
|---------|-------|
| Pings/hora | 6 |
| Pings/día | 144 |
| Pings/mes | ~4,320 |
| Uptime | 99.9% |
| Tiempo dormido | ~0% |

---

## 🎯 Resultado Final

Con esto configurado:

✅ Tu sitio responde instantáneamente 24/7  
✅ No hay "cold starts" de 30-60 segundos  
✅ 100% gratis  
✅ Set and forget

---

## 🆓 Alternativas Gratuitas

Si cron-job.org no te funciona, prueba:

1. **UptimeRobot.com**
   - 50 monitors gratis
   - Ping cada 5 minutos
   - https://uptimerobot.com

2. **Freshping.io**
   - 50 endpoints gratis
   - Ping cada 1 minuto
   - https://freshping.io

3. **GitHub Actions** (más técnico)
   - Cron schedule en workflow
   - Totalmente gratis
   - Requiere crear workflow file

---

**Última actualización**: Octubre 2025  
**Tiempo de setup**: 3 minutos  
**Costo**: $0

