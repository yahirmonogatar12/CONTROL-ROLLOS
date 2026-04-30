# Changelog

Todos los cambios notables del proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/),
y este proyecto sigue [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.8] - 2026-01-05

### Documentación
- Actualizada toda la documentación a Enero 2026
- Añadido archivo `database-schema.md` con schema completo de BD
- Añadido archivo `CHANGELOG.md`
- Añadido archivo `TROUBLESHOOTING.md`
- Corregida información de módulos (14 controllers, 16 rutas)
- Añadido módulo Blacklist a la documentación
- Removidos módulos IPM/Raw-IPM de la documentación

---

## [1.0.7] - 2025-12

### Añadido
- Módulo de lista negra (Blacklist) para lotes problemáticos
- Logging detallado para diagnóstico de escaneos perdidos
- División de lotes para salidas parciales

### Mejorado
- Corrección de errores en autocompletado de scan
- Mejor manejo de timeouts en escaneos

---

## [1.0.6] - 2025-12

### Añadido
- Pantalla KPI para televisión en ventana separada
- Soporte multi-ventana con window_manager

### Mejorado
- Refactorización del layout principal para evitar overflow
- Aplicación de paleta de colores oficial

---

## [1.0.5] - 2025-11

### Añadido
- Columna "Entregadas assy" en plan de producción
- Selector de plan/lote en modal de asignación de salida
- Campo de fecha con valor default en modal de edición admin

### Corregido
- Visualización correcta de columna Status después de añadir nueva columna
- Índices de columnas en funciones de actualización

---

## [1.0.4] - 2025-12

### Añadido
- App móvil completa con 6 pantallas
  - Mobile Entry (recepción con cámara)
  - Mobile Outgoing (salidas con cámara)
  - Mobile Inventory (consulta de inventario)
  - Mobile Audit (auditoría física)
  - Mobile Label Assignment (asignación de etiquetas)
  - Mobile Home Scaffold (navegación)
- Auto-descubrimiento de servidor por UDP
- Impresión Bluetooth desde móvil
- Impresión remota via servidor desktop
- Sistema de traducciones móviles (EN/ES/KO)

### Mejorado
- Configuración de servidor dinámica (múltiples perfiles)
- Backend accesible desde red local (0.0.0.0)

### Corregido
- Bug de cámara que no reabre después del primer escaneo
- Error `numero_lote cannot be null` en salidas móviles

---

## [1.0.3] - 2025-11

### Añadido
- Módulo de auditoría de inventario físico
- Sincronización en tiempo real via WebSocket
- Tabla `inventory_audit` y relacionadas

### Mejorado
- Rate limiting para múltiples dispositivos móviles

---

## [1.0.2] - 2025-11

### Añadido
- Módulo de devolución de material a proveedor
- Tabla `material_return`
- Solicitudes de cancelación con aprobación

### Mejorado
- Migración automática de base de datos al iniciar servidor

---

## [1.0.1] - 2025-10

### Añadido
- Módulo IQC completo con muestreo AQL
- Especificaciones de calidad por material
- Módulo de cuarentena
- 5 tipos de prueba: ROHS, Brightness, Dimension, Color, Appearance

### Mejorado
- Backend modularizado (controllers + routes separados)
- Documentación de permisos

---

## [1.0.0] - 2025-09

### Inicial
- Lanzamiento inicial del sistema
- Módulos base: Warehousing, Outgoing, Material Control
- Gestión de usuarios y permisos
- Impresión de etiquetas ZPL
- Exportación a Excel
- Soporte multi-idioma (EN/ES/KO)
- Build system con PowerShell
- Instalador Inno Setup

---

## Leyenda

- **Añadido** - Nuevas funcionalidades
- **Mejorado** - Cambios en funcionalidades existentes
- **Corregido** - Corrección de bugs
- **Eliminado** - Funcionalidades eliminadas
- **Seguridad** - Correcciones de vulnerabilidades
- **Documentación** - Cambios solo en documentación
