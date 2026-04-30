-- ============================================
-- TABLA: control_material_almacen_smd (ENTRADAS)
-- ============================================
-- Esta tabla ya existe en tu base de datos con esta estructura:

/*
CREATE TABLE IF NOT EXISTS control_material_almacen_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  forma_material TEXT,                    -- Material Format
  cliente TEXT,                           -- Customer
  codigo_material_original TEXT,          -- Material Original Code
  codigo_material TEXT,                   -- Material Code
  material_importacion_local TEXT,        -- Material Consigned (Import/Local)
  fecha_recibo DATETIME,                  -- Warehousing Date
  fecha_fabricacion DATETIME,             -- Making Date
  cantidad_actual INT,                    -- Current Qty
  numero_lote_material TEXT,              -- Material Lot No
  codigo_material_recibido TEXT,          -- Material Warehousing Code
  numero_parte TEXT,                      -- Part Number
  cantidad_estandarizada TEXT,            -- Packaging Unit
  codigo_material_final TEXT,             -- Final Material Code
  propiedad_material TEXT,                -- Material Property
  especificacion TEXT,                    -- Material Spec
  material_importacion_local_final TEXT,  -- Final Import/Local
  estado_desecho INT,                     -- Disposal Status (0=Active, 1=Disposed)
  ubicacion_salida TEXT,                  -- Location
  fecha_registro DATETIME                 -- Registration Date
);
*/

-- ============================================
-- COLUMNAS ADICIONALES PARA IQC
-- ============================================
-- Ejecutar estas sentencias para agregar soporte IQC:

/*
-- receiving_lot_code: Prefijo del código de etiqueta (primeros 20 chars)
-- Ejemplo: EAE66213501-20251127 (de EAE66213501-202511270006)
ALTER TABLE control_material_almacen_smd 
ADD COLUMN receiving_lot_code VARCHAR(25) NULL AFTER codigo_material_recibido;

-- label_seq: Consecutivo de etiqueta (últimos 4 dígitos)
-- Ejemplo: 6 (de EAE66213501-202511270006)
ALTER TABLE control_material_almacen_smd 
ADD COLUMN label_seq INT NULL AFTER receiving_lot_code;

-- iqc_required: Si el material requiere inspección IQC (0=No, 1=Sí)
ALTER TABLE control_material_almacen_smd 
ADD COLUMN iqc_required TINYINT DEFAULT 0 AFTER label_seq;

-- iqc_status: Estado de la inspección IQC
-- NotRequired: No requiere IQC
-- Pending: Pendiente de inspección
-- InProgress: Inspección en curso
-- Released: Liberado por calidad
-- Rejected: Rechazado
-- Hold: En espera
-- Rework: Para retrabajo
-- Scrap: Para desecho
-- Return: Devolución a proveedor
ALTER TABLE control_material_almacen_smd 
ADD COLUMN iqc_status ENUM('NotRequired','Pending','InProgress','Released','Rejected','Hold','Rework','Scrap','Return') 
DEFAULT 'NotRequired' AFTER iqc_required;

-- Índice para búsquedas rápidas por lote de llegada
CREATE INDEX idx_receiving_lot_code ON control_material_almacen_smd(receiving_lot_code);

-- Índice para búsquedas por estado IQC
CREATE INDEX idx_iqc_status ON control_material_almacen_smd(iqc_status);
*/

-- ============================================
-- TABLA: iqc_inspection_lot_smd (Inspecciones IQC por Lote)
-- ============================================
CREATE TABLE IF NOT EXISTS iqc_inspection_lot_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Identificación del lote
  receiving_lot_code VARCHAR(25) NOT NULL UNIQUE,    -- Lote de llegada (prefijo 20 chars)
  sample_label_code VARCHAR(30) NULL,                -- Código de la etiqueta muestreada
  sample_label_id INT NULL,                          -- FK a control_material_almacen_smd
  
  -- Información del material
  material_code VARCHAR(50) NULL,                    -- Código de material
  part_number VARCHAR(50) NULL,                      -- Número de parte
  customer VARCHAR(100) NULL,                        -- Cliente
  supplier VARCHAR(100) NULL,                        -- Proveedor
  arrival_date DATE NULL,                            -- Fecha de llegada
  
  -- Cantidades del lote
  total_qty_received INT DEFAULT 0,                  -- Cantidad total recibida (suma de etiquetas)
  total_labels INT DEFAULT 0,                        -- Número total de etiquetas del lote
  
  -- Muestreo AQL
  aql_level VARCHAR(20) NULL,                        -- Nivel AQL (0.65, 1.0, 2.5, 4.0, etc.)
  sample_qty INT NULL,                               -- Cantidad de muestras
  qty_sample_ok INT DEFAULT 0,                       -- Muestras OK
  qty_sample_ng INT DEFAULT 0,                       -- Muestras NG
  
  -- Resultados de pruebas (OK, NG, NA, Pending)
  rohs_result ENUM('OK','NG','NA','Pending') DEFAULT 'Pending',
  brightness_result ENUM('OK','NG','NA','Pending') DEFAULT 'Pending',
  dimension_result ENUM('OK','NG','NA','Pending') DEFAULT 'Pending',
  color_result ENUM('OK','NG','NA','Pending') DEFAULT 'Pending',
  
  -- Disposición y estado
  disposition ENUM('Pending','Release','Return','Scrap','Hold','Rework') DEFAULT 'Pending',
  status ENUM('Pending','InProgress','Closed') DEFAULT 'Pending',
  
  -- Auditoría
  inspector VARCHAR(100) NULL,                       -- Nombre del inspector
  inspector_id INT NULL,                             -- ID del usuario inspector
  remarks TEXT NULL,                                 -- Observaciones
  
  -- Timestamps
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  closed_at DATETIME NULL,
  
  -- Foreign Keys
  FOREIGN KEY (sample_label_id) REFERENCES control_material_almacen_smd(id) ON DELETE SET NULL,
  
  -- Índices
  INDEX idx_iqc_status (status),
  INDEX idx_iqc_disposition (disposition),
  INDEX idx_iqc_arrival_date (arrival_date)
);

-- ============================================
-- TABLA: iqc_inspection_detail_smd (Detalle de Mediciones)
-- ============================================
CREATE TABLE IF NOT EXISTS iqc_inspection_detail_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Relación con inspección
  inspection_lot_id INT NOT NULL,                    -- FK a iqc_inspection_lot_smd
  
  -- Identificación de muestra
  sample_number INT NOT NULL,                        -- Número de muestra (1, 2, 3...)
  
  -- Característica medida
  characteristic ENUM('dimension','brightness','color','rohs','other') NOT NULL,
  test_name VARCHAR(100) NOT NULL,                   -- Nombre de la prueba (ej: "Largo", "Ancho", "Delta E")
  
  -- Valores
  measured_value VARCHAR(50) NULL,                   -- Valor medido
  unit VARCHAR(20) NULL,                             -- Unidad (mm, %, etc.)
  min_spec VARCHAR(50) NULL,                         -- Especificación mínima
  max_spec VARCHAR(50) NULL,                         -- Especificación máxima
  
  -- Resultado
  result ENUM('OK','NG') NOT NULL,
  
  -- Auditoría
  remarks TEXT NULL,
  measured_by VARCHAR(100) NULL,
  measured_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  -- Foreign Key
  FOREIGN KEY (inspection_lot_id) REFERENCES iqc_inspection_lot_smd(id) ON DELETE CASCADE,
  
  -- Índices
  INDEX idx_detail_lot (inspection_lot_id),
  INDEX idx_detail_characteristic (characteristic)
);

-- ============================================
-- MAPEO DE CAMPOS UI -> BASE DE DATOS
-- ============================================
/*
| Campo UI (Flutter)         | Campo BD                        |
|----------------------------|---------------------------------|
| Material Format            | forma_material                  |
| Customer                   | cliente                         |
| Material Original Code     | codigo_material_original        |
| Material Code              | codigo_material                 |
| Material Consigned         | material_importacion_local      |
| Warehousing Date           | fecha_recibo                    |
| Making Date                | fecha_fabricacion               |
| Current Qty                | cantidad_actual                 |
| Material Lot No            | numero_lote_material            |
| Material Warehousing Code  | codigo_material_recibido        |
| Part Number                | numero_parte                    |
| Packaging Unit             | cantidad_estandarizada          |
| Material Property          | propiedad_material              |
| Material Spec              | especificacion                  |
| Location                   | ubicacion_salida                |
| Disposal                   | estado_desecho                  |
*/

-- ============================================
-- TABLA: material_return_smd (Devolución de Material)
-- ============================================
CREATE TABLE IF NOT EXISTS material_return_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Referencia a la entrada original
  warehousing_id INT NULL,                           -- FK a control_material_almacen_smd
  material_warehousing_code VARCHAR(50) NOT NULL,    -- Código de entrada original
  
  -- Información del material
  material_code VARCHAR(50) NULL,                    -- Código de material
  part_number VARCHAR(50) NULL,                      -- Número de parte
  material_lot_no VARCHAR(100) NULL,                 -- Lote de material
  packaging_unit VARCHAR(50) NULL,                   -- Unidad de empaque
  material_spec TEXT NULL,                           -- Especificación del material
  
  -- Cantidades
  remain_qty INT DEFAULT 0,                          -- Cantidad disponible antes de devolver
  return_qty INT DEFAULT 0,                          -- Cantidad devuelta
  loss_qty INT DEFAULT 0,                            -- Cantidad perdida/merma
  
  -- Fechas
  return_datetime DATETIME DEFAULT CURRENT_TIMESTAMP, -- Fecha/hora de devolución
  
  -- Auditoría
  returned_by VARCHAR(100) NULL,                     -- Usuario que realizó la devolución
  returned_by_id INT NULL,                           -- ID del usuario
  remarks TEXT NULL,                                 -- Observaciones
  
  -- Timestamps
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  -- Foreign Keys
  FOREIGN KEY (warehousing_id) REFERENCES control_material_almacen_smd(id) ON DELETE SET NULL,
  
  -- Índices
  INDEX idx_return_warehousing_code (material_warehousing_code),
  INDEX idx_return_datetime (return_datetime),
  INDEX idx_return_part_number (part_number)
);
