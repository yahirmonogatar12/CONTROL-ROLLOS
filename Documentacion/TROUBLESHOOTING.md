# Guía de Troubleshooting

> **Última actualización:** Enero 2026

Soluciones a problemas comunes del sistema.

---

## 🔌 Problemas de Conexión

### Error: "No se puede conectar al servidor"

**Síntomas:** La app Flutter muestra error de conexión al iniciar.

**Soluciones:**

1. **Verificar que el backend esté corriendo:**
   ```powershell
   # Ver si el proceso está activo
   Get-Process -Name "backend-server" -ErrorAction SilentlyContinue
   
   # O verificar el puerto
   netstat -an | findstr ":3000"
   ```

2. **Verificar archivo .env:**
   ```env
   DB_HOST=localhost
   DB_PORT=3306
   DB_USER=root
   DB_PASSWORD=tu_password
   DB_NAME=meslocal
   ```

3. **Reiniciar el backend:**
   ```powershell
   # Detener
   taskkill /IM backend-server.exe /F
   
   # Iniciar de nuevo
   .\backend-server.exe
   ```

---

### Error: "ECONNREFUSED" al conectar a MySQL

**Causa:** MySQL no está corriendo o credenciales incorrectas.

**Soluciones:**

1. Verificar servicio MySQL:
   ```powershell
   Get-Service -Name "MySQL*"
   ```

2. Iniciar MySQL si está detenido:
   ```powershell
   Start-Service -Name "MySQL80"
   ```

3. Verificar credenciales en `.env`

4. Probar conexión desde consola:
   ```bash
   mysql -u root -p -h localhost
   ```

---

## 📱 Problemas de App Móvil

### El móvil no encuentra el servidor

**Síntomas:** "No se encontraron servidores" en la pantalla de configuración.

**Soluciones:**

1. **Verificar misma red WiFi:**
   - El móvil debe estar en la misma red que el servidor.

2. **Verificar UDP discovery:**
   - El servidor debe mostrar: `📡 Auto-descubrimiento UDP activo en puerto 3001`

3. **Firewall Windows:**
   ```powershell
   # Permitir puerto 3000 y 3001
   New-NetFirewallRule -DisplayName "MES Backend" -Direction Inbound -Port 3000,3001 -Protocol TCP -Action Allow
   New-NetFirewallRule -DisplayName "MES UDP Discovery" -Direction Inbound -Port 3001 -Protocol UDP -Action Allow
   ```

4. **Configurar servidor manualmente:**
   - Obtener IP del servidor: `ipconfig`
   - Agregar servidor manualmente con IP y puerto 3000

---

### La cámara no reabre después de escanear

**Síntoma:** Después del primer escaneo, la cámara se congela.

**Solución:** Este bug fue corregido en v1.0.4. Actualizar la app.

---

### Error "numero_lote cannot be null" al dar salida

**Síntoma:** Error al registrar salida desde móvil.

**Solución:** Bug corregido en v1.0.4. Actualizar la app.

---

## 🖨️ Problemas de Impresión

### La impresora no imprime etiquetas

**Verificar:**

1. **Impresora conectada y encendida**

2. **Configuración correcta:**
   - Abrir diálogo de configuración de impresora
   - Verificar IP y puerto de la impresora
   - Probar conexión

3. **Puerto 9100 abierto:**
   ```powershell
   Test-NetConnection -ComputerName IP_IMPRESORA -Port 9100
   ```

4. **Formato ZPL correcto:**
   - Las impresoras Zebra usan puerto 9100 por defecto
   - Verificar que el nombre de impresora coincida

---

### Impresión desde móvil no funciona

**Para impresión remota (via servidor):**

1. Verificar que el servidor desktop esté corriendo
2. Verificar configuración de impresora en servidor
3. Verificar endpoint `/api/print` disponible

**Para impresión Bluetooth:**

1. Emparejar impresora en ajustes de Android
2. Verificar permisos Bluetooth en la app
3. Escanear impresoras desde la app

---

## 💾 Problemas de Base de Datos

### Error: "Table doesn't exist"

**Causa:** Tabla no creada por migraciones.

**Solución:**
```bash
cd backend
npm run dev
# Las migraciones se ejecutan automáticamente
```

O ejecutar manualmente:
```javascript
const { runMigrations } = require('./utils/dbMigrations');
await runMigrations();
```

---

### Columna falta en tabla existente

**Síntoma:** Error "Unknown column" al guardar.

**Solución:** Las migraciones agregan columnas automáticamente al reiniciar el servidor. Reiniciar backend.

---

### Datos corruptos o inconsistentes

**Para verificar integridad:**

```sql
-- Verificar entradas sin campo obligatorio
SELECT * FROM control_material_almacen WHERE numero_parte IS NULL OR numero_parte = '';

-- Verificar salidas huérfanas
SELECT s.* FROM control_material_salida s 
LEFT JOIN control_material_almacen e ON s.warehousing_id = e.id 
WHERE e.id IS NULL;

-- Verificar estado IQC inconsistente
SELECT * FROM control_material_almacen 
WHERE iqc_required = 1 AND iqc_status = 'NotRequired';
```

---

## 🔧 Problemas de Compilación

### "Flutter no encontrado"

```powershell
# Verificar instalación
flutter doctor

# Agregar a PATH
$env:PATH += ";C:\flutter\bin"
```

---

### "Inno Setup no encontrado"

Opciones:
1. Instalar desde: https://jrsoftware.org/isdl.php
2. Usar flag `-SkipInstaller`:
   ```powershell
   .\build.ps1 -SkipInstaller
   ```

---

### Error de Visual Studio C++

```powershell
# Instalar Visual Studio 2022 con C++
winget install Microsoft.VisualStudio.2022.Community
```

Luego agregar workload "Desktop development with C++".

---

## 🔍 Diagnóstico General

### Ver logs del servidor

Los logs se muestran en la consola del backend. Para más detalle:

```javascript
// En server.js, habilitar debug
process.env.DEBUG = 'express:*';
```

---

### Health check del servidor

```bash
curl http://localhost:3000/api/health
```

Respuesta esperada:
```json
{
  "status": "OK",
  "database": "Connected",
  "pool": { "active": 2, "idle": 8 }
}
```

---

### Verificar conexiones activas

```sql
SHOW PROCESSLIST;
```

---

## 📞 Contacto Soporte

Si el problema persiste después de seguir esta guía:

1. Recopilar logs del servidor
2. Capturar screenshot del error
3. Describir pasos para reproducir
4. Contactar al equipo de desarrollo

---

*Última actualización: Enero 2026*
