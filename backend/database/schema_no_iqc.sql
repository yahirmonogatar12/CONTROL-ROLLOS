-- Schema without IQC tables/columns

CREATE TABLE IF NOT EXISTS control_material_almacen_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  forma_material TEXT,
  cliente TEXT,
  codigo_material_original TEXT,
  codigo_material TEXT,
  material_importacion_local TEXT,
  fecha_recibo DATETIME,
  fecha_fabricacion DATETIME,
  cantidad_actual INT,
  numero_lote_material TEXT,
  codigo_material_recibido TEXT,
  numero_parte TEXT,
  cantidad_estandarizada TEXT,
  codigo_material_final TEXT,
  propiedad_material TEXT,
  especificacion TEXT,
  material_importacion_local_final TEXT,
  estado_desecho INT,
  ubicacion_salida TEXT,
  ubicacion_destino VARCHAR(100),
  vendedor VARCHAR(100),
  usuario_registro VARCHAR(150),
  unidad_medida VARCHAR(10),
  fecha_registro DATETIME
);

CREATE TABLE IF NOT EXISTS material_return_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  warehousing_id INT NULL,
  material_warehousing_code VARCHAR(50) NOT NULL,
  material_code VARCHAR(50) NULL,
  part_number VARCHAR(50) NULL,
  material_lot_no VARCHAR(100) NULL,
  packaging_unit VARCHAR(50) NULL,
  material_spec TEXT NULL,
  remain_qty INT DEFAULT 0,
  return_qty INT DEFAULT 0,
  loss_qty INT DEFAULT 0,
  return_datetime DATETIME DEFAULT CURRENT_TIMESTAMP,
  returned_by VARCHAR(100) NULL,
  returned_by_id INT NULL,
  remarks TEXT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (warehousing_id) REFERENCES control_material_almacen_smd(id) ON DELETE SET NULL,
  INDEX idx_return_warehousing_code (material_warehousing_code),
  INDEX idx_return_datetime (return_datetime),
  INDEX idx_return_part_number (part_number)
);

-- ============================================
-- TABLAS: REQUERIMIENTOS (COMPARTIDAS)
-- ============================================
CREATE TABLE IF NOT EXISTS material_requirements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  codigo_requerimiento VARCHAR(20) NULL UNIQUE,
  area_destino VARCHAR(50) NOT NULL,
  modelo VARCHAR(100) NULL,
  fecha_requerida DATE NOT NULL,
  turno VARCHAR(20) NULL,
  status ENUM('Pendiente', 'En Preparación', 'Listo', 'Entregado', 'Cancelado') DEFAULT 'Pendiente',
  prioridad ENUM('Normal', 'Urgente', 'Crítico') DEFAULT 'Normal',
  notas TEXT NULL,
  creado_por VARCHAR(100) NOT NULL,
  fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
  actualizado_por VARCHAR(100) NULL,
  fecha_actualizacion DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_fecha_requerida (fecha_requerida),
  INDEX idx_status (status),
  INDEX idx_area (area_destino),
  INDEX idx_prioridad (prioridad),
  INDEX idx_codigo (codigo_requerimiento)
);

CREATE TABLE IF NOT EXISTS material_requirement_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  requirement_id INT NOT NULL,
  numero_parte VARCHAR(50) NOT NULL,
  descripcion VARCHAR(200) NULL,
  cantidad_requerida INT NOT NULL,
  cantidad_preparada INT DEFAULT 0,
  cantidad_entregada INT DEFAULT 0,
  status ENUM('Pendiente', 'Parcial', 'Preparado', 'Entregado') DEFAULT 'Pendiente',
  codigos_salida TEXT NULL,
  notas TEXT NULL,
  FOREIGN KEY (requirement_id) REFERENCES material_requirements(id) ON DELETE CASCADE,
  INDEX idx_requirement (requirement_id),
  INDEX idx_numero_parte (numero_parte),
  INDEX idx_status (status)
);

-- ============================================
-- TABLA: ENTRADAS SMD (PENDIENTES) + CONFIRMACIÓN
-- ============================================
CREATE TABLE IF NOT EXISTS control_material_entrada_smd (
  id INT AUTO_INCREMENT PRIMARY KEY,
  codigo_material_recibido TEXT,
  numero_parte TEXT,
  numero_lote TEXT,
  modelo TEXT,
  vendedor VARCHAR(100),
  depto_salida TEXT,
  proceso_salida TEXT,
  cantidad_salida DECIMAL(10,2),
  fecha_salida DATETIME,
  fecha_registro DATETIME,
  especificacion_material TEXT,
  usuario_registro VARCHAR(150),
  cancelado TINYINT DEFAULT 0,
  confirmado TINYINT DEFAULT 0,
  confirmado_por VARCHAR(150) NULL,
  confirmado_at DATETIME NULL,
  rechazado TINYINT DEFAULT 0,
  rechazado_por VARCHAR(150) NULL,
  rechazado_at DATETIME NULL,
  rechazado_motivo TEXT NULL,
  INDEX idx_fecha_salida (fecha_salida),
  INDEX idx_confirmado (confirmado),
  INDEX idx_rechazado (rechazado)
);

-- Si la tabla ya existe, ejecutar solo si faltan columnas:
-- ALTER TABLE control_material_entrada_smd ADD COLUMN confirmado TINYINT DEFAULT 0;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN confirmado_por VARCHAR(150) NULL;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN confirmado_at DATETIME NULL;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN rechazado TINYINT DEFAULT 0;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN rechazado_por VARCHAR(150) NULL;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN rechazado_at DATETIME NULL;
-- ALTER TABLE control_material_entrada_smd ADD COLUMN rechazado_motivo TEXT NULL;

-- Si control_material_almacen_smd ya existe, agregar columnas faltantes:
-- ALTER TABLE control_material_almacen_smd ADD COLUMN vendedor VARCHAR(100) NULL;
-- ALTER TABLE control_material_almacen_smd ADD COLUMN usuario_registro VARCHAR(150) NULL;
-- ALTER TABLE control_material_almacen_smd ADD COLUMN unidad_medida VARCHAR(10) NULL;
