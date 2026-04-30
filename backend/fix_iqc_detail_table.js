require('dotenv').config();
const mysql = require('mysql2/promise');

async function run() {
  const pool = await mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '3306'),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'meslocal'
  });

  try {
    console.log('\n🔧 Actualizando tabla iqc_inspection_detail_smd...\n');
    
    // Verificar si la tabla existe
    const [tables] = await pool.query("SHOW TABLES LIKE 'iqc_inspection_detail_smd'");
    
    if (tables.length === 0) {
      console.log('⚠️ Tabla iqc_inspection_detail_smd no existe. Creándola...');
      await pool.query(`
        CREATE TABLE iqc_inspection_detail_smd (
          id INT AUTO_INCREMENT PRIMARY KEY,
          inspection_lot_id INT NOT NULL,
          sample_number INT NOT NULL,
          characteristic VARCHAR(50) NOT NULL,
          test_name VARCHAR(100) NULL,
          measured_value VARCHAR(50) NULL,
          unit VARCHAR(20) NULL,
          min_spec VARCHAR(50) NULL,
          max_spec VARCHAR(50) NULL,
          result VARCHAR(20) NOT NULL,
          remarks TEXT NULL,
          measured_by VARCHAR(100) NULL,
          measured_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          INDEX idx_detail_lot (inspection_lot_id),
          INDEX idx_detail_characteristic (characteristic)
        )
      `);
      console.log('✅ Tabla creada exitosamente');
    } else {
      console.log('✅ Tabla existe. Verificando columnas...');
      
      // Verificar la columna result
      const [columns] = await pool.query("DESCRIBE iqc_inspection_detail_smd");
      const resultCol = columns.find(c => c.Field === 'result');
      const testNameCol = columns.find(c => c.Field === 'test_name');
      const characteristicCol = columns.find(c => c.Field === 'characteristic');
      
      if (resultCol) {
        console.log(`   - result: ${resultCol.Type}`);
        if (resultCol.Type.includes('enum')) {
          console.log('   Cambiando result de ENUM a VARCHAR...');
          await pool.query("ALTER TABLE iqc_inspection_detail_smd MODIFY COLUMN result VARCHAR(20) NOT NULL");
          console.log('   ✅ Columna result actualizada');
        }
      }
      
      if (testNameCol) {
        console.log(`   - test_name: ${testNameCol.Type} ${testNameCol.Null}`);
        if (testNameCol.Null === 'NO') {
          console.log('   Haciendo test_name nullable...');
          await pool.query("ALTER TABLE iqc_inspection_detail_smd MODIFY COLUMN test_name VARCHAR(100) NULL");
          console.log('   ✅ Columna test_name actualizada');
        }
      } else {
        console.log('   Agregando columna test_name...');
        await pool.query("ALTER TABLE iqc_inspection_detail_smd ADD COLUMN test_name VARCHAR(100) NULL AFTER characteristic");
        console.log('   ✅ Columna test_name agregada');
      }
      
      if (characteristicCol) {
        console.log(`   - characteristic: ${characteristicCol.Type}`);
        if (characteristicCol.Type.includes('enum')) {
          console.log('   Cambiando characteristic de ENUM a VARCHAR...');
          await pool.query("ALTER TABLE iqc_inspection_detail_smd MODIFY COLUMN characteristic VARCHAR(50) NOT NULL");
          console.log('   ✅ Columna characteristic actualizada');
        }
      }
    }

    console.log('\n✅ Tabla iqc_inspection_detail_smd lista!\n');

    // Mostrar estructura final
    console.log('=== Estructura final ===');
    const [finalCols] = await pool.query("DESCRIBE iqc_inspection_detail_smd");
    finalCols.forEach(c => console.log(`${c.Field}: ${c.Type} ${c.Null === 'YES' ? 'NULL' : 'NOT NULL'}`));

  } catch (err) {
    console.error('❌ Error:', err.message);
  }

  await pool.end();
}

run();
