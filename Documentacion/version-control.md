# Control de Versiones

> **Última actualización:** Enero 2026

## Esquema de Versionado

El proyecto utiliza **Semantic Versioning 2.0.0** (SemVer):

```
MAJOR.MINOR.PATCH
  │      │     └── Correcciones de bugs, cambios menores
  │      └── Nuevas funcionalidades retrocompatibles
  └── Cambios incompatibles con versiones anteriores
```

**Ejemplo:** `1.1.1`
- `1` = Major (cambios que rompen compatibilidad)
- `1` = Minor (nuevas funcionalidades)
- `1` = Patch (correcciones de bugs)

---

## Archivo VERSION.txt

Fuente única de verdad para la versión de la aplicación.

**Ubicación:** `./VERSION.txt` (raíz del proyecto)

**Formato:** Una sola línea con el número de versión
```
1.1.1
```

### Cómo se usa

| Componente | Archivo | Uso |
|------------|---------|-----|
| **Build system** | `build.ps1` | Lee versión para nombrar instalador |
| **Flutter app** | `launcher_screen.dart` | Muestra versión en UI |
| **Update service** | `update_service.dart` | Compara con servidor para updates |
| **Publish script** | `publish_version.js` | Lee/actualiza al publicar |

---

## Archivos del Sistema

### 1. VERSION.txt
```
1.1.1
```
- Única fuente de verdad
- Se copia al directorio de distribución durante el build

### 2. CHANGELOG.md
- Historial de cambios por versión
- Formato [Keep a Changelog](https://keepachangelog.com/)
- Secciones: Añadido, Mejorado, Corregido, Eliminado

### 3. build.ps1
```powershell
# Compilar con versión del archivo
.\build.ps1

# Compilar con versión específica (actualiza VERSION.txt)
.\build.ps1 -Version "1.1.2"
```

### 4. publish_version.js
```bash
# Publicar nueva versión (modo interactivo)
cd backend
node publish_version.js

# Con parámetros
node publish_version.js --version 1.1.1 --mandatory
```
Registra versiones en tabla `app_versions` para notificar actualizaciones.

---

## Flujo de Release

### 1. Desarrollo Completo
```bash
# Hacer cambios
git add .
git commit -m "feat: nueva funcionalidad"
```

### 2. Actualizar Versión
```bash
# Editar VERSION.txt con nueva versión
echo "1.1.1" > VERSION.txt
```

### 3. Documentar Cambios
```markdown
## [1.1.1] - 2026-01-06

### Añadido
- Nueva funcionalidad X
- Corrección de bug Y
```

### 4. Commit de Versión
```bash
git add VERSION.txt CHANGELOG.md
git commit -m "release: v1.1.1"
git tag v1.1.1
git push origin main --tags
```

### 5. Compilar
```powershell
.\build.ps1
# Genera: dist/Control_de_Almacen-v1.1.1/
# Genera: dist/Control_de_Almacen_Setup_v1.1.1.exe
```

### 6. Publicar (Opcional)
```bash
cd backend
node publish_version.js
# Registra en BD para notificar a usuarios
```

---

## Lectura de Versión en la App

```dart
// En launcher_screen.dart
Future<void> _loadVersion() async {
  // Intenta leer de: 
  // 1. <exe_dir>/VERSION.txt (release)
  // 2. ./VERSION.txt (debug)
  // 3. Default: "1.0.0"
}
```

La versión se muestra en:
- Pantalla de login (esquina inferior)
- Pantalla principal (título de ventana)

---

## Convenciones de Commits

| Prefijo | Uso | Ejemplo |
|---------|-----|---------|
| `feat:` | Nueva funcionalidad | `feat: agregar impresión de etiqueta actualizada` |
| `fix:` | Corrección de bug | `fix: corregir error de escaneo` |
| `docs:` | Documentación | `docs: actualizar README` |
| `refactor:` | Mejora de código | `refactor: simplificar lógica de validación` |
| `release:` | Bump de versión | `release: v1.1.1` |
