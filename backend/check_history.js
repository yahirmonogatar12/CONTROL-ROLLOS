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
    // Verificar tipo de columnas de resultado
    console.log('=== Verificando tipos de columnas ===\n');
    const [columns] = await pool.query("DESCRIBE iqc_inspection_lot_smd");
    const resultColumns = columns.filter(c => c.Field.includes('result'));
    resultColumns.forEach(c => console.log(`${c.Field}: ${c.Type}`));

    // Modificar columnas ENUM a VARCHAR para soportar Pass/Fail
    console.log('\n=== Actualizando columnas a VARCHAR ===\n');
    
    const resultFields = ['rohs_result', 'brightness_result', 'dimension_result', 'color_result', 'appearance_result'];
    
    for (const field of resultFields) {
      try {
        await pool.query(`ALTER TABLE iqc_inspection_lot_smd MODIFY COLUMN ${field} VARCHAR(20) DEFAULT 'Pending'`);
        console.log(`✅ ${field} actualizado a VARCHAR(20)`);
      } catch (e) {
        console.log(`⚠️ ${field}: ${e.message}`);
      }
    }

    console.log('\n=== Estructura final ===\n');
    const [finalColumns] = await pool.query("DESCRIBE iqc_inspection_lot_smd");
    const finalResultColumns = finalColumns.filter(c => c.Field.includes('result'));
    finalResultColumns.forEach(c => console.log(`${c.Field}: ${c.Type}`));

  } catch (err) {
    console.error('Error:', err.message);
  }

  await pool.end();
}

run();
