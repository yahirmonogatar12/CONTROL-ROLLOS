# Sistema de Compilación y Distribución
## Control de Almacén - MES

> **Última actualización:** Enero 2026

---

## ⭐ Características

**El backend se compila a un ejecutable standalone (.exe) - NO requiere Node.js instalado en el equipo destino.**

---

## 📋 Requisitos

### Para Compilar:
- **Flutter SDK** (3.0+) - [Instalar Flutter](https://docs.flutter.dev/get-started/install)
- **Node.js** (18+) - Solo para compilar - [Instalar Node.js](https://nodejs.org)
- **Visual Studio 2022** con C++ Desktop Development
- **Inno Setup 6** (opcional, para crear instalador) - [Descargar](https://jrsoftware.org/isdl.php)

### Para Ejecutar (equipo destino):
- **Windows 10/11** (64-bit)
- **MySQL Server** (8.0+)
- ~~Node.js~~ - **NO requerido** ✅

---

## 🚀 Uso del Sistema de Build

### Compilación Básica

```powershell
# Usar la versión en VERSION.txt
.\build.ps1

# Especificar versión manualmente
.\build.ps1 -Version "1.0.1"

# Solo compilar (sin crear instalador)
.\build.ps1 -SkipInstaller

# Limpiar y compilar
.\build.ps1 -Clean
```

### Cambiar Versión

```powershell
# Incrementar patch (1.0.0 → 1.0.1)
.\bump-version.ps1 patch

# Incrementar minor (1.0.0 → 1.1.0)  
.\bump-version.ps1 minor

# Incrementar major (1.0.0 → 2.0.0)
.\bump-version.ps1 major
```

O edita directamente `VERSION.txt`.

---

## 📁 Estructura de Salida

Después de compilar, encontrarás en `dist/`:

```
dist/
├── Control_de_Almacen-v1.0.0/           # Aplicación portable
│   ├── material_warehousing_flutter.exe  # App Flutter
│   ├── backend-server.exe                # Backend compilado (~38 MB)
│   ├── *.dll                             # DLLs de Flutter
│   ├── data/
│   ├── .env.example                      # Plantilla de configuración
│   ├── Iniciar.bat                       # Script de inicio
│   ├── Detener.bat                       # Script para cerrar
│   └── VERSION.txt
│
└── Control_de_Almacen_Setup_v1.0.0.exe   # Instalador
```

---

## 🔧 Configuración

Antes de ejecutar, configura el archivo `.env` (en el mismo directorio que los ejecutables):

```env
# Configuración de Base de Datos
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=tu_password
DB_NAME=meslocal
DB_PORT=3306
```

---

## 📦 Distribución

### Opción 1: Instalador (Recomendado)

1. Ejecuta `Control_de_Almacen_Setup_vX.X.X.exe`
2. Sigue el asistente de instalación
3. Configura `.env` en la carpeta de instalación
4. Ejecuta desde el menú de inicio o escritorio

### Opción 2: Portable

1. Copia la carpeta `Control_de_Almacen-vX.X.X` al equipo destino
2. Renombra `.env.example` a `.env`
3. Configura `.env` con los datos de MySQL
4. Ejecuta `Iniciar.bat` o directamente `material_warehousing_flutter.exe`

---

## ✅ Ventajas del Backend Compilado

| Característica | Antes | Ahora |
|---------------|-------|-------|
| Requiere Node.js | ✅ Sí | ❌ No |
| Tamaño backend | ~50+ MB (node_modules) | ~38 MB (un solo .exe) |
| Archivos backend | Muchos | 1 ejecutable |
| Tiempo de inicio | Lento | Rápido |
| Distribución | Compleja | Simple |

---

## 🗄️ Base de Datos

### Crear la base de datos:

```sql
CREATE DATABASE meslocal;
USE meslocal;

-- Ejecutar el schema
SOURCE database/schema.sql;
```

### Crear usuario de prueba:

```sql
-- Password: admin123 (SHA-256)
INSERT INTO usuarios_sistema (username, password_hash, nombre_completo, departamento, cargo, activo)
VALUES ('admin', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 
        'Administrador', 'IT', 'Admin', 1);
```

---

## 🔄 Flujo de Versiones

1. Desarrollar cambios
2. Probar en modo debug (`flutter run -d windows`)
3. Actualizar `VERSION.txt` con la nueva versión
4. Ejecutar `.\build.ps1`
5. Probar el instalador en un equipo limpio
6. Distribuir

### Convención de Versiones (SemVer):

- **MAJOR.MINOR.PATCH** (ej: 1.2.3)
- **MAJOR**: Cambios incompatibles
- **MINOR**: Nueva funcionalidad compatible
- **PATCH**: Corrección de bugs

---

## ❓ Solución de Problemas

### "Flutter no encontrado"
```powershell
# Verificar instalación
flutter doctor

# Agregar a PATH si es necesario
$env:PATH += ";C:\flutter\bin"
```

### "Inno Setup no encontrado"
- Instalar desde: https://jrsoftware.org/isdl.php
- O usar `-SkipInstaller` para omitir

### "Error de compilación Visual Studio"
```powershell
# Instalar componentes de C++
winget install Microsoft.VisualStudio.2022.Community
# Luego agregar "Desktop development with C++"
```

### "Error conectando a MySQL"
1. Verificar que MySQL esté corriendo
2. Revisar credenciales en `.env`
3. Verificar que la base de datos exista

---

## 📞 Contacto

Para soporte técnico, contactar al equipo de desarrollo.

---

*Última actualización: Enero 2026*
