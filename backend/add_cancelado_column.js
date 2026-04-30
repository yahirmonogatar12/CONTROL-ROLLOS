// Script para agregar columna cancelado a la tabla
const mysql = require('mysql2/promise');

async function addCanceladoColumn() {
  const connection = await mysql.createConnection({
    host: 'up-de-fra1-mysql-1.db.run-on-seenode.com',
    port: 11550,
    user: 'db_rrpq0erbdujn',
    password: '5fUNbSRcPP3LN9K2I33Pr0ge',
    database: 'db_rrpq0erbdujn'
  });

  try {
    console.log('Conectado a MySQL...');
    
    // Verificar si la columna existe
    const [columns] = await connection.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_SCHEMA = 'db_rrpq0erbdujn' 
      AND TABLE_NAME = 'control_material_almacen_smd' 
      AND COLUMN_NAME = 'cancelado'
    `);
    
    if (columns.length === 0) {
      console.log('Agregando columna cancelado...');
      await connection.query(`
        ALTER TABLE control_material_almacen_smd 
        ADD COLUMN cancelado TINYINT DEFAULT 0
      `);
      console.log('✓ Columna "cancelado" agregada exitosamente');
    } else {
      console.log('✓ La columna "cancelado" ya existe');
    }
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await connection.end();
    console.log('Conexión cerrada');
  }
}

addCanceladoColumn();
