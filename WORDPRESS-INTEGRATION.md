# 🚀 Just Speed It - Widget para WordPress

## 📋 Guía de Instalación

### Opción 1: Usando un Plugin (Recomendado)

#### Paso 1: Instalar Plugin
Instala uno de estos plugins en tu WordPress:
- **Insert Headers and Footers** (más popular)
- **Code Snippets**
- **WPCode**

#### Paso 2: Agregar el Widget

1. Ve a tu WordPress Admin
2. Si usas **Insert Headers and Footers**:
   - Ve a `Settings > Insert Headers and Footers`
   - En la sección "Body", pega el siguiente código:

```html
<!-- Just Speed It Widget -->
<div id="justspeedit-widget"></div>
<script>
  window.JUSTSPEEDIT_API_URL = 'https://wpaudit-production.up.railway.app';
</script>
<script src="https://wpaudit-production.up.railway.app/api/widget" defer></script>
```

3. Guarda los cambios
4. **¡Listo!** El widget aparecerá en tu página

---

### Opción 2: Usando un Shortcode (Para más control)

Si quieres controlar exactamente dónde aparece el widget:

#### Paso 1: Crear el Shortcode

1. Ve a `Appearance > Theme File Editor`
2. Abre `functions.php`
3. Agrega este código al final:

```php
<?php
// Just Speed It Widget Shortcode
function justspeedit_widget_shortcode() {
    ob_start();
    ?>
    <div id="justspeedit-widget"></div>
    <script>
      window.JUSTSPEEDIT_API_URL = 'https://wpaudit-production.up.railway.app';
    </script>
    <script src="https://wpaudit-production.up.railway.app/api/widget" defer></script>
    <?php
    return ob_get_clean();
}
add_shortcode('justspeedit', 'justspeedit_widget_shortcode');
?>
```

#### Paso 2: Usar el Shortcode

Ahora puedes usar el shortcode en cualquier página o post:

```
[justspeedit]
```

O en un template PHP:

```php
<?php echo do_shortcode('[justspeedit]'); ?>
```

---

### Opción 3: Directamente en un Template

Si quieres agregarlo a una página específica (ej: página de inicio):

1. Ve a `Appearance > Theme File Editor`
2. Abre el template donde quieres el widget (ej: `page.php`, `front-page.php`)
3. Agrega este código donde quieras que aparezca:

```php
<div id="justspeedit-widget"></div>
<script>
  window.JUSTSPEEDIT_API_URL = 'https://wpaudit-production.up.railway.app';
</script>
<script src="https://wpaudit-production.up.railway.app/api/widget" defer></script>
```

---

## 🎨 Personalización

### Cambiar el Ancho Máximo

Agrega CSS personalizado en `Appearance > Customize > Additional CSS`:

```css
.jsi-widget {
  max-width: 1200px !important;
}
```

### Cambiar Colores

```css
/* Cambiar color del botón */
.jsi-button {
  background: #10B981 !important; /* Verde */
}

.jsi-button:hover {
  background: #059669 !important;
}

/* Cambiar color del título */
.jsi-title {
  color: #1F2937 !important;
}
```

---

## 🔧 Configuración Avanzada

### Cambiar la URL de la API

Si cambias tu deployment de Railway, actualiza la URL:

```html
<script>
  window.JUSTSPEEDIT_API_URL = 'https://tu-nueva-url.up.railway.app';
</script>
```

### Deshabilitar Redirección Automática

Si prefieres que NO redirija automáticamente después del scan:

```html
<script>
  window.JUSTSPEEDIT_REDIRECT = false;
</script>
```

---

## ✅ Verificación

Después de instalar:

1. Visita tu página donde agregaste el widget
2. Deberías ver:
   - Título: "Speed audit will never be the same again."
   - Campo de texto para URL
   - Botón "Get Started"
   - Badges: "Free forever", "No credit card", "Results in 60s"

3. Prueba ingresar una URL y hacer clic en "Get Started"
4. Deberías ser redirigido a la página de escaneo

---

## 🐛 Troubleshooting

### El widget no aparece
- Verifica que el código está correctamente pegado
- Limpia el caché de WordPress (si usas plugin de caché)
- Abre la consola del navegador (F12) y busca errores

### Error de CORS
- Verifica que tu dominio está en la whitelist del backend
- Contacta al administrador del sistema

### El botón no funciona
- Verifica que Railway está funcionando: `https://wpaudit-production.up.railway.app/health`
- Limpia el caché del navegador

---

## 📞 Soporte

Si tienes problemas, verifica:
1. La consola del navegador (F12 > Console)
2. El estado de Railway: `https://wpaudit-production.up.railway.app/health`

---

## 🎯 Ejemplo Completo

Para una página landing completa, usa este HTML en un template o en Elementor/Gutenberg:

```html
<div style="padding: 60px 20px; background: linear-gradient(to bottom, #f0fdf4, #ffffff);">
  <div style="max-width: 1200px; margin: 0 auto;">
    
    <!-- Widget -->
    <div id="justspeedit-widget"></div>
    
    <!-- Features (Opcional) -->
    <div style="margin-top: 80px; text-align: center;">
      <h2 style="font-size: 2rem; font-weight: bold; margin-bottom: 40px;">
        Powered by Google Lighthouse
      </h2>
      <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 30px;">
        <div>
          <h3>⚡ Core Web Vitals</h3>
          <p>Real LCP, CLS, FID scores</p>
        </div>
        <div>
          <h3>🔒 Security Scan</h3>
          <p>Find vulnerabilities</p>
        </div>
        <div>
          <h3>📈 SEO Analysis</h3>
          <p>Meta tags & structured data</p>
        </div>
      </div>
    </div>
    
  </div>
</div>

<!-- Scripts -->
<script>
  window.JUSTSPEEDIT_API_URL = 'https://wpaudit-production.up.railway.app';
</script>
<script src="https://wpaudit-production.up.railway.app/api/widget" defer></script>
```

---

## 🚀 URL de Railway

Tu aplicación está desplegada en Railway. Las URLs serán algo como:
- **App**: `https://wpaudit-production.up.railway.app` 
- **Widget**: `https://wpaudit-production.up.railway.app/api/widget`
- **Health Check**: `https://wpaudit-production.up.railway.app/health`

**IMPORTANTE**: Reemplaza `wpaudit-production.up.railway.app` con tu URL real de Railway en todos los ejemplos de código.

