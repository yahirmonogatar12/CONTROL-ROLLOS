// Script para agregar la columna tiene_salida
const { pool } = require('./config/database');

async function addColumn() {
  try {
    console.log('Intentando agregar columna tiene_salida...');
    
    // Verificar si la columna ya existe
    const [columns] = await pool.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'control_material_almacen_smd' 
        AND COLUMN_NAME = 'tiene_salida'
    `);
    
    if (columns.length > 0) {
      console.log('La columna tiene_salida ya existe.');
    } else {
      // Agregar la columna
      await pool.query(`
        ALTER TABLE control_material_almacen_smd 
        ADD COLUMN tiene_salida TINYINT DEFAULT 0
      `);
      console.log('✓ Columna tiene_salida agregada correctamente!');
    }
    
    // Verificar que se creó correctamente
    const [verify] = await pool.query(`
      SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'control_material_almacen_smd' 
        AND COLUMN_NAME = 'tiene_salida'
    `);
    
    if (verify.length > 0) {
      console.log('Verificación:', verify[0]);
    }
    
    process.exit(0);
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

addColumn();
