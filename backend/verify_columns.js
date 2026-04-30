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
    const [rows] = await pool.query(`
      SELECT id, receiving_lot_code, 
        rohs_result, brightness_result, dimension_result, color_result, appearance_result
      FROM iqc_inspection_lot_smd 
      WHERE status = 'Closed'
      ORDER BY id DESC
      LIMIT 5
    `);
    
    console.log('=== Valores reales en BD ===\n');
    rows.forEach(r => {
      console.log(`ID ${r.id}: ${r.receiving_lot_code}`);
      console.log(`  rohs: "${r.rohs_result}" | brightness: "${r.brightness_result}" | dimension: "${r.dimension_result}"`);
      console.log(`  color: "${r.color_result}" | appearance: "${r.appearance_result}"`);
      console.log('');
    });

  } catch (err) {
    console.error('Error:', err.message);
  }

  await pool.end();
}

run();
