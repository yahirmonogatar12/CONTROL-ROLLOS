# Product Overview

> **Última actualización:** Enero 2026

## Descripción

**Material Warehousing Control System** - Sistema de gestión de almacén de materiales para entornos de manufactura. Disponible en versión Desktop (Windows) y Mobile (Android/iOS).

---

## Propósito

Gestiona el ciclo de vida completo de materiales en almacén:

| Fase | Funcionalidad |
|------|---------------|
| **Entrada** | Recepción de material con generación de etiquetas |
| **Inspección** | Control de calidad entrante (IQC) con muestreo AQL |
| **Almacenamiento** | Tracking de inventario con FIFO |
| **Salida** | Despacho con validación de BOM y FIFO |
| **Devolución** | Retorno de material a proveedor |
| **Auditoría** | Inventario físico con verificación en tiempo real |

---

## Módulos del Sistema

### Desktop App (15 módulos)

| Módulo | Descripción | Departamentos con Acceso |
|--------|-------------|-------------------------|
| **Material Warehousing** | Recepción y registro de material | Almacén, Sistemas, Gerencia |
| **Material Outgoing** | Salidas de material con validación BOM | Almacén, Sistemas, Gerencia |
| **Material Return** | Devolución de material a proveedor | Almacén, Calidad, Sistemas |
| **Material Control** | Catálogo de materiales | Sistemas, Gerencia |
| **IQC Inspection** | Inspección de calidad entrante | Calidad, Sistemas |
| **Quality Specs** | Especificaciones de calidad | Calidad, Sistemas |
| **Quarantine** | Gestión de material en cuarentena | Calidad, Sistemas |
| **Long-Term Inventory** | Inventario de lotes y aging | Todos (lectura) |
| **Inventory Audit** | Auditoría de inventario físico | Almacén, Sistemas |
| **Blacklist** | Lista negra de lotes | Sistemas, Calidad |
| **User Management** | Administración de usuarios | Sistemas |

### Mobile App (6 pantallas)

| Pantalla | Descripción |
|----------|-------------|
| **Mobile Entry** | Escaneo y registro de material entrante |
| **Mobile Outgoing** | Escaneo para salidas de material |
| **Mobile Inventory** | Consulta rápida de inventario |
| **Mobile Audit** | Escaneo para auditoría física |
| **Mobile Label Assignment** | Asignación de etiquetas |
| **Remote Printing** | Envío de trabajos de impresión al servidor |

---

## Características Clave

### Multi-idioma
- Inglés (English)
- Español
- Coreano (한국어)

### Escaneo de Códigos
- Soporte para códigos de barras y QR
- Escaneo por cámara (mobile)
- Lectores de códigos USB (desktop)

### Inspección de Calidad (IQC)
- Muestreo basado en niveles AQL
- Múltiples tipos de prueba (ROHS, Brightness, Dimension, Color)
- Disposiciones: Release, Return, Scrap, Hold, Rework

### Exportación de Datos
- Exportación a Excel
- Impresión de etiquetas ZPL
- Generación de reportes

### Control de Acceso
- Autenticación por usuario
- Permisos basados en departamento
- Modo solo lectura para usuarios sin permisos

### Mobile Features
- **Auto-discovery:** Encuentra automáticamente el servidor en la red
- **Remote printing:** Imprime etiquetas desde móvil via servidor desktop
- **Offline feedback:** Audio y vibración para confirmar operaciones
- **Camera scanning:** Escaneo rápido de códigos de barras

---

## Usuarios Objetivo

| Rol | Módulos Principales |
|-----|---------------------|
| **Personal de Almacén** | Warehousing, Outgoing, Inventory |
| **Inspectores de Calidad** | IQC, Quality Specs, Quarantine |
| **Supervisores** | Todos los módulos (lectura/escritura) |
| **Administradores** | User Management, configuración |
| **Operadores Móviles** | Mobile Entry, Mobile Outgoing, Mobile Audit |

---

## Dominio de Negocio

### Trazabilidad de Material
- Código único por etiqueta (`codigo_material_recibido`)
- Agrupación por lote (`receiving_lot_code`)
- Historial completo de movimientos

### Cumplimiento FIFO
- Validación automática de antigüedad
- Alertas para material antiguo
- Reportes de aging

### Validación de BOM
- Verificación de materiales requeridos
- Control de cantidades
- Prevención de errores de entrega

### Control de Calidad
- Gates de calidad antes de liberación
- Muestreo estadístico (AQL)
- Gestión de no conformidades
- Cuarentena de material defectuoso

### Auditoría de Inventario
- Conteo físico vs sistema
- Reconciliación de diferencias
- Sincronización en tiempo real (móvil ↔ desktop)

---

## Integración

### Base de Datos
- MySQL local (`meslocal`)
- Estructura relacional con foreign keys
- Triggers para cálculos automáticos

### Impresión
- Impresoras ZPL (Zebra)
- Impresión local (desktop)
- Impresión remota (mobile → desktop)

### Red
- API REST (HTTP)
- UDP discovery para móviles
- Operación en red local (sin internet requerido)
