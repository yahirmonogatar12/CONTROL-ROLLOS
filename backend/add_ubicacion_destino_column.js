/**
 * Script para agregar la columna ubicacion_destino a control_material_almacen_smd
 * Esta columna permite registrar a donde va el material cuando se recibe
 */
const { pool } = require('./config/database');

async function addUbicacionDestinoColumn() {
  try {
    console.log('Verificando si la columna ubicacion_destino existe...');
    
    // Verificar si la columna ya existe
    const [columns] = await pool.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'control_material_almacen_smd' 
        AND COLUMN_NAME = 'ubicacion_destino'
    `);

    if (columns.length > 0) {
      console.log('La columna ubicacion_destino ya existe.');
      return;
    }

    // Agregar la columna
    console.log('Agregando columna ubicacion_destino...');
    await pool.query(`
      ALTER TABLE control_material_almacen_smd 
      ADD COLUMN ubicacion_destino VARCHAR(100) NULL AFTER ubicacion_salida
    `);
    
    console.log('Columna ubicacion_destino agregada exitosamente.');
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await pool.end();
    process.exit(0);
  }
}

addUbicacionDestinoColumn();
