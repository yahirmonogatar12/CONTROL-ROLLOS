/**
 * Migration Script: Add unidad_medida column to tables
 * Run once: node add_unit_column.js
 * 
 * Adds Unit of Measure column with options:
 * - EA (Element/Piece) - Default
 * - m (Meter)
 * - kg (Kilogram)
 * - g (Gram)
 * - mg (Milligram)
 */

require('dotenv').config();
const { pool } = require('./config/database');

async function addUnitColumn() {
  console.log('='.repeat(50));
  console.log('Adding unidad_medida column to tables');
  console.log('='.repeat(50));

  try {
    // 1. Check and add to materiales table
    const [matColumns] = await pool.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'materiales' 
        AND COLUMN_NAME = 'unidad_medida'
    `);

    if (matColumns.length > 0) {
      console.log('✓ Column unidad_medida already exists in materiales');
    } else {
      await pool.query(`
        ALTER TABLE materiales 
        ADD COLUMN unidad_medida VARCHAR(10) DEFAULT 'EA' 
        AFTER unidad_empaque
      `);
      console.log('✓ Column unidad_medida added to materiales');
    }

    // 2. Check and add to control_material_almacen_smd table
    const [whColumns] = await pool.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'control_material_almacen_smd' 
        AND COLUMN_NAME = 'unidad_medida'
    `);

    if (whColumns.length > 0) {
      console.log('✓ Column unidad_medida already exists in control_material_almacen_smd');
    } else {
      await pool.query(`
        ALTER TABLE control_material_almacen_smd 
        ADD COLUMN unidad_medida VARCHAR(10) DEFAULT 'EA' 
        AFTER cantidad_estandarizada
      `);
      console.log('✓ Column unidad_medida added to control_material_almacen_smd');
    }

    // 3. Check and add to inventario_lotes_smd table
    const [invColumns] = await pool.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'inventario_lotes_smd' 
        AND COLUMN_NAME = 'unidad_medida'
    `);

    if (invColumns.length > 0) {
      console.log('✓ Column unidad_medida already exists in inventario_lotes_smd');
    } else {
      await pool.query(`
        ALTER TABLE inventario_lotes_smd 
        ADD COLUMN unidad_medida VARCHAR(10) DEFAULT 'EA' 
        AFTER stock_actual
      `);
      console.log('✓ Column unidad_medida added to inventario_lotes_smd');
    }

    // 4. Set default values for existing records
    const [matUpdated] = await pool.query(`
      UPDATE materiales SET unidad_medida = 'EA' WHERE unidad_medida IS NULL OR unidad_medida = ''
    `);
    console.log(`✓ Updated ${matUpdated.affectedRows} materiales records with default 'EA'`);

    const [whUpdated] = await pool.query(`
      UPDATE control_material_almacen_smd SET unidad_medida = 'EA' WHERE unidad_medida IS NULL OR unidad_medida = ''
    `);
    console.log(`✓ Updated ${whUpdated.affectedRows} warehousing records with default 'EA'`);

    const [invUpdated] = await pool.query(`
      UPDATE inventario_lotes_smd SET unidad_medida = 'EA' WHERE unidad_medida IS NULL OR unidad_medida = ''
    `);
    console.log(`✓ Updated ${invUpdated.affectedRows} inventory records with default 'EA'`);

    console.log('\n' + '='.repeat(50));
    console.log('Migration completed successfully!');
    console.log('Valid units: EA, m, kg, g, mg');
    console.log('='.repeat(50));

  } catch (error) {
    console.error('Migration failed:', error.message);
  } finally {
    process.exit(0);
  }
}

addUnitColumn();
