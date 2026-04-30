/**
 * Migraciones automáticas de base de datos
 * Agrega columnas y tablas necesarias si no existen
 */
const { pool } = require('../config/database');

// Helper para agregar columna si no existe
async function addColumnIfNotExists(table, columnName, definition) {
  try {
    const [rows] = await pool.query(`
      SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
      AND TABLE_NAME = ? 
      AND COLUMN_NAME = ?
    `, [table, columnName]);

    if (rows.length === 0) {
      await pool.query(`ALTER TABLE ${table} ADD COLUMN ${columnName} ${definition}`);
      console.log(`✓ Columna "${columnName}" agregada a ${table}`);
      return true;
    }
    return false;
  } catch (err) {
    console.log(`Nota: Error verificando columna ${columnName} en ${table}:`, err.message);
    return false;
  }
}

async function dropIndexIfExists(table, indexName) {
  try {
    const [rows] = await pool.query(`
      SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = ?
      AND INDEX_NAME = ?
      LIMIT 1
    `, [table, indexName]);

    if (rows.length === 0) {
      return false;
    }

    await pool.query(`ALTER TABLE ${table} DROP INDEX ${indexName}`);
    console.log(`✓ Indice "${indexName}" eliminado de ${table}`);
    return true;
  } catch (err) {
    console.log(`Nota: Error eliminando indice ${indexName} en ${table}:`, err.message);
    return false;
  }
}

// Agregar columna cancelado
async function addCanceladoColumn() {
  const tables = [
    'control_material_almacen_smd',
    'control_material_salida',
    'control_material_salida_smd'
  ];

  for (const table of tables) {
    await addColumnIfNotExists(table, 'cancelado', 'TINYINT DEFAULT 0');
  }
  console.log('✓ Columna "cancelado" verificada/agregada');
}

// Agregar columna tiene_salida
async function addTieneSalidaColumn() {
  try {
    await pool.query(`
      ALTER TABLE control_material_almacen_smd 
      ADD COLUMN IF NOT EXISTS tiene_salida TINYINT DEFAULT 0
    `);
    console.log('✓ Columna "tiene_salida" verificada/agregada');
  } catch (err) {
    if (!err.message.includes('Duplicate column')) {
      console.log('Nota: La columna tiene_salida puede ya existir');
    }
  }
}

// Agregar columnas IQC a control_material_almacen_smd
async function addIqcColumns() {
  const columns = [
    { name: 'receiving_lot_code', definition: 'VARCHAR(25) NULL' },
    { name: 'label_seq', definition: 'INT NULL' },
    { name: 'iqc_required', definition: 'TINYINT DEFAULT 0' },
    { name: 'iqc_status', definition: "VARCHAR(20) DEFAULT 'NotRequired'" },
    { name: 'inspection_lot_sequence', definition: 'INT DEFAULT 1' }
  ];

  for (const col of columns) {
    await addColumnIfNotExists('control_material_almacen_smd', col.name, col.definition);
  }
  console.log('✓ Columnas IQC verificadas/agregadas');
}

// Agregar columnas de configuración IQC a materiales
async function addMaterialesIqcConfigColumns() {
  const columns = [
    { name: 'iqc_required', definition: 'TINYINT DEFAULT 0' },
    { name: 'rohs_enabled', definition: 'TINYINT DEFAULT 0' },
    { name: 'brightness_enabled', definition: 'TINYINT DEFAULT 0' },
    { name: 'brightness_sampling_level', definition: "VARCHAR(10) DEFAULT 'S-1'" },
    { name: 'brightness_aql_level', definition: "VARCHAR(10) DEFAULT '2.5'" },
    { name: 'brightness_target', definition: 'DECIMAL(10,4) NULL' },
    { name: 'brightness_lsl', definition: 'DECIMAL(10,4) NULL' },
    { name: 'brightness_usl', definition: 'DECIMAL(10,4) NULL' },
    { name: 'dimension_enabled', definition: 'TINYINT DEFAULT 0' },
    { name: 'dimension_sampling_level', definition: "VARCHAR(10) DEFAULT 'S-1'" },
    { name: 'dimension_aql_level', definition: "VARCHAR(10) DEFAULT '2.5'" },
    { name: 'dimension_length', definition: 'DECIMAL(10,3) NULL' },
    { name: 'dimension_length_tol', definition: 'DECIMAL(10,3) NULL' },
    { name: 'dimension_width', definition: 'DECIMAL(10,3) NULL' },
    { name: 'dimension_width_tol', definition: 'DECIMAL(10,3) NULL' },
    { name: 'dimension_height', definition: 'DECIMAL(10,3) NULL' },
    { name: 'dimension_height_tol', definition: 'DECIMAL(10,3) NULL' },
    { name: 'color_enabled', definition: 'TINYINT DEFAULT 0' },
    { name: 'color_sampling_level', definition: "VARCHAR(10) DEFAULT 'S-1'" },
    { name: 'color_aql_level', definition: "VARCHAR(10) DEFAULT '2.5'" },
    { name: 'color_spec', definition: 'VARCHAR(255) NULL' },
    { name: 'appearance_enabled', definition: 'TINYINT DEFAULT 0' },
    { name: 'appearance_sampling_level', definition: "VARCHAR(10) DEFAULT 'S-1'" },
    { name: 'appearance_aql_level', definition: "VARCHAR(10) DEFAULT '2.5'" },
    { name: 'appearance_spec', definition: 'TEXT NULL' },
    { name: 'sampling_level', definition: "VARCHAR(10) DEFAULT 'S-1'" },
    { name: 'aql_level', definition: "VARCHAR(10) DEFAULT '2.5'" },
    { name: 'dimension_spec', definition: 'VARCHAR(500) NULL' },
    { name: 'version', definition: 'VARCHAR(50) NULL' },
    { name: 'assign_internal_lot', definition: 'TINYINT DEFAULT 0' }
  ];

  for (const col of columns) {
    await addColumnIfNotExists('materiales', col.name, col.definition);
  }
  console.log('✓ Columnas IQC Config en materiales verificadas');
}

// Crear tablas IQC
async function createIqcTables() {
  try {
    // Tabla iqc_inspection_lot_smd
    await pool.query(`
      CREATE TABLE IF NOT EXISTS iqc_inspection_lot_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        receiving_lot_code VARCHAR(50) NOT NULL,
        sample_label_code VARCHAR(50) NULL,
        sample_label_id INT NULL,
        material_code TEXT NULL,
        part_number VARCHAR(150) NULL,
        customer VARCHAR(150) NULL,
        supplier VARCHAR(150) NULL,
        arrival_date DATE NULL,
        total_qty_received INT DEFAULT 0,
        total_labels INT DEFAULT 0,
        aql_level VARCHAR(20) NULL,
        sample_qty INT NULL,
        qty_sample_ok INT DEFAULT 0,
        qty_sample_ng INT DEFAULT 0,
        rohs_result VARCHAR(20) DEFAULT 'Pending',
        brightness_result VARCHAR(20) DEFAULT 'Pending',
        dimension_result VARCHAR(20) DEFAULT 'Pending',
        color_result VARCHAR(20) DEFAULT 'Pending',
        appearance_result VARCHAR(20) DEFAULT 'Pending',
        disposition ENUM('Pending','Release','Return','Scrap','Hold','Rework') DEFAULT 'Pending',
        status ENUM('Pending','InProgress','Closed') DEFAULT 'Pending',
        inspector VARCHAR(100) NULL,
        inspector_id INT NULL,
        remarks TEXT NULL,
        lot_sequence INT DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        closed_at DATETIME NULL
      )
    `);

    // Corregir tamaños de columnas
    try {
      await pool.query(`ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN material_code TEXT NULL`);
      await pool.query(`ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN part_number VARCHAR(150) NULL`);
      await pool.query(`ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN receiving_lot_code VARCHAR(50) NOT NULL`);
    } catch (e) { }

    // Agregar columnas adicionales si no existen
    const iqcLotColumns = [
      { name: 'inspector', definition: 'VARCHAR(100) NULL' },
      { name: 'inspector_id', definition: 'INT NULL' },
      { name: 'remarks', definition: 'TEXT NULL' },
      { name: 'appearance_result', definition: "VARCHAR(20) DEFAULT 'Pending'" },
      { name: 'lot_sequence', definition: 'INT DEFAULT 1' }
    ];
    for (const col of iqcLotColumns) {
      await addColumnIfNotExists('iqc_inspection_lot_smd', col.name, col.definition);
    }

    // Modificar ENUMs
    const resultColumns = ['rohs_result', 'brightness_result', 'dimension_result', 'color_result', 'appearance_result'];
    for (const col of resultColumns) {
      try {
        await pool.query(`ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN ${col} VARCHAR(20) DEFAULT 'Pending'`);
      } catch (e) { }
    }

    // Manejar índices
    try {
      await pool.query(`ALTER TABLE iqc_inspection_lot_smd DROP INDEX receiving_lot_code`);
    } catch (e) { }

    try {
      await pool.query(`
        CREATE UNIQUE INDEX idx_receiving_lot_sequence 
        ON iqc_inspection_lot_smd(receiving_lot_code, lot_sequence)
      `);
    } catch (e) { }

    // Tabla iqc_inspection_detail_smd
    await pool.query(`
      CREATE TABLE IF NOT EXISTS iqc_inspection_detail_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        inspection_lot_id INT NOT NULL,
        sample_number INT NOT NULL,
        characteristic VARCHAR(20) NOT NULL,
        test_name VARCHAR(100) NOT NULL,
        measured_value VARCHAR(50) NULL,
        unit VARCHAR(20) NULL,
        min_spec VARCHAR(50) NULL,
        max_spec VARCHAR(50) NULL,
        result ENUM('OK','NG') NOT NULL,
        remarks TEXT NULL,
        measured_by VARCHAR(100) NULL,
        measured_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    console.log('✓ Tablas IQC verificadas/creadas');
  } catch (err) {
    console.log('Nota: Las tablas IQC pueden ya existir:', err.message);
  }
}

// Agregar columna usuario_registro
async function addUsuarioRegistroColumns() {
  const tables = [
    { table: 'control_material_almacen_smd', name: 'usuario_registro', definition: 'VARCHAR(150) NULL' },
    { table: 'control_material_salida_smd', name: 'usuario_registro', definition: 'VARCHAR(150) NULL' },
    { table: 'control_material_salida', name: 'usuario_registro', definition: 'VARCHAR(150) NULL' },
    { table: 'control_material_entrada_smd', name: 'usuario_registro', definition: 'VARCHAR(150) NULL' }
  ];

  for (const col of tables) {
    await addColumnIfNotExists(col.table, col.name, col.definition);
  }
  console.log('✓ Columnas usuario_registro verificadas');
}

// Agregar columnas extra de warehousing si no existen
async function addWarehousingExtraColumns() {
  const columns = [
    { name: 'vendedor', definition: 'VARCHAR(100) NULL' },
    { name: 'unidad_medida', definition: 'VARCHAR(10) NULL' }
  ];

  for (const col of columns) {
    await addColumnIfNotExists('control_material_almacen_smd', col.name, col.definition);
  }
  console.log('? Columnas vendedor/unidad_medida verificadas');
}
// Crear/ajustar tabla de entradas SMD (pendientes por confirmar)
async function createControlMaterialEntradaSmdTable() {
  try {
    await pool.query(`
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
      )
    `);

    await addColumnIfNotExists('control_material_entrada_smd', 'confirmado', 'TINYINT DEFAULT 0');
    await addColumnIfNotExists('control_material_entrada_smd', 'confirmado_por', 'VARCHAR(150) NULL');
    await addColumnIfNotExists('control_material_entrada_smd', 'confirmado_at', 'DATETIME NULL');
    await addColumnIfNotExists('control_material_entrada_smd', 'rechazado', 'TINYINT DEFAULT 0');
    await addColumnIfNotExists('control_material_entrada_smd', 'rechazado_por', 'VARCHAR(150) NULL');
    await addColumnIfNotExists('control_material_entrada_smd', 'rechazado_at', 'DATETIME NULL');
    await addColumnIfNotExists('control_material_entrada_smd', 'rechazado_motivo', 'TEXT NULL');

    console.log('? Tabla control_material_entrada_smd verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla control_material_entrada_smd puede ya existir:', err.message);
  }
}


// Crear/ajustar tabla de salidas de almacén compartida (entradas SMD)
async function createControlMaterialSalidaTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS control_material_salida (
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
      )
    `);

    // Asegurar columnas de confirmación en tablas existentes
    await addColumnIfNotExists('control_material_salida', 'confirmado', 'TINYINT DEFAULT 0');
    await addColumnIfNotExists('control_material_salida', 'confirmado_por', 'VARCHAR(150) NULL');
    await addColumnIfNotExists('control_material_salida', 'confirmado_at', 'DATETIME NULL');
    await addColumnIfNotExists('control_material_salida', 'rechazado', 'TINYINT DEFAULT 0');
    await addColumnIfNotExists('control_material_salida', 'rechazado_por', 'VARCHAR(150) NULL');
    await addColumnIfNotExists('control_material_salida', 'rechazado_at', 'DATETIME NULL');
    await addColumnIfNotExists('control_material_salida', 'rechazado_motivo', 'TEXT NULL');

    console.log('✓ Tabla control_material_salida verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla control_material_salida puede ya existir:', err.message);
  }
}

// Crear tablas de cuarentena
async function createQuarantineTables() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS quarantine_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        warehousing_id INT NOT NULL,
        codigo_material_recibido VARCHAR(50) NOT NULL,
        numero_parte VARCHAR(150) NULL,
        numero_lote VARCHAR(100) NULL,
        cantidad INT DEFAULT 0,
        reason TEXT NULL,
        status ENUM('Pending','Released','Scrapped','Returned') DEFAULT 'Pending',
        disposition ENUM('Pending','Release','Scrap','Return') DEFAULT 'Pending',
        created_by VARCHAR(100) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        closed_at DATETIME NULL,
        closed_by VARCHAR(100) NULL
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS quarantine_history_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        quarantine_id INT NOT NULL,
        action VARCHAR(50) NOT NULL,
        comment TEXT NULL,
        created_by VARCHAR(100) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    console.log('✓ Tablas de cuarentena verificadas/creadas');
  } catch (err) {
    console.log('Nota: Las tablas de cuarentena pueden ya existir');
  }
}

// Crear tabla de solicitudes de cancelación
async function createCancellationRequestsTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS cancellation_requests (
        id INT AUTO_INCREMENT PRIMARY KEY,
        warehousing_id INT NOT NULL,
        warehousing_code VARCHAR(50) NULL,
        status ENUM('Pending','Approved','Rejected') DEFAULT 'Pending',
        requested_by VARCHAR(100) NOT NULL,
        requested_by_id INT NULL,
        requested_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        reason TEXT NOT NULL,
        reviewed_by VARCHAR(100) NULL,
        reviewed_by_id INT NULL,
        reviewed_at DATETIME NULL,
        review_notes TEXT NULL,
        INDEX idx_warehousing_id (warehousing_id),
        INDEX idx_status (status),
        INDEX idx_requested_at (requested_at)
      )
    `);

    console.log('✓ Tabla cancellation_requests verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla cancellation_requests puede ya existir');
  }
}

// ============================================
// TABLAS DE AUDITORÍA DE INVENTARIO
// ============================================
async function createAuditTables() {
  try {
    // Tabla principal de auditorías
    await pool.query(`
      CREATE TABLE IF NOT EXISTS inventory_audit_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        audit_code VARCHAR(30) NOT NULL UNIQUE,
        status ENUM('Pending', 'InProgress', 'Completed', 'Cancelled') DEFAULT 'Pending',
        
        -- Estadísticas
        total_locations INT DEFAULT 0,
        total_items INT DEFAULT 0,
        verified_locations INT DEFAULT 0,
        discrepancy_locations INT DEFAULT 0,
        found_items INT DEFAULT 0,
        missing_items INT DEFAULT 0,
        
        -- Usuarios y fechas
        usuario_inicio VARCHAR(100) NULL,
        usuario_fin VARCHAR(100) NULL,
        fecha_inicio DATETIME NULL,
        fecha_fin DATETIME NULL,
        notas TEXT NULL,
        
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        
        INDEX idx_status (status),
        INDEX idx_fecha_inicio (fecha_inicio)
      )
    `);

    // Tabla de ubicaciones por auditoría
    await pool.query(`
      CREATE TABLE IF NOT EXISTS inventory_audit_location_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        audit_id INT NOT NULL,
        location VARCHAR(100) NOT NULL,
        status ENUM('Pending', 'InProgress', 'Verified', 'Discrepancy') DEFAULT 'Pending',
        
        total_items INT DEFAULT 0,
        total_qty INT DEFAULT 0,
        
        started_at DATETIME NULL,
        started_by VARCHAR(100) NULL,
        completed_at DATETIME NULL,
        completed_by VARCHAR(100) NULL,
        
        FOREIGN KEY (audit_id) REFERENCES inventory_audit_smd(id) ON DELETE CASCADE,
        INDEX idx_audit_id (audit_id),
        INDEX idx_location (location),
        INDEX idx_status (status),
        UNIQUE KEY uk_audit_location (audit_id, location)
      )
    `);

    // Tabla de items escaneados
    await pool.query(`
      CREATE TABLE IF NOT EXISTS inventory_audit_item_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        audit_id INT NOT NULL,
        warehousing_id INT NOT NULL,
        warehousing_code VARCHAR(50) NOT NULL,
        location VARCHAR(100) NOT NULL,
        
        status ENUM('Pending', 'Found', 'Missing', 'ProcessedOut') DEFAULT 'Pending',
        
        scanned_at DATETIME NULL,
        scanned_by VARCHAR(100) NULL,
        processed_at DATETIME NULL,
        processed_by VARCHAR(100) NULL,
        notas TEXT NULL,
        
        FOREIGN KEY (audit_id) REFERENCES inventory_audit_smd(id) ON DELETE CASCADE,
        INDEX idx_audit_id (audit_id),
        INDEX idx_warehousing_id (warehousing_id),
        INDEX idx_location (location),
        INDEX idx_status (status),
        UNIQUE KEY uk_audit_item (audit_id, warehousing_id)
      )
    `);

    console.log('✓ Tablas de auditoría de inventario verificadas/creadas');
  } catch (err) {
    console.log('Nota: Las tablas de auditoría pueden ya existir:', err.message);
  }
}

// ============================================
// TABLA AUDIT PART - Resumen por número de parte para auditoría v2
// ============================================
async function createAuditPartTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS inventory_audit_part_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        audit_id INT NOT NULL,
        location VARCHAR(100) NOT NULL,
        numero_parte VARCHAR(150) NOT NULL,
        
        -- Valores esperados
        expected_items INT DEFAULT 0,
        expected_qty DECIMAL(15,4) DEFAULT 0,
        
        -- Status del flujo v2
        status ENUM('Pending', 'Ok', 'Mismatch', 'VerifiedByScan', 'MissingConfirmed') DEFAULT 'Pending',
        
        -- Valores escaneados (solo si Mismatch)
        scanned_items INT DEFAULT 0,
        scanned_qty DECIMAL(15,4) DEFAULT 0,
        
        -- Confirmación
        confirmed_by VARCHAR(100) NULL,
        confirmed_at DATETIME NULL,
        flagged_by VARCHAR(100) NULL,
        flagged_at DATETIME NULL,
        
        FOREIGN KEY (audit_id) REFERENCES inventory_audit_smd(id) ON DELETE CASCADE,
        UNIQUE KEY uk_audit_location_part (audit_id, location, numero_parte),
        INDEX idx_audit_id (audit_id),
        INDEX idx_location (location),
        INDEX idx_numero_parte (numero_parte),
        INDEX idx_status (status)
      )
    `);

    console.log('✓ Tabla inventory_audit_part_smd verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla inventory_audit_part_smd puede ya existir:', err.message);
  }
}

// ============================================
// TABLA PCB INVENTORY SCAN SMD
// ============================================
async function createPcbInventoryScanTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pcb_inventory_scan_smd (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        inventory_date DATE NOT NULL,
        scanned_original VARCHAR(180) NOT NULL,
        scanned_original_norm VARCHAR(180) NOT NULL,
        assy_type VARCHAR(20) NULL,
        pcb_part_no VARCHAR(11) NOT NULL,
        modelo VARCHAR(120) NOT NULL DEFAULT 'N/A',
        proceso ENUM('SMD','IMD','ASSY') NOT NULL DEFAULT 'SMD',
        area ENUM('INVENTARIO','REPARACION') NOT NULL DEFAULT 'INVENTARIO',
        tipo_movimiento ENUM('ENTRADA','SALIDA','SCRAP') NOT NULL DEFAULT 'ENTRADA',
        qty INT NOT NULL DEFAULT 1,
        array_count INT NOT NULL DEFAULT 1,
        array_group_code VARCHAR(180) NULL,
        array_role VARCHAR(20) NOT NULL DEFAULT 'SINGLE',
        comentarios TEXT NULL,
        scanned_by VARCHAR(100) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uk_daily_original_tipo_area (inventory_date, scanned_original_norm, tipo_movimiento, area),
        INDEX idx_daily_part (inventory_date, pcb_part_no),
        INDEX idx_daily_process (inventory_date, proceso),
        INDEX idx_daily_tipo (inventory_date, tipo_movimiento),
        INDEX idx_pcb_array_group (array_group_code),
        INDEX idx_pcb_area (area)
      )
    `);

    console.log('✓ Tabla pcb_inventory_scan_smd verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla pcb_inventory_scan_smd puede ya existir:', err.message);
  }
}

// Migrar esquema PCB legado:
// - agrega area
// - convierte proceso de SMT/REPARADO/REPARACION a SMD/IMD/ASSY
// - actualiza indices para permitir el mismo codigo por area
async function migratePcbInventorySchema() {
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'area',
    "ENUM('INVENTARIO','REPARACION') NOT NULL DEFAULT 'INVENTARIO' AFTER proceso"
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'qty',
    'INT NOT NULL DEFAULT 1 AFTER tipo_movimiento'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'array_count',
    'INT NOT NULL DEFAULT 1 AFTER qty'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'array_group_code',
    'VARCHAR(180) NULL AFTER array_count'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'array_role',
    "VARCHAR(20) NOT NULL DEFAULT 'SINGLE' AFTER array_group_code"
  );

  try {
    const [procesoCols] = await pool.query(`
      SELECT COLUMN_TYPE
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'pcb_inventory_scan_smd'
      AND COLUMN_NAME = 'proceso'
      LIMIT 1
    `);
    const procesoType = (procesoCols[0]?.COLUMN_TYPE || '').toLowerCase();
    const procesoNeedsMigration = procesoType !== "enum('smd','imd','assy')";

    if (procesoNeedsMigration) {
      await pool.query(`
        ALTER TABLE pcb_inventory_scan_smd
        MODIFY COLUMN proceso VARCHAR(20) NOT NULL DEFAULT 'SMD'
      `);

      await pool.query(`
        UPDATE pcb_inventory_scan_smd
        SET area = 'REPARACION'
        WHERE proceso IN ('REPARADO', 'REPARACION')
      `);

      await pool.query(`
        UPDATE pcb_inventory_scan_smd
        SET area = 'INVENTARIO'
        WHERE proceso = 'SMT'
      `);

      await pool.query(`
        UPDATE pcb_inventory_scan_smd
        SET proceso = CASE
          WHEN proceso IN ('SMD', 'IMD', 'ASSY') THEN proceso
          WHEN proceso IN ('SMT', 'REPARADO', 'REPARACION', '') THEN 'SMD'
          ELSE 'SMD'
        END
      `);

      await pool.query(`
        ALTER TABLE pcb_inventory_scan_smd
        MODIFY COLUMN proceso ENUM('SMD','IMD','ASSY') NOT NULL DEFAULT 'SMD'
      `);
    }

    console.log('✓ Esquema PCB proceso/area verificado/migrado');
  } catch (err) {
    console.log('Nota: Error migrando proceso/area PCB:', err.message);
  }

  try {
    await pool.query(`
      CREATE INDEX idx_pcb_area
      ON pcb_inventory_scan_smd (area)
    `);
    console.log('✓ Creado indice idx_pcb_area');
  } catch (e) {
    // Puede que ya exista - eso esta bien
  }

  try {
    await pool.query(`
      CREATE INDEX idx_pcb_array_group
      ON pcb_inventory_scan_smd (array_group_code)
    `);
    console.log('✓ Creado indice idx_pcb_array_group');
  } catch (e) {
    // Puede que ya exista - eso esta bien
  }
}

// Agregar columna tipo_movimiento a pcb_inventory_scan_smd si no existe
async function addPcbInventoryTipoMovimiento() {
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'tipo_movimiento',
    "ENUM('ENTRADA','SALIDA','SCRAP') NOT NULL DEFAULT 'ENTRADA' AFTER proceso"
  );

  // Crear/verificar el indice nuevo antes de quitar los indices antiguos.
  let hasAreaUniqueIndex = false;
  try {
    await pool.query(`
      CREATE UNIQUE INDEX uk_daily_original_tipo_area
      ON pcb_inventory_scan_smd (inventory_date, scanned_original_norm, tipo_movimiento, area)
    `);
    console.log('✓ Creado indice uk_daily_original_tipo_area');
    hasAreaUniqueIndex = true;
  } catch (e) {
    // Puede que ya exista - eso esta bien
    try {
      const [rows] = await pool.query(`
        SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'pcb_inventory_scan_smd'
        AND INDEX_NAME = 'uk_daily_original_tipo_area'
        LIMIT 1
      `);
      hasAreaUniqueIndex = rows.length > 0;
    } catch (_) {
      hasAreaUniqueIndex = false;
    }
  }

  if (hasAreaUniqueIndex) {
    await dropIndexIfExists('pcb_inventory_scan_smd', 'uk_daily_original');
    await dropIndexIfExists('pcb_inventory_scan_smd', 'uk_daily_original_tipo');
  }

  try {
    await pool.query(`
      CREATE INDEX idx_daily_tipo 
      ON pcb_inventory_scan_smd (inventory_date, tipo_movimiento)
    `);
    console.log('✓ Creado indice idx_daily_tipo');
  } catch (e) {
    // Puede que ya exista
  }
}

// Ejecutar todas las migraciones
async function runMigrations() {
  console.log('🔄 Ejecutando migraciones de base de datos...');

  await addCanceladoColumn();
  await addTieneSalidaColumn();
  await addUsuarioRegistroColumns();
  await createControlMaterialEntradaSmdTable();
  await addWarehousingExtraColumns();
  await createControlMaterialSalidaTable();
  await createQuarantineTables();
  await createCancellationRequestsTable();
  await addIqcColumns();
  await createIqcTables();
  await addMaterialesIqcConfigColumns();
  await createAuditTables();
  await createAuditPartTable();
  await createLotDivisionTable();
  await createRequirementsTables();
  await addReentryColumns();
  await createPcbInventoryScanTable();
  await migratePcbInventorySchema();
  await addPcbInventoryTipoMovimiento();

  console.log('✅ Migraciones completadas');
}

// Agregar columnas de reingreso para historial
async function addReentryColumns() {
  const columns = [
    { name: 'ubicacion_anterior', definition: 'VARCHAR(100) NULL' },
    { name: 'fecha_reingreso', definition: 'DATETIME NULL' },
    { name: 'usuario_reingreso', definition: 'VARCHAR(100) NULL' }
  ];

  for (const col of columns) {
    await addColumnIfNotExists('control_material_almacen_smd', col.name, col.definition);
  }

  // Crear índice para búsquedas por fecha de reingreso
  try {
    await pool.query(`CREATE INDEX idx_fecha_reingreso ON control_material_almacen_smd(fecha_reingreso)`);
  } catch (err) {
    // El índice ya puede existir
  }

  console.log('✓ Columnas de reingreso verificadas/agregadas');
}

// Crear tablas de requerimientos de material
async function createRequirementsTables() {
  try {
    // Tabla principal de requerimientos
    await pool.query(`
      CREATE TABLE IF NOT EXISTS material_requirements (
        id INT AUTO_INCREMENT PRIMARY KEY,
        
        -- Código único del requerimiento (REQ-YYYYMMDD-###)
        codigo_requerimiento VARCHAR(20) NULL UNIQUE,
        
        -- Información del requerimiento
        area_destino VARCHAR(50) NOT NULL,
        modelo VARCHAR(100) NULL,
        fecha_requerida DATE NOT NULL,
        turno VARCHAR(20) NULL,
        
        -- Estado y prioridad
        status ENUM('Pendiente', 'En Preparación', 'Listo', 'Entregado', 'Cancelado') DEFAULT 'Pendiente',
        prioridad ENUM('Normal', 'Urgente', 'Crítico') DEFAULT 'Normal',
        
        -- Notas
        notas TEXT NULL,
        
        -- Auditoría
        creado_por VARCHAR(100) NOT NULL,
        fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
        actualizado_por VARCHAR(100) NULL,
        fecha_actualizacion DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
        
        INDEX idx_fecha_requerida (fecha_requerida),
        INDEX idx_status (status),
        INDEX idx_area (area_destino),
        INDEX idx_prioridad (prioridad),
        INDEX idx_codigo (codigo_requerimiento)
      )
    `);

    // Tabla de items por requerimiento
    await pool.query(`
      CREATE TABLE IF NOT EXISTS material_requirement_items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        requirement_id INT NOT NULL,
        
        -- Material
        numero_parte VARCHAR(50) NOT NULL,
        descripcion VARCHAR(200) NULL,
        
        -- Cantidades
        cantidad_requerida INT NOT NULL,
        cantidad_preparada INT DEFAULT 0,
        cantidad_entregada INT DEFAULT 0,
        
        -- Estado del item
        status ENUM('Pendiente', 'Parcial', 'Preparado', 'Entregado') DEFAULT 'Pendiente',
        
        -- Trazabilidad
        codigos_salida TEXT NULL,
        
        -- Notas
        notas TEXT NULL,
        
        FOREIGN KEY (requirement_id) REFERENCES material_requirements(id) ON DELETE CASCADE,
        INDEX idx_requirement (requirement_id),
        INDEX idx_numero_parte (numero_parte),
        INDEX idx_status (status)
      )
    `);

    // Agregar columna codigo_requerimiento si no existe (para tablas existentes)
    try {
      await pool.query(`
        ALTER TABLE material_requirements 
        ADD COLUMN codigo_requerimiento VARCHAR(20) NULL UNIQUE AFTER id
      `);
      console.log('✓ Columna codigo_requerimiento agregada');
    } catch (e) {
      // La columna ya puede existir
    }

    console.log('✓ Tablas de requerimientos de material verificadas/creadas');
  } catch (err) {
    console.log('Nota: Las tablas de requerimientos pueden ya existir:', err.message);
  }
}

// Crear tabla para historial de divisiones de lote
async function createLotDivisionTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS lot_division (
        id INT AUTO_INCREMENT PRIMARY KEY,
        original_code VARCHAR(50) NOT NULL,
        original_qty_before INT NOT NULL,
        original_qty_after INT NOT NULL,
        new_code VARCHAR(50) NOT NULL,
        new_qty INT NOT NULL,
        standard_pack INT NOT NULL,
        outgoing_id INT NULL,
        divided_by VARCHAR(100),
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_original_code (original_code),
        INDEX idx_new_code (new_code),
        INDEX idx_created_at (created_at)
      )
    `);

    console.log('✓ Tabla lot_division verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla lot_division puede ya existir:', err.message);
  }
}

module.exports = {
  runMigrations,
  migratePcbInventorySchema,
  addPcbInventoryTipoMovimiento,
  addColumnIfNotExists
};


