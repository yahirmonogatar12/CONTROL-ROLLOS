const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const mysql = require('mysql2/promise');

async function cancelAllRecords() {
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME
  });

  try {
    console.log('📝 Marcando registros como cancelados (el historial se mantiene)...');
    
    // Marcar como cancelado en control_material_almacen_smd
    const [resultAlmacen] = await connection.query(
      'UPDATE control_material_almacen_smd SET cancelado = 1 WHERE cancelado = 0'
    );
    console.log(`✓ control_material_almacen_smd: ${resultAlmacen.affectedRows} registros marcados como cancelados`);
    
    // Marcar como cancelado en control_material_salida_smd (si tiene columna cancelado)
    try {
      const [resultSalida] = await connection.query(
        'UPDATE control_material_salida_smd SET cancelado = 1 WHERE cancelado = 0'
      );
      console.log(`✓ control_material_salida_smd: ${resultSalida.affectedRows} registros marcados como cancelados`);
    } catch (e) {
      console.log('⚠️ control_material_salida_smd: no tiene columna cancelado o está vacía');
    }
    
    // Marcar como cancelado en material_return_smd (si tiene columna cancelado)
    try {
      const [resultReturn] = await connection.query(
        'UPDATE material_return_smd SET cancelado = 1 WHERE cancelado = 0'
      );
      console.log(`✓ material_return_smd: ${resultReturn.affectedRows} registros marcados como cancelados`);
    } catch (e) {
      console.log('⚠️ material_return_smd: no tiene columna cancelado o está vacía');
    }
    
    console.log('');
    console.log('✅ Todos los registros fueron marcados como cancelados.');
    console.log('📋 El historial se mantiene intacto para consultas.');
  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    await connection.end();
  }
}

cancelAllRecords();
