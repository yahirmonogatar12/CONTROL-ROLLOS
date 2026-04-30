/**
 * Script para aplicar el trigger trg_mounter_ai_smd
 * 
 * Este trigger conecta el historial de escaneo de mounters SMD
 * con el sistema de inventario, generando salidas automaticas.
 * 
 * Uso: node backend/scripts/apply_mounter_trigger.js
 */

const fs = require('fs');
const path = require('path');
const pool = require('../config/database');

async function applyMounterTrigger() {
  let connection;
  try {
    connection = await pool.getConnection();
    console.log('Conectado a la base de datos.');

    // Leer el archivo SQL
    const sqlPath = path.join(__dirname, '..', 'sql', 'trigger_mounter_salida.sql');
    const sqlContent = fs.readFileSync(sqlPath, 'utf8');

    // Extraer los statements individuales (separados por DELIMITER)
    // El archivo usa DELIMITER $$ ... $$ DELIMITER ;
    // Ejecutamos DROP y CREATE por separado

    // 1. Drop trigger
    console.log('Eliminando trigger anterior si existe...');
    await connection.query('DROP TRIGGER IF EXISTS trg_mounter_ai_smd');

    // 2. Extraer el CREATE TRIGGER statement
    const createMatch = sqlContent.match(/CREATE TRIGGER[\s\S]+?END/);
    if (!createMatch) {
      throw new Error('No se encontro el CREATE TRIGGER en el archivo SQL');
    }

    console.log('Creando trigger trg_mounter_ai_smd...');
    await connection.query(createMatch[0]);

    // 3. Verificar
    const [triggers] = await connection.query(`
      SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION
      FROM INFORMATION_SCHEMA.TRIGGERS
      WHERE TRIGGER_SCHEMA = DATABASE()
        AND TRIGGER_NAME = 'trg_mounter_ai_smd'
    `);

    if (triggers.length > 0) {
      console.log('Trigger creado exitosamente:');
      console.log(`  Nombre: ${triggers[0].TRIGGER_NAME}`);
      console.log(`  Tabla: ${triggers[0].EVENT_OBJECT_TABLE}`);
      console.log(`  Evento: ${triggers[0].ACTION_TIMING} ${triggers[0].EVENT_MANIPULATION}`);
    } else {
      console.error('ERROR: El trigger no se creo correctamente.');
      process.exit(1);
    }

    console.log('\nFlujo del trigger:');
    console.log('  1. INSERT en historial_cambio_material_smt (escaneo en mounter)');
    console.log('  2. Busca Barcode en control_material_almacen_smd (tiene_salida=0, cancelado=0)');
    console.log('  3. INSERT en control_material_salida_smd (depto=SMD, proceso=Mounter)');
    console.log('  4. UPDATE tiene_salida=1 en control_material_almacen_smd');
    console.log('  5. trg_salida_ai_smd actualiza inventario_lotes_smd automaticamente');
    console.log('\nMapeo de lineas:');
    console.log('  1line -> LINEA A | 2line -> LINEA B | 3line -> LINEA C | 4line -> LINEA D');

  } catch (err) {
    console.error('Error aplicando trigger:', err.message);
    process.exit(1);
  } finally {
    if (connection) connection.release();
    await pool.end();
  }
}

applyMounterTrigger();
