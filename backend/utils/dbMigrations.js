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

async function ensureWarehouseCodeIndex() {
  const indexName = 'idx_cma_smd_codigo_material';
  const [rows] = await pool.query(`
    SELECT INDEX_NAME
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'control_material_almacen_smd'
      AND INDEX_NAME = ?
    LIMIT 1
  `, [indexName]);

  if (rows.length === 0) {
    await pool.query(`
      CREATE INDEX idx_cma_smd_codigo_material
      ON control_material_almacen_smd (codigo_material_recibido(191))
    `);
    console.log('✓ Índice de código de material SMD creado');
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
        linea_proceso TEXT NULL,
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
    await addColumnIfNotExists('control_material_salida', 'linea_proceso', 'TEXT NULL AFTER modelo');

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

    // Catálogo persistente de ubicaciones físicas. Conserva también los
    // espacios vacíos escaneados para incluirlos en auditorías posteriores.
    await pool.query(`
      CREATE TABLE IF NOT EXISTS inventory_location_catalog_smd (
        id INT AUTO_INCREMENT PRIMARY KEY,
        location VARCHAR(100) NOT NULL,
        active TINYINT NOT NULL DEFAULT 1,
        source VARCHAR(30) NOT NULL DEFAULT 'AuditScan',
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uk_inventory_location_catalog_smd (location),
        INDEX idx_inventory_location_catalog_active (active)
      )
    `);

    // Conservar sólo ubicaciones que realmente fueron abiertas por un
    // operador. Las filas Pending precargadas no demuestran que el QR físico
    // exista y podrían inflar la siguiente auditoría.
    await pool.query(`
      DELETE catalog
      FROM inventory_location_catalog_smd catalog
      WHERE catalog.source IN ('AuditHistory', 'Inventory')
        AND NOT EXISTS (
          SELECT 1
          FROM inventory_audit_location_smd audited
          WHERE audited.location = catalog.location
            AND (audited.started_at IS NOT NULL OR audited.status <> 'Pending')
        )
    `);

    await pool.query(`
      INSERT INTO inventory_location_catalog_smd (
        location, active, source, created_at, last_seen_at
      )
      SELECT DISTINCT TRIM(location), 1, 'AuditHistory', NOW(), NOW()
      FROM inventory_audit_location_smd
      WHERE NULLIF(TRIM(location), '') IS NOT NULL
        AND (started_at IS NOT NULL OR status <> 'Pending')
      ON DUPLICATE KEY UPDATE
        active = 1,
        last_seen_at = GREATEST(last_seen_at, VALUES(last_seen_at))
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

// Congelar los datos del lote tal como estaban al iniciar la auditoria.
// Las columnas tambien permiten que auditorias anteriores sigan mostrando
// el material aunque una salida posterior deje stock_actual en cero.
async function addAuditSnapshotColumns() {
  const columns = [
    { name: 'numero_parte_snapshot', definition: 'VARCHAR(150) NULL AFTER location' },
    { name: 'numero_lote_material_snapshot', definition: 'VARCHAR(150) NULL AFTER numero_parte_snapshot' },
    { name: 'cantidad_snapshot', definition: 'DECIMAL(15,4) NULL AFTER numero_lote_material_snapshot' },
    { name: 'especificacion_snapshot', definition: 'TEXT NULL AFTER cantidad_snapshot' },
    { name: 'fecha_recibo_snapshot', definition: 'DATETIME NULL AFTER especificacion_snapshot' },
    { name: 'physical_quantity', definition: 'DECIMAL(15,4) NULL AFTER fecha_recibo_snapshot' },
    { name: 'physical_quantity_recorded_at', definition: 'DATETIME NULL AFTER physical_quantity' },
    { name: 'physical_quantity_recorded_by', definition: 'VARCHAR(100) NULL AFTER physical_quantity_recorded_at' },
    { name: 'is_new_inventory', definition: 'TINYINT NOT NULL DEFAULT 0 AFTER physical_quantity_recorded_by' }
  ];

  for (const col of columns) {
    await addColumnIfNotExists('inventory_audit_item_smd', col.name, col.definition);
  }

  // Backfill idempotente para auditorias creadas antes de esta migracion.
  await pool.query(`
    UPDATE inventory_audit_item_smd iai
    LEFT JOIN control_material_almacen_smd cma ON cma.id = iai.warehousing_id
    SET
      iai.numero_parte_snapshot = COALESCE(iai.numero_parte_snapshot, cma.numero_parte),
      iai.numero_lote_material_snapshot = COALESCE(iai.numero_lote_material_snapshot, cma.numero_lote_material),
      iai.cantidad_snapshot = COALESCE(iai.cantidad_snapshot, cma.cantidad_actual),
      iai.especificacion_snapshot = COALESCE(iai.especificacion_snapshot, cma.especificacion),
      iai.fecha_recibo_snapshot = COALESCE(iai.fecha_recibo_snapshot, cma.fecha_recibo)
    WHERE iai.numero_parte_snapshot IS NULL
       OR iai.numero_lote_material_snapshot IS NULL
       OR iai.cantidad_snapshot IS NULL
  `);

  // Auditorias activas creadas por versiones anteriores solo tenian filas
  // para etiquetas ya procesadas. Completar los lotes que siguen activos
  // permite continuar la auditoria despues de actualizar el backend.
  const [activeBackfill] = await pool.query(`
    INSERT IGNORE INTO inventory_audit_item_smd (
      audit_id,
      warehousing_id,
      warehousing_code,
      location,
      numero_parte_snapshot,
      numero_lote_material_snapshot,
      cantidad_snapshot,
      especificacion_snapshot,
      fecha_recibo_snapshot,
      status
    )
    SELECT
      ia.id,
      cma.id,
      il.codigo_material_recibido,
      COALESCE(NULLIF(TRIM(cma.ubicacion_destino), ''), NULLIF(TRIM(cma.ubicacion_salida), '')),
      il.numero_parte,
      il.numero_lote,
      il.stock_actual,
      cma.especificacion,
      cma.fecha_recibo,
      'Pending'
    FROM inventory_audit_smd ia
    JOIN inventario_lotes_smd il ON il.stock_actual > 0
    JOIN (
      SELECT c1.*
      FROM control_material_almacen_smd c1
      JOIN (
        SELECT codigo_material_recibido, MAX(id) AS max_id
        FROM control_material_almacen_smd
        GROUP BY codigo_material_recibido
      ) latest ON latest.max_id = c1.id
    ) cma ON cma.codigo_material_recibido = il.codigo_material_recibido
    WHERE ia.status = 'InProgress'
      AND COALESCE(NULLIF(TRIM(cma.ubicacion_destino), ''), NULLIF(TRIM(cma.ubicacion_salida), '')) IS NOT NULL
  `);

  console.log('✓ Snapshot de auditoria verificado/agregado');
  if (activeBackfill.affectedRows > 0) {
    console.log(`✓ ${activeBackfill.affectedRows} lote(s) agregados al snapshot de auditoria activa`);
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

// Reparar auditorias activas donde una etiqueta salio por discrepancia y fue
// devuelta despues. El inventario recupera stock por el trigger de retornos;
// la auditoria debe reabrir la parte para no quedar desfasada.
async function reconcileActiveAuditReturns() {
  try {
    const [itemsResult] = await pool.query(`
      UPDATE inventory_audit_item_smd iai
      JOIN inventory_audit_smd ia ON ia.id = iai.audit_id
      JOIN material_return_smd mr
        ON mr.material_warehousing_code = iai.warehousing_code
       AND mr.created_at >= iai.processed_at
      SET iai.status = 'Found',
          iai.scanned_at = mr.return_datetime,
          iai.scanned_by = COALESCE(mr.returned_by, 'Sistema'),
          iai.processed_at = NULL,
          iai.processed_by = NULL,
          iai.notas = CONCAT_WS(' | ', NULLIF(iai.notas, ''), 'Retorno durante auditoria activa')
      WHERE ia.status = 'InProgress'
        AND iai.status = 'ProcessedOut'
    `);

    await pool.query(`
      UPDATE inventory_audit_part_smd iap
      JOIN inventory_audit_smd ia ON ia.id = iap.audit_id
      JOIN inventory_audit_item_smd iai
        ON iai.audit_id = iap.audit_id
       AND iai.location = iap.location
       AND iai.numero_parte_snapshot = iap.numero_parte
      SET iap.status = 'Mismatch',
          iap.flagged_by = COALESCE(iai.scanned_by, 'Sistema'),
          iap.flagged_at = COALESCE(iai.scanned_at, NOW())
      WHERE ia.status = 'InProgress'
        AND iap.status = 'MissingConfirmed'
        AND iai.status = 'Found'
        AND iai.notas LIKE '%Retorno durante auditoria activa%'
    `);

    await pool.query(`
      UPDATE inventory_audit_location_smd ial
      JOIN inventory_audit_smd ia ON ia.id = ial.audit_id
      JOIN inventory_audit_part_smd iap
        ON iap.audit_id = ial.audit_id AND iap.location = ial.location
      SET ial.status = 'InProgress',
          ial.completed_at = NULL,
          ial.completed_by = NULL
      WHERE ia.status = 'InProgress'
        AND ial.status = 'Discrepancy'
        AND iap.status = 'Mismatch'
    `);

    if (itemsResult.affectedRows > 0) {
      console.log(`✓ ${itemsResult.affectedRows} retorno(s) reconciliados con auditoria activa`);
    }
  } catch (err) {
    console.log('Nota: Error reconciliando retornos de auditoria:', err.message);
  }
}

// Reparar auditorias activas donde una parte quedo en Mismatch aunque todas
// sus etiquetas ya estan Found o ProcessedOut: la ubicacion nunca se cerraba
// (no se ponia en verde) porque checkLocationCompletion exige partes cerradas.
async function reconcileStuckAuditParts() {
  try {
    const [partsResult] = await pool.query(`
      UPDATE inventory_audit_part_smd iap
      JOIN inventory_audit_smd ia ON ia.id = iap.audit_id
      SET iap.status = IF(
            (SELECT COUNT(*) FROM inventory_audit_item_smd iai
             WHERE iai.audit_id = iap.audit_id AND iai.location = iap.location
               AND iai.numero_parte_snapshot = iap.numero_parte
               AND iai.status = 'ProcessedOut') > 0,
            'MissingConfirmed', 'VerifiedByScan'
          ),
          iap.confirmed_at = COALESCE(iap.confirmed_at, NOW())
      WHERE ia.status = 'InProgress'
        AND iap.status = 'Mismatch'
        AND (SELECT COUNT(*) FROM inventory_audit_item_smd iai
             WHERE iai.audit_id = iap.audit_id AND iai.location = iap.location
               AND iai.numero_parte_snapshot = iap.numero_parte) > 0
        AND (SELECT COUNT(*) FROM inventory_audit_item_smd iai
             WHERE iai.audit_id = iap.audit_id AND iai.location = iap.location
               AND iai.numero_parte_snapshot = iap.numero_parte
               AND iai.status NOT IN ('Found', 'ProcessedOut')) = 0
    `);

    const [locResult] = await pool.query(`
      UPDATE inventory_audit_location_smd ial
      JOIN inventory_audit_smd ia ON ia.id = ial.audit_id
      SET ial.status = IF(
            (SELECT COUNT(*) FROM inventory_audit_part_smd iap
             WHERE iap.audit_id = ial.audit_id AND iap.location = ial.location
               AND iap.status = 'MissingConfirmed') > 0,
            'Discrepancy', 'Verified'
          ),
          ial.completed_at = COALESCE(ial.completed_at, NOW())
      WHERE ia.status = 'InProgress'
        AND ial.status IN ('Pending', 'InProgress')
        AND (SELECT COUNT(*) FROM inventory_audit_part_smd iap
             WHERE iap.audit_id = ial.audit_id AND iap.location = ial.location) > 0
        AND (SELECT COUNT(*) FROM inventory_audit_part_smd iap
             WHERE iap.audit_id = ial.audit_id AND iap.location = ial.location
               AND iap.status NOT IN ('Ok', 'VerifiedByScan', 'MissingConfirmed')) = 0
    `);

    if (partsResult.affectedRows > 0 || locResult.affectedRows > 0) {
      console.log(`✓ Auditoria: ${partsResult.affectedRows} parte(s) y ${locResult.affectedRows} ubicacion(es) cerradas por reconciliacion`);
    }
  } catch (err) {
    console.log('Nota: Error reconciliando partes atoradas de auditoria:', err.message);
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
        assy_type VARCHAR(64) NULL,
        pcb_part_no VARCHAR(11) NOT NULL,
        modelo VARCHAR(120) NOT NULL DEFAULT 'N/A',
        proceso ENUM('SMD','IMD','ASSY') NOT NULL DEFAULT 'SMD',
        area ENUM('INVENTARIO','INVENTARIO_REPARACION','REPARACION') NOT NULL DEFAULT 'INVENTARIO',
        tipo_movimiento ENUM('ENTRADA','SALIDA','SCRAP') NOT NULL DEFAULT 'ENTRADA',
        qty INT NOT NULL DEFAULT 1,
        array_count INT NOT NULL DEFAULT 1,
        array_group_code VARCHAR(180) NULL,
        array_role VARCHAR(20) NOT NULL DEFAULT 'SINGLE',
        defect_type VARCHAR(120) NULL,
        component_location VARCHAR(120) NULL,
        etapa_deteccion ENUM('LQC','OQC','AIS') NULL,
        defect_source_area VARCHAR(50) NULL,
        defect_data_id VARCHAR(50) NULL,
        source_entry_id BIGINT NULL,
        defect_count INT NOT NULL DEFAULT 0,
        comentarios TEXT NULL,
        scanned_by VARCHAR(100) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_pcb_history_movement (inventory_date, scanned_original_norm, tipo_movimiento, area),
        INDEX idx_daily_part (inventory_date, pcb_part_no),
        INDEX idx_daily_process (inventory_date, proceso),
        INDEX idx_daily_tipo (inventory_date, tipo_movimiento),
        INDEX idx_pcb_array_group (array_group_code),
        INDEX idx_pcb_area (area),
        INDEX idx_pcb_source_entry (source_entry_id)
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
    "ENUM('INVENTARIO','INVENTARIO_REPARACION','REPARACION') NOT NULL DEFAULT 'INVENTARIO' AFTER proceso"
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
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'defect_type',
    'VARCHAR(120) NULL AFTER array_role'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'component_location',
    'VARCHAR(120) NULL AFTER defect_type'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'etapa_deteccion',
    "ENUM('LQC','OQC','AIS') NULL AFTER component_location"
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'defect_source_area',
    'VARCHAR(50) NULL AFTER etapa_deteccion'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'defect_data_id',
    'VARCHAR(50) NULL AFTER defect_source_area'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'source_entry_id',
    'BIGINT NULL AFTER defect_data_id'
  );
  await addColumnIfNotExists(
    'pcb_inventory_scan_smd',
    'defect_count',
    'INT NOT NULL DEFAULT 0 AFTER source_entry_id'
  );

  try {
    const [areaCols] = await pool.query(`
      SELECT COLUMN_TYPE
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'pcb_inventory_scan_smd'
      AND COLUMN_NAME = 'area'
      LIMIT 1
    `);
    const areaType = (areaCols[0]?.COLUMN_TYPE || '').toLowerCase();
    const expectedAreaType =
      "enum('inventario','inventario_reparacion','reparacion')";

    if (areaType !== expectedAreaType) {
      await pool.query(`
        ALTER TABLE pcb_inventory_scan_smd
        MODIFY COLUMN area
          ENUM('INVENTARIO','INVENTARIO_REPARACION','REPARACION')
          NOT NULL DEFAULT 'INVENTARIO'
      `);
    }

    console.log('✓ Esquema PCB areas verificado/migrado');
  } catch (err) {
    console.log('Nota: Error migrando areas PCB:', err.message);
  }

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

  try {
    await pool.query(`
      CREATE INDEX idx_pcb_scanned_original_norm
      ON pcb_inventory_scan_smd (scanned_original_norm)
    `);
    console.log('✓ Creado indice idx_pcb_scanned_original_norm');
  } catch (e) {
    // Puede que ya exista - eso esta bien
  }

  try {
    await pool.query(`
      CREATE INDEX idx_pcb_source_entry
      ON pcb_inventory_scan_smd (source_entry_id)
    `);
    console.log('✓ Creado indice idx_pcb_source_entry');
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

  // El historial permite varios ciclos completos de la misma PCB el mismo dia.
  // La proteccion contra dobles entradas se hace con bloqueo + balance activo.
  await dropIndexIfExists('pcb_inventory_scan_smd', 'uk_daily_original');
  await dropIndexIfExists('pcb_inventory_scan_smd', 'uk_daily_original_tipo');
  await dropIndexIfExists('pcb_inventory_scan_smd', 'uk_daily_original_tipo_area');

  try {
    await pool.query(`
      CREATE INDEX idx_pcb_history_movement
      ON pcb_inventory_scan_smd (inventory_date, scanned_original_norm, tipo_movimiento, area)
    `);
    console.log('✓ Creado indice idx_pcb_history_movement');
  } catch (e) {
    // Puede que ya exista - eso esta bien
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

// Cada entrada de reparacion es un ciclo independiente. Sus defectos se
// relacionan con el id de esa entrada y la salida que los reparo.
async function createPcbScanDefectsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS pcb_inventory_scan_defects_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      entry_scan_id BIGINT NOT NULL,
      exit_scan_id BIGINT NULL,
      sort_order INT NOT NULL DEFAULT 1,
      defect_type VARCHAR(120) NOT NULL,
      component_location VARCHAR(120) NULL,
      etapa_deteccion ENUM('LQC','OQC','AIS') NULL,
      defect_source_area VARCHAR(50) NULL,
      defect_data_id VARCHAR(50) NULL,
      repair_status ENUM('PENDING','REPAIRED','SCRAPPED') NOT NULL DEFAULT 'PENDING',
      repaired_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_pcb_defects_entry (entry_scan_id, sort_order),
      INDEX idx_pcb_defects_exit (exit_scan_id),
      INDEX idx_pcb_defects_status (repair_status),
      CONSTRAINT fk_pcb_defects_entry_scan
        FOREIGN KEY (entry_scan_id) REFERENCES pcb_inventory_scan_smd(id)
        ON DELETE CASCADE,
      CONSTRAINT fk_pcb_defects_exit_scan
        FOREIGN KEY (exit_scan_id) REFERENCES pcb_inventory_scan_smd(id)
        ON DELETE SET NULL
    )
  `);
  console.log('✓ Tabla de defectos por ciclo PCB verificada/creada');
}

// Catalogo de defectos PCB usados durante reparacion
async function createPcbDefectCatalogTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pcb_defect_catalog (
        id INT AUTO_INCREMENT PRIMARY KEY,
        defect_name VARCHAR(120) NOT NULL,
        description TEXT NULL,
        is_active TINYINT NOT NULL DEFAULT 1,
        created_by VARCHAR(100) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uk_pcb_defect_name (defect_name),
        INDEX idx_pcb_defect_active (is_active)
      )
    `);
    console.log('✓ Tabla pcb_defect_catalog verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla pcb_defect_catalog puede ya existir:', err.message);
  }
}

// Una etiqueta física identifica un solo lote. Los índices compuestos antiguos
// permitían repetir el código cuando parte o lote cambiaban durante un retorno.
async function enforceUniqueSmdInventoryLots() {
  const connection = await pool.getConnection();
  let lockAcquired = false;

  try {
    const [[lockResult]] = await connection.query(`
      SELECT GET_LOCK('migrate_unique_inventory_lots_smd', 30) AS acquired
    `);
    lockAcquired = Number(lockResult?.acquired) === 1;
    if (!lockAcquired) {
      throw new Error('No se pudo obtener el bloqueo para consolidar lotes SMD');
    }

    await connection.query(`
      CREATE TEMPORARY TABLE tmp_inventory_smd_canonical (
        codigo_material_recibido VARCHAR(128) NOT NULL PRIMARY KEY,
        canonical_id BIGINT NOT NULL
      )
    `);

    // Conservar la fila que coincide con los datos actuales de almacén. Esos
    // registros son correcciones de identidad, no entradas que deban sumarse.
    await connection.query(`
      INSERT INTO tmp_inventory_smd_canonical (
        codigo_material_recibido,
        canonical_id
      )
      SELECT
        il.codigo_material_recibido,
        COALESCE(
          MAX(CASE WHEN cma.id IS NOT NULL THEN il.id END),
          MAX(il.id)
        ) AS canonical_id
      FROM inventario_lotes_smd il
      LEFT JOIN control_material_almacen_smd cma
        ON cma.codigo_material_recibido = il.codigo_material_recibido
       AND cma.numero_parte = il.numero_parte
       AND cma.numero_lote_material <=> il.numero_lote
      GROUP BY il.codigo_material_recibido
      HAVING COUNT(DISTINCT il.id) > 1
    `);

    const [deleteResult] = await connection.query(`
      DELETE duplicate_lot
      FROM inventario_lotes_smd duplicate_lot
      JOIN tmp_inventory_smd_canonical canonical
        ON canonical.codigo_material_recibido = duplicate_lot.codigo_material_recibido
      WHERE duplicate_lot.id <> canonical.canonical_id
    `);

    const [indexRows] = await connection.query(`
      SELECT INDEX_NAME
      FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'inventario_lotes_smd'
        AND INDEX_NAME = 'uk_inv_codigo_material_smd'
      LIMIT 1
    `);

    if (indexRows.length === 0) {
      await connection.query(`
        CREATE UNIQUE INDEX uk_inv_codigo_material_smd
        ON inventario_lotes_smd (codigo_material_recibido)
      `);
    }

    // El retorno también debe localizar el lote únicamente por la etiqueta,
    // pues parte/lote pueden haber sido corregidos desde el recibo original.
    await connection.query('DROP TRIGGER IF EXISTS trg_return_ai_smd');
    await connection.query(`
      CREATE TRIGGER trg_return_ai_smd
      AFTER INSERT ON material_return_smd
      FOR EACH ROW
      BEGIN
        UPDATE inventario_lotes_smd
        SET total_salida = GREATEST(0, total_salida - NEW.return_qty)
        WHERE codigo_material_recibido = NEW.material_warehousing_code;
      END
    `);

    console.log('✓ Índice único por código de lote SMD verificado/agregado');
    if (deleteResult.affectedRows > 0) {
      console.log(`✓ ${deleteResult.affectedRows} fila(s) duplicadas de lote consolidadas`);
    }
  } finally {
    if (lockAcquired) {
      try {
        await connection.query(`SELECT RELEASE_LOCK('migrate_unique_inventory_lots_smd')`);
      } catch (_) {
        // La conexión libera el bloqueo automáticamente al cerrarse.
      }
    }
    connection.release();
  }
}

// Mantener stock_actual >= 0 incluso si la escritura no pasa por los
// controladores HTTP (auditoría, scripts, concurrencia o cambios de entrada).
async function enforceNonNegativeSmdInventory() {
  const connection = await pool.getConnection();
  let lockAcquired = false;

  try {
    const [[lockResult]] = await connection.query(`
      SELECT GET_LOCK('migrate_nonnegative_inventory_smd', 30) AS acquired
    `);
    lockAcquired = Number(lockResult?.acquired) === 1;
    if (!lockAcquired) {
      throw new Error('No se pudo obtener el bloqueo para proteger inventario SMD');
    }

    // Los negativos heredados se llevan exactamente a cero. La historia de
    // salidas permanece en control_material_salida_smd.
    const [repairResult] = await connection.query(`
      UPDATE inventario_lotes_smd
      SET
        total_entrada = GREATEST(COALESCE(total_entrada, 0), 0),
        total_salida = LEAST(
          GREATEST(COALESCE(total_salida, 0), 0),
          GREATEST(COALESCE(total_entrada, 0), 0)
        )
      WHERE total_entrada IS NULL
         OR total_salida IS NULL
         OR total_entrada < 0
         OR total_salida < 0
         OR total_salida > total_entrada
    `);

    // Sustituir el trigger anterior, que sumaba la salida sin comprobar stock.
    await connection.query('DROP TRIGGER IF EXISTS trg_salida_ai_smd');
    await connection.query('DROP TRIGGER IF EXISTS trg_salida_bi_guard_smd');
    await connection.query('DROP TRIGGER IF EXISTS trg_inventario_lotes_bi_nonnegative_smd');
    await connection.query('DROP TRIGGER IF EXISTS trg_inventario_lotes_bu_nonnegative_smd');

    await connection.query(`
      CREATE TRIGGER trg_inventario_lotes_bi_nonnegative_smd
      BEFORE INSERT ON inventario_lotes_smd
      FOR EACH ROW
      BEGIN
        IF COALESCE(NEW.total_entrada, 0) < 0
           OR COALESCE(NEW.total_salida, 0) < 0
           OR COALESCE(NEW.total_salida, 0) > COALESCE(NEW.total_entrada, 0) THEN
          SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NEGATIVE_STOCK_NOT_ALLOWED_SMD';
        END IF;
      END
    `);

    await connection.query(`
      CREATE TRIGGER trg_inventario_lotes_bu_nonnegative_smd
      BEFORE UPDATE ON inventario_lotes_smd
      FOR EACH ROW
      BEGIN
        IF COALESCE(NEW.total_entrada, 0) < 0
           OR COALESCE(NEW.total_salida, 0) < 0
           OR COALESCE(NEW.total_salida, 0) > COALESCE(NEW.total_entrada, 0) THEN
          SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NEGATIVE_STOCK_NOT_ALLOWED_SMD';
        END IF;
      END
    `);

    // La actualización condicional es atómica: dos escaneos simultáneos no
    // pueden consumir la misma existencia. Si el INSERT falla, también se
    // revierte esta actualización porque forma parte de la misma transacción.
    await connection.query(`
      CREATE TRIGGER trg_salida_bi_guard_smd
      BEFORE INSERT ON control_material_salida_smd
      FOR EACH ROW
      BEGIN
        IF NEW.cantidad_salida IS NULL OR NEW.cantidad_salida < 0 THEN
          SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'INVALID_OUTGOING_QUANTITY_SMD';
        END IF;

        IF NEW.cantidad_salida > 0 THEN
          UPDATE inventario_lotes_smd
          SET
            total_salida = total_salida + NEW.cantidad_salida,
            ultima_salida = CASE
              WHEN NEW.fecha_salida IS NULL THEN ultima_salida
              WHEN ultima_salida IS NULL OR NEW.fecha_salida > ultima_salida
                THEN NEW.fecha_salida
              ELSE ultima_salida
            END
          WHERE codigo_material_recibido = NEW.codigo_material_recibido
            AND (total_entrada - total_salida) >= NEW.cantidad_salida;

          IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000'
              SET MESSAGE_TEXT = 'INSUFFICIENT_STOCK_SMD';
          END IF;
        END IF;
      END
    `);

    console.log('✓ Protección de inventario SMD contra negativos instalada');
    if (repairResult.affectedRows > 0) {
      console.log(`✓ ${repairResult.affectedRows} lote(s) negativos reparados a stock cero`);
    }
  } finally {
    if (lockAcquired) {
      try {
        await connection.query(`SELECT RELEASE_LOCK('migrate_nonnegative_inventory_smd')`);
      } catch (_) {
        // La conexión libera el bloqueo automáticamente al cerrarse.
      }
    }
    connection.release();
  }
}

// Algunas instalaciones antiguas tienen las tablas de cuarentena, pero no la
// bandera en almacén. Varias validaciones operativas (incluida pasta de
// soldadura) dependen de esta columna, por lo que debe existir antes de aceptar
// solicitudes.
async function ensureQuarantineWarehouseFlag() {
  const columnAdded = await addColumnIfNotExists(
    'control_material_almacen_smd',
    'en_cuarentena',
    'TINYINT NOT NULL DEFAULT 0',
  );

  const [[column]] = await pool.query(`
    SELECT COUNT(*) AS total
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'control_material_almacen_smd'
      AND COLUMN_NAME = 'en_cuarentena'
  `);
  if (Number(column?.total || 0) === 0) {
    throw new Error(
      'No fue posible crear control_material_almacen_smd.en_cuarentena',
    );
  }

  if (columnAdded) {
    // Recuperar la marca para materiales que ya estaban en una cuarentena
    // activa antes de agregar la columna.
    await pool.query(`
      UPDATE control_material_almacen_smd cma
      SET cma.en_cuarentena = EXISTS (
        SELECT 1
        FROM quarantine_smd q
        WHERE q.codigo_material_recibido = cma.codigo_material_recibido
          AND q.status IN ('InQuarantine', 'Pending')
      )
    `);
  }
  console.log('✓ Bandera en_cuarentena verificada y reconciliada');
}

// ============================================
// CICLO DE VIDA DE PASTA DE SOLDADURA
// ============================================
async function createSolderPasteLifecycleTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS solder_paste_process_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      warehousing_id BIGINT NOT NULL,
      inventory_lot_id BIGINT NULL,
      inventory_source VARCHAR(32) NOT NULL DEFAULT 'WAREHOUSE',
      codigo_material_recibido VARCHAR(180) NOT NULL,
      numero_parte VARCHAR(150) NULL,
      numero_lote VARCHAR(150) NULL,
      cycle_no INT NOT NULL DEFAULT 1,
      status VARCHAR(32) NOT NULL,
      removed_from_cold_at DATETIME NOT NULL,
      ambient_ready_at DATETIME NOT NULL,
      agitation_deadline_at DATETIME NULL,
      agitation_started_at DATETIME NULL,
      agitation_ready_at DATETIME NULL,
      agitation_completed_at DATETIME NULL,
      line_code VARCHAR(10) NULL,
      line_started_at DATETIME NULL,
      expires_at DATETIME NULL,
      issued_quantity DECIMAL(15,4) NULL,
      unit VARCHAR(30) NULL,
      inventory_outgoing_id BIGINT NULL,
      consumed_at DATETIME NULL,
      scrapped_at DATETIME NULL,
      scrap_record_id BIGINT NULL,
      cancelled_at DATETIME NULL,
      cancelled_by VARCHAR(150) NULL,
      returned_to_cold_at DATETIME NULL,
      returned_by VARCHAR(150) NULL,
      started_by VARCHAR(150) NULL,
      started_by_id INT NULL,
      updated_by VARCHAR(150) NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uk_solder_paste_code_cycle (codigo_material_recibido, cycle_no),
      INDEX idx_solder_paste_code (codigo_material_recibido),
      INDEX idx_solder_paste_status (status),
      INDEX idx_solder_paste_ambient_ready (status, ambient_ready_at),
      INDEX idx_solder_paste_ready_deadline (status, agitation_deadline_at),
      INDEX idx_solder_paste_agitation_ready (status, agitation_ready_at),
      INDEX idx_solder_paste_expires (status, expires_at)
    )
  `);

  // Los ciclos creados antes de enlazar la pasta con el inventario general de
  // almacén conservan su origen para poder terminarse sin alterar su salida.
  const sourceColumnAdded = await addColumnIfNotExists(
    'solder_paste_process_smd',
    'inventory_source',
    "VARCHAR(32) NULL AFTER inventory_lot_id",
  );
  if (sourceColumnAdded) {
    await pool.query(`
      UPDATE solder_paste_process_smd
      SET inventory_source = 'SMD_LEGACY'
      WHERE inventory_source IS NULL
    `);
    await pool.query(`
      ALTER TABLE solder_paste_process_smd
      MODIFY COLUMN inventory_source VARCHAR(32) NOT NULL DEFAULT 'WAREHOUSE'
    `);
  }

  await addColumnIfNotExists(
    'solder_paste_process_smd',
    'agitation_deadline_at',
    'DATETIME NULL AFTER ambient_ready_at',
  );
  await addColumnIfNotExists(
    'solder_paste_process_smd',
    'returned_to_cold_at',
    'DATETIME NULL AFTER cancelled_by',
  );
  await addColumnIfNotExists(
    'solder_paste_process_smd',
    'returned_by',
    'VARCHAR(150) NULL AFTER returned_to_cold_at',
  );
  await pool.query(`
    UPDATE solder_paste_process_smd
    SET agitation_deadline_at = DATE_ADD(ambient_ready_at, INTERVAL 8 HOUR)
    WHERE agitation_deadline_at IS NULL
  `);
  // Las 12 horas comienzan cuando termina la agitación, no cuando el operador
  // selecciona la línea. Reconstruye el límite de procesos creados previamente.
  await pool.query(`
    UPDATE solder_paste_process_smd
    SET expires_at = DATE_ADD(
          COALESCE(
            agitation_completed_at,
            agitation_ready_at,
            line_started_at,
            updated_at
          ),
          INTERVAL 12 HOUR
        ),
        agitation_completed_at = COALESCE(
          agitation_completed_at,
          agitation_ready_at,
          line_started_at,
          updated_at
        )
    WHERE status IN ('READY_FOR_LINE', 'IN_LINE')
      AND expires_at IS NULL
  `);

  const [readyDeadlineIndex] = await pool.query(`
    SELECT INDEX_NAME
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'solder_paste_process_smd'
      AND INDEX_NAME = 'idx_solder_paste_ready_deadline'
    LIMIT 1
  `);
  if (readyDeadlineIndex.length === 0) {
    await pool.query(`
      CREATE INDEX idx_solder_paste_ready_deadline
      ON solder_paste_process_smd (status, agitation_deadline_at)
    `);
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS solder_paste_event_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      process_id BIGINT NOT NULL,
      event_type VARCHAR(50) NOT NULL,
      from_status VARCHAR(32) NULL,
      to_status VARCHAR(32) NULL,
      usuario VARCHAR(150) NULL,
      metadata JSON NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_solder_paste_event_process (process_id, id),
      INDEX idx_solder_paste_event_created (created_at),
      CONSTRAINT fk_solder_paste_event_process
        FOREIGN KEY (process_id) REFERENCES solder_paste_process_smd(id)
        ON DELETE CASCADE
    )
  `);

  await pool.query(`
    INSERT IGNORE INTO scrap_motivos
      (motivo, activo, creado_por, fecha_creacion)
    VALUES
      ('Pasta de soldadura vencida en línea (12 h)', 1, 'Sistema', NOW()),
      ('Pasta de soldadura excedió 8 h lista para agitación', 1, 'Sistema', NOW())
  `);
  console.log('✓ Tablas de ciclo de vida de pasta de soldadura verificadas/creadas');
}

// ============================================
// METAL MASK / SQUEEGEE
// ============================================
async function createToolingControlTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS tooling_asset_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      asset_type ENUM('METAL_MASK','SQUEEGEE') NOT NULL,
      control_code VARCHAR(80) NOT NULL,
      asset_no VARCHAR(80) NULL,
      location_code VARCHAR(80) NULL,
      pcb_no VARCHAR(150) NULL,
      production_date_raw VARCHAR(40) NULL,
      side VARCHAR(20) NULL,
      lifecycle_status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
      thickness_mm DECIMAL(8,3) NULL,
      use_count BIGINT NOT NULL DEFAULT 0,
      use_limit BIGINT NULL,
      assignment_count BIGINT NOT NULL DEFAULT 0,
      active TINYINT(1) NOT NULL DEFAULT 1,
      source_file VARCHAR(150) NOT NULL DEFAULT 'DATOS METAL Y SQUEGUEE.xlsx',
      last_used_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uk_tooling_control_code (control_code),
      INDEX idx_tooling_type_status (asset_type, active, lifecycle_status)
    )
  `);

  await addColumnIfNotExists(
    'tooling_asset_smd',
    'use_limit',
    'BIGINT NULL AFTER use_count'
  );

  // El plan viene en piezas; lo que desgasta la mask son impresiones. Array = 1
  // deja el conteo como estaba, asi que las masks sin dato no cambian.
  await addColumnIfNotExists(
    'tooling_asset_smd',
    'array_size',
    'INT NOT NULL DEFAULT 1 AFTER thickness_mm'
  );

  // La impresora monta dos squeegees por plan; el segundo llego despues.
  await addColumnIfNotExists(
    'tooling_plan_assignment_smd',
    'squeegee_code_2',
    'VARCHAR(80) NULL AFTER squeegee_code'
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS tooling_plan_assignment_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      event_id VARCHAR(36) NOT NULL,
      plan_source VARCHAR(30) NOT NULL DEFAULT 'plan_smt',
      plan_id BIGINT NOT NULL,
      lot_no VARCHAR(120) NULL,
      part_no VARCHAR(120) NULL,
      model_code VARCHAR(150) NULL,
      line_code VARCHAR(20) NOT NULL,
      working_date DATE NOT NULL,
      shift VARCHAR(20) NULL,
      plan_count INT NOT NULL DEFAULT 0,
      metal_mask_code VARCHAR(80) NOT NULL,
      squeegee_code VARCHAR(80) NOT NULL,
      squeegee_code_2 VARCHAR(80) NULL,
      count_source ENUM('PLAN','SCAN') NOT NULL DEFAULT 'PLAN',
      planned_uses INT NOT NULL DEFAULT 0,
      assigned_at DATETIME NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uk_tooling_event (event_id),
      UNIQUE KEY uk_tooling_plan (plan_source, plan_id),
      INDEX idx_tooling_assignment_date (working_date, line_code),
      INDEX idx_tooling_assignment_mask (metal_mask_code)
    )
  `);

  // Los squeegees solo acumulaban assignment_count: se reconstruyen sus usos
  // desde el log de asignaciones. GREATEST evita perder lo que ya subio un edge.
  await pool.query(`
    UPDATE tooling_asset_smd a
    SET a.use_count = GREATEST(a.use_count, (
      SELECT COALESCE(SUM(p.planned_uses), 0)
      FROM tooling_plan_assignment_smd p
      WHERE p.squeegee_code = a.control_code
    ))
    WHERE a.asset_type = 'SQUEEGEE'
  `);

  // Normaliza los estados heredados del Excel: "USADA"/"RECIENTES" describian
  // desgaste, no disponibilidad, y el edge bloquea todo lo que no sea ACTIVE.
  await pool.query(`
    UPDATE tooling_asset_smd
    SET lifecycle_status = 'ACTIVE', active = 1
    WHERE lifecycle_status IN ('USADA', 'RECIENTES')
  `);

  const catalog = require('../data/toolingCatalog').rows();
  // Limite estandar de vida util. Solo rellena los vacios: un limite ajustado a
  // mano desde la pantalla no se pisa en cada arranque.
  await pool.query(`
    UPDATE tooling_asset_smd SET use_limit = 50000 WHERE use_limit IS NULL
  `);

  // Re-normaliza cualquier pcb_no que aun arrastre version o lado
  // (EAX01882201-D, EAX67445308-1.0 TOP, EAX69871901 VER D). El seed usa
  // COALESCE y no pisa lo ya guardado, asi que la correccion va aparte.
  // Idempotente: solo toca las filas que no estan ya en su forma base.
  await pool.query(`
    UPDATE tooling_asset_smd
    SET pcb_no = REGEXP_REPLACE(pcb_no, '^([A-Za-z]+[0-9]+).*$', '$1')
    WHERE pcb_no IS NOT NULL
      AND pcb_no REGEXP '^[A-Za-z]+[0-9]+.'
      AND pcb_no NOT REGEXP '^[A-Za-z]+[0-9]+$'
  `);

  // COALESCE en las columnas de datos: se rellenan las vacias sin pisar lo que
  // alguien haya corregido a mano desde la pantalla.
  const sql = `
    INSERT INTO tooling_asset_smd (
      asset_type, control_code, asset_no, location_code,
      lifecycle_status, active, pcb_no, production_date_raw, side, thickness_mm,
      array_size, source_file
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'DATOS METAL Y SQUEGUEE.xlsx')
    ON DUPLICATE KEY UPDATE
      asset_type = VALUES(asset_type),
      asset_no = COALESCE(tooling_asset_smd.asset_no, VALUES(asset_no)),
      location_code = COALESCE(tooling_asset_smd.location_code, VALUES(location_code)),
      pcb_no = COALESCE(tooling_asset_smd.pcb_no, VALUES(pcb_no)),
      production_date_raw = COALESCE(tooling_asset_smd.production_date_raw, VALUES(production_date_raw)),
      side = COALESCE(tooling_asset_smd.side, VALUES(side)),
      thickness_mm = COALESCE(tooling_asset_smd.thickness_mm, VALUES(thickness_mm)),
      -- Solo siembra el array de fabrica sobre el default; uno ajustado a mano
      -- desde la pantalla no se pisa en cada arranque.
      array_size = IF(tooling_asset_smd.array_size > 1, tooling_asset_smd.array_size, VALUES(array_size)),
      source_file = VALUES(source_file)
  `;
  for (const item of catalog) {
    await pool.query(sql, [
      item.assetType,
      item.controlCode,
      item.assetNo,
      item.locationCode,
      item.lifecycleStatus,
      item.lifecycleStatus === 'SCRAP' ? 0 : 1,
      item.pcbNo || null,
      item.productionDate || null,
      item.side || null,
      item.thickness ?? null,
      item.arraySize || 1,
    ]);
  }
  console.log(`✓ Catalogo de herramentales verificado (${catalog.length} codigos)`);
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
  await ensureWarehouseCodeIndex();
  await enforceUniqueSmdInventoryLots();
  await enforceNonNegativeSmdInventory();
  await createInventoryAdjustmentSmdTable();
  await createQuarantineTables();
  await ensureQuarantineWarehouseFlag();
  await createCancellationRequestsTable();
  await addIqcColumns();
  await createIqcTables();
  await addMaterialesIqcConfigColumns();
  await createAuditTables();
  await addAuditSnapshotColumns();
  await createAuditPartTable();
  // Primero cierra lo que ya estaba completo, luego los retornos reabren lo
  // que corresponda (el reconcile de retornos debe tener la ultima palabra).
  await reconcileStuckAuditParts();
  await reconcileActiveAuditReturns();
  // El lote viene de la etiqueta y supera los 100 chars originales.
  try {
    await pool.query(`ALTER TABLE material_return_smd MODIFY COLUMN material_lot_no VARCHAR(150) NULL`);
  } catch (e) { }
  await createLotDivisionTable();
  await createRequirementsTables();
  await addReentryColumns();
  await createPcbDefectCatalogTable();
  await createPcbInventoryScanTable();
  await migratePcbInventorySchema();
  await addPcbInventoryTipoMovimiento();
  await createPcbScanDefectsTable();
  await createScrapMotivosTable();
  await createScrapRecordsTable();
  await createScrapRecordEditsTable();
  await widenAssyTypeColumns();
  await createSolderPasteLifecycleTables();
  await createToolingControlTables();
  await migrateScrapAreaColumn();
  await addColumnIfNotExists('scrap_records', 'cantidad', 'INT NOT NULL DEFAULT 1 AFTER usuario_registro');
  await addColumnIfNotExists('scrap_records', 'raw_barcode', 'VARCHAR(180) NULL AFTER part_no');
  await addColumnIfNotExists('scrap_records', 'proceso', 'VARCHAR(30) NULL AFTER area');
  await addColumnIfNotExists('scrap_records', 'cliente', 'VARCHAR(30) NULL AFTER scanned_original_norm');
  await addColumnIfNotExists('scrap_records', 'ubicacion', 'VARCHAR(100) NULL AFTER proceso');
  await addColumnIfNotExists('scrap_record_edits', 'old_raw_barcode', 'VARCHAR(180) NULL AFTER new_part_no');
  await addColumnIfNotExists('scrap_record_edits', 'new_raw_barcode', 'VARCHAR(180) NULL AFTER old_raw_barcode');
  await addColumnIfNotExists('scrap_record_edits', 'old_proceso', 'VARCHAR(30) NULL AFTER new_area');
  await addColumnIfNotExists('scrap_record_edits', 'new_proceso', 'VARCHAR(30) NULL AFTER old_proceso');

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
        cantidad_estandarizada INT NULL DEFAULT NULL,
        cantidad_unidades INT NULL DEFAULT NULL,
        unidad_empaque VARCHAR(50) NULL DEFAULT NULL,
        cantidad_preparada INT DEFAULT 0,
        cantidad_entregada INT DEFAULT 0,

        -- Punto donde debe entregarse el material
        ubicacion_destino VARCHAR(100) NULL DEFAULT NULL,
        
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

    await addColumnIfNotExists(
      'material_requirement_items',
      'cantidad_estandarizada',
      'INT NULL DEFAULT NULL AFTER cantidad_requerida'
    );
    await addColumnIfNotExists(
      'material_requirement_items',
      'cantidad_unidades',
      'INT NULL DEFAULT NULL AFTER cantidad_estandarizada'
    );
    await addColumnIfNotExists(
      'material_requirement_items',
      'unidad_empaque',
      'VARCHAR(50) NULL DEFAULT NULL AFTER cantidad_unidades'
    );
    await addColumnIfNotExists(
      'material_requirement_items',
      'ubicacion_destino',
      'VARCHAR(100) NULL DEFAULT NULL AFTER cantidad_entregada'
    );

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

// ============================================
// SCRAP TABLES
// ============================================

async function createScrapMotivosTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS scrap_motivos (
        id INT AUTO_INCREMENT PRIMARY KEY,
        motivo VARCHAR(200) NOT NULL UNIQUE,
        activo TINYINT DEFAULT 1,
        creado_por VARCHAR(100) NULL,
        fecha_creacion DATETIME NULL,
        actualizado_por VARCHAR(100) NULL,
        fecha_actualizacion DATETIME NULL,
        INDEX idx_activo (activo)
      )
    `);
    console.log('  Tabla scrap_motivos verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla scrap_motivos puede ya existir:', err.message);
  }
}

async function createInventoryAdjustmentSmdTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS inventory_adjustment_smd (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      warehousing_id INT NOT NULL,
      inventory_lot_id INT NOT NULL,
      codigo_material_recibido VARCHAR(128) NOT NULL,
      numero_parte VARCHAR(150) NULL,
      numero_lote VARCHAR(150) NULL,
      quantity_before DECIMAL(12,2) NOT NULL,
      quantity_after DECIMAL(12,2) NOT NULL,
      adjustment_quantity DECIMAL(12,2) NOT NULL,
      movement_type VARCHAR(20) NOT NULL,
      reason VARCHAR(255) NOT NULL,
      usuario_registro VARCHAR(100) NULL,
      usuario_registro_id INT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_inventory_adjustment_smd_code (codigo_material_recibido),
      INDEX idx_inventory_adjustment_smd_created (created_at),
      INDEX idx_inventory_adjustment_smd_lot (inventory_lot_id)
    )
  `);

  console.log('✓ Tabla inventory_adjustment_smd verificada/creada');
}

async function createScrapRecordsTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS scrap_records (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        scanned_original VARCHAR(180) NOT NULL,
        scanned_original_norm VARCHAR(180) NOT NULL,
        cliente VARCHAR(30) NULL,
        assy_type VARCHAR(64) NULL,
        part_no VARCHAR(50) NULL,
        modelo VARCHAR(120) NOT NULL DEFAULT 'N/A',
        area VARCHAR(30) NOT NULL,
        proceso VARCHAR(30) NULL,
        ubicacion VARCHAR(100) NULL,
        motivo_scrap_id INT NULL,
        motivo_scrap_texto VARCHAR(200) NULL,
        comentarios TEXT NULL,
        usuario_registro VARCHAR(100) NULL,
        cantidad INT NOT NULL DEFAULT 1,
        fecha_registro DATETIME NOT NULL,
        INDEX idx_fecha (fecha_registro),
        INDEX idx_area (area),
        INDEX idx_part_no (part_no),
        INDEX idx_norm_fecha (scanned_original_norm, fecha_registro),
        CONSTRAINT fk_scrap_motivo FOREIGN KEY (motivo_scrap_id) REFERENCES scrap_motivos(id) ON DELETE SET NULL
      )
    `);
    console.log('  Tabla scrap_records verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla scrap_records puede ya existir:', err.message);
  }
}

async function createScrapRecordEditsTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS scrap_record_edits (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        scrap_record_id BIGINT NOT NULL,
        old_scanned_original VARCHAR(180) NULL,
        new_scanned_original VARCHAR(180) NULL,
        old_scanned_original_norm VARCHAR(180) NULL,
        new_scanned_original_norm VARCHAR(180) NULL,
        old_assy_type VARCHAR(64) NULL,
        new_assy_type VARCHAR(64) NULL,
        old_part_no VARCHAR(50) NULL,
        new_part_no VARCHAR(50) NULL,
        old_modelo VARCHAR(120) NULL,
        new_modelo VARCHAR(120) NULL,
        old_area VARCHAR(30) NULL,
        new_area VARCHAR(30) NULL,
        old_proceso VARCHAR(30) NULL,
        new_proceso VARCHAR(30) NULL,
        old_motivo_scrap_id INT NULL,
        new_motivo_scrap_id INT NULL,
        old_motivo_scrap_texto VARCHAR(200) NULL,
        new_motivo_scrap_texto VARCHAR(200) NULL,
        old_comentarios TEXT NULL,
        new_comentarios TEXT NULL,
        old_cantidad INT NULL,
        new_cantidad INT NULL,
        edit_reason TEXT NOT NULL,
        edited_by_user_id INT NULL,
        edited_by_name VARCHAR(100) NULL,
        edited_at DATETIME NOT NULL,
        INDEX idx_scrap_record_id (scrap_record_id),
        INDEX idx_edited_at (edited_at),
        CONSTRAINT fk_scrap_record_edit_record FOREIGN KEY (scrap_record_id) REFERENCES scrap_records(id) ON DELETE CASCADE
      )
    `);
    console.log('  Tabla scrap_record_edits verificada/creada');
  } catch (err) {
    console.log('Nota: La tabla scrap_record_edits puede ya existir:', err.message);
  }
}

// assy_type se rellena desde raw.model cuando el codigo se escanea sin ';'
// (entrada manual). raw.model es VARCHAR(64) y assy_type nacio VARCHAR(20), asi
// que cualquier modelo de nombre largo tumbaba el guardado con ER_DATA_TOO_LONG
// ("VF_Better R Ice maker Sub PCBA", 30 caracteres). Se iguala al origen en vez
// de truncar: el nombre del modelo es el dato, no un adorno.
async function widenAssyTypeColumns() {
  const targets = [
    ['scrap_records', ['assy_type']],
    ['scrap_record_edits', ['old_assy_type', 'new_assy_type']],
    ['pcb_inventory_scan_smd', ['assy_type']],
    // La crea Control_produccion; si esta en esta base se amplia igual.
    ['pcb_inventory_scan_prod', ['assy_type']],
  ];
  for (const [table, columns] of targets) {
    for (const column of columns) {
      const [rows] = await pool.query(`
        SELECT CHARACTER_MAXIMUM_LENGTH AS largo
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
      `, [table, column]);
      if (!rows.length || Number(rows[0].largo) >= 64) continue;
      await pool.query(`ALTER TABLE \`${table}\` MODIFY COLUMN \`${column}\` VARCHAR(64) NULL`);
      console.log(`  ${table}.${column} ampliada a VARCHAR(64)`);
    }
  }
  console.log('\u2713 Columnas assy_type verificadas (VARCHAR(64), igual que raw.model)');
}

// Migrar columna area de scrap_records de ENUM a VARCHAR
async function migrateScrapAreaColumn() {
  try {
    const [cols] = await pool.query(`
      SELECT COLUMN_TYPE
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'scrap_records'
      AND COLUMN_NAME = 'area'
      LIMIT 1
    `);
    const colType = (cols[0]?.COLUMN_TYPE || '').toLowerCase();
    if (colType.startsWith('enum')) {
      await pool.query(`
        ALTER TABLE scrap_records
        MODIFY COLUMN area VARCHAR(30) NOT NULL
      `);
      console.log('\u2713 Columna scrap_records.area migrada de ENUM a VARCHAR(30)');
    }
  } catch (err) {
    console.log('Nota: Error migrando scrap_records.area:', err.message);
  }
}

module.exports = {
  runMigrations,
  enforceUniqueSmdInventoryLots,
  enforceNonNegativeSmdInventory,
  createInventoryAdjustmentSmdTable,
  createPcbDefectCatalogTable,
  createPcbScanDefectsTable,
  migratePcbInventorySchema,
  addPcbInventoryTipoMovimiento,
  addColumnIfNotExists
};


