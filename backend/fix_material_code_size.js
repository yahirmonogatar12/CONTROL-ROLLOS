require('dotenv').config();
const mysql = require('mysql2/promise');

async function run() {
  const pool = await mysql.createPool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    port: parseInt(process.env.DB_PORT || '3306')
  });

  try {
    // Verificar tamaño actual
    const [cols] = await pool.query('DESCRIBE iqc_inspection_lot_smd');
    const matCol = cols.find(c => c.Field === 'material_code');
    console.log('Tamaño actual de material_code:', matCol ? matCol.Type : 'No encontrado');

    // Cambiar a TEXT para soportar códigos muy largos
    await pool.query('ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN material_code TEXT NULL');
    console.log('✅ Columna material_code actualizada a TEXT');

    // Verificar cambio
    const [cols2] = await pool.query('DESCRIBE iqc_inspection_lot_smd');
    const matCol2 = cols2.find(c => c.Field === 'material_code');
    console.log('Nuevo tamaño:', matCol2 ? matCol2.Type : 'Error');

  } catch (err) {
    console.error('Error:', err.message);
  }

  await pool.end();
}

run();
