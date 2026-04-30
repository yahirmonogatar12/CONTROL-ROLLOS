/**
 * Script para agregar columnas de Reingreso a la tabla control_material_almacen_smd
 * Ejecutar: node add_reentry_columns.js
 */

const { pool } = require('./config/database');

async function addReentryColumns() {
  console.log('🚀 Agregando columnas de Reingreso...\n');

  const alterStatements = [
    {
      name: 'fecha_reingreso',
      sql: `ALTER TABLE control_material_almacen_smd ADD COLUMN fecha_reingreso DATETIME NULL`,
      description: 'Fecha/hora del último reingreso'
    },
    {
      name: 'ubicacion_anterior',
      sql: `ALTER TABLE control_material_almacen_smd ADD COLUMN ubicacion_anterior VARCHAR(100) NULL`,
      description: 'Ubicación antes del reingreso'
    },
    {
      name: 'usuario_reingreso',
      sql: `ALTER TABLE control_material_almacen_smd ADD COLUMN usuario_reingreso VARCHAR(100) NULL`,
      description: 'Usuario que realizó el reingreso'
    }
  ];

  for (const stmt of alterStatements) {
    try {
      await pool.query(stmt.sql);
      console.log(`✅ Columna '${stmt.name}' agregada - ${stmt.description}`);
    } catch (err) {
      if (err.code === 'ER_DUP_FIELDNAME') {
        console.log(`⚠️  Columna '${stmt.name}' ya existe - omitiendo`);
      } else {
        console.error(`❌ Error agregando '${stmt.name}':`, err.message);
      }
    }
  }

  // Crear índice para búsquedas por fecha de reingreso
  try {
    await pool.query(`CREATE INDEX idx_fecha_reingreso ON control_material_almacen_smd(fecha_reingreso)`);
    console.log('✅ Índice idx_fecha_reingreso creado');
  } catch (err) {
    if (err.code === 'ER_DUP_KEYNAME') {
      console.log('⚠️  Índice idx_fecha_reingreso ya existe - omitiendo');
    } else {
      console.error('❌ Error creando índice:', err.message);
    }
  }

  console.log('\n✅ Migración de Reingreso completada');
  process.exit(0);
}

addReentryColumns().catch(err => {
  console.error('Error fatal:', err);
  process.exit(1);
});
