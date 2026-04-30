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
    console.log('\n🔧 Actualizando triggers para excluir Pending/InProgress del inventario...\n');
    
    // Eliminar los triggers problemáticos
    await pool.query('DROP TRIGGER IF EXISTS trg_inventario_lotes_entrada_ai');
    console.log('✅ Eliminado: trg_inventario_lotes_entrada_ai');
    
    await pool.query('DROP TRIGGER IF EXISTS trg_inventario_lotes_entrada_au');
    console.log('✅ Eliminado: trg_inventario_lotes_entrada_au');

    // Eliminar trigger de INSERT para recrearlo con filtro de iqc_status
    await pool.query('DROP TRIGGER IF EXISTS trg_almacen_ai');
    console.log('✅ Eliminado: trg_almacen_ai (se recreará con filtro iqc_status)');

    // Eliminar trigger de UPDATE para recrearlo
    await pool.query('DROP TRIGGER IF EXISTS trg_almacen_au');
    console.log('✅ Eliminado: trg_almacen_au (se recreará correctamente)');

    // Crear trigger de INSERT que SOLO cuenta materiales Released o NotRequired
    const createTriggerAI = `
      CREATE TRIGGER trg_almacen_ai
      AFTER INSERT ON control_material_almacen_smd
      FOR EACH ROW
      BEGIN
          -- Solo contar en inventario si el material está Released o NotRequired
          -- Pending e InProgress NO deben contarse
          IF NEW.cancelado = 0 AND NEW.iqc_status IN ('Released', 'NotRequired') THEN
              INSERT INTO inventario_lotes_smd (
                  codigo_material_recibido, numero_parte, numero_lote,
                  total_entrada, total_salida, primer_recibo
              ) VALUES (
                  NEW.codigo_material_recibido, NEW.numero_parte, NEW.numero_lote_material,
                  NEW.cantidad_actual, 0, NEW.fecha_recibo
              )
              ON DUPLICATE KEY UPDATE
                  total_entrada = total_entrada + NEW.cantidad_actual,
                  primer_recibo = LEAST(primer_recibo, NEW.fecha_recibo);
          END IF;
      END
    `;
    
    await pool.query(createTriggerAI);
    console.log('✅ Creado: trg_almacen_ai (solo cuenta Released/NotRequired)');

    // Recrear trigger de UPDATE correctamente
    const createTriggerAU = `
      CREATE TRIGGER trg_almacen_au
      AFTER UPDATE ON control_material_almacen_smd
      FOR EACH ROW
      BEGIN
          DECLARE diff DECIMAL(12,2);
          DECLARE antes_se_contaba TINYINT(1);
          DECLARE ahora_se_cuenta  TINYINT(1);

          SET antes_se_contaba = (
              OLD.cancelado = 0
              AND OLD.iqc_status IN ('Released', 'NotRequired')
          );

          SET ahora_se_cuenta = (
              NEW.cancelado = 0
              AND NEW.iqc_status IN ('Released', 'NotRequired')
          );

          -- CASO 1: se cancela algo que sí se contaba -> RESTAR
          IF OLD.cancelado = 0 AND NEW.cancelado = 1 AND antes_se_contaba = 1 THEN
              UPDATE inventario_lotes_smd
              SET total_entrada = total_entrada - OLD.cantidad_actual
              WHERE codigo_material_recibido = OLD.codigo_material_recibido
                AND numero_parte = OLD.numero_parte
                AND numero_lote = OLD.numero_lote_material;

          -- CASO 2: antes NO se contaba y ahora SÍ -> INSERTAR/SUMAR
          ELSEIF antes_se_contaba = 0 AND ahora_se_cuenta = 1 THEN
              INSERT INTO inventario_lotes_smd (
                  codigo_material_recibido, numero_parte, numero_lote,
                  total_entrada, total_salida, primer_recibo
              ) VALUES (
                  NEW.codigo_material_recibido, NEW.numero_parte, NEW.numero_lote_material,
                  NEW.cantidad_actual, 0, NEW.fecha_recibo
              )
              ON DUPLICATE KEY UPDATE
                  total_entrada = total_entrada + NEW.cantidad_actual,
                  primer_recibo = LEAST(primer_recibo, NEW.fecha_recibo);

          -- CASO 3: antes SÍ se contaba y ahora TAMBIÉN, pero cambió la cantidad
          ELSEIF antes_se_contaba = 1 AND ahora_se_cuenta = 1
             AND OLD.cantidad_actual <> NEW.cantidad_actual THEN
              SET diff = NEW.cantidad_actual - OLD.cantidad_actual;
              UPDATE inventario_lotes_smd
              SET total_entrada = total_entrada + diff
              WHERE codigo_material_recibido = NEW.codigo_material_recibido
                AND numero_parte = NEW.numero_parte
                AND numero_lote = NEW.numero_lote_material;

          -- CASO 4: antes SÍ contaba y ahora NO (cambio de status) -> RESTAR
          ELSEIF antes_se_contaba = 1 AND ahora_se_cuenta = 0 THEN
              UPDATE inventario_lotes_smd
              SET total_entrada = total_entrada - OLD.cantidad_actual
              WHERE codigo_material_recibido = OLD.codigo_material_recibido
                AND numero_parte = OLD.numero_parte
                AND numero_lote = OLD.numero_lote_material;
          END IF;
      END
    `;
    
    await pool.query(createTriggerAU);
    console.log('✅ Creado: trg_almacen_au (con lógica de iqc_status)');

    console.log('\n✅ Triggers actualizados exitosamente!');
    console.log('📋 Ahora solo los materiales con iqc_status Released o NotRequired se cuentan en inventario.');
    console.log('📋 Materiales con Pending o InProgress NO afectan el inventario.\n');
    
    // Recalcular inventario existente para corregir datos actuales
    console.log('🔄 Recalculando inventario actual basado en las nuevas reglas...\n');
    
    // Primero, resetear total_entrada a 0
    await pool.query('UPDATE inventario_lotes_smd SET total_entrada = 0');
    
    // Luego, recalcular solo con materiales Released/NotRequired
    const recalcularQuery = `
      UPDATE inventario_lotes_smd il
      SET total_entrada = (
          SELECT COALESCE(SUM(cantidad_actual), 0)
          FROM control_material_almacen_smd cma
          WHERE cma.codigo_material_recibido = il.codigo_material_recibido
            AND cma.numero_parte = il.numero_parte
            AND cma.numero_lote_material = il.numero_lote
            AND cma.cancelado = 0
            AND cma.iqc_status IN ('Released', 'NotRequired')
      )
    `;
    await pool.query(recalcularQuery);
    console.log('✅ Inventario recalculado (solo Released/NotRequired)');

    console.log('\n✅ Proceso completado exitosamente!\n');

    // Verificar triggers actuales
    console.log('=== Triggers actuales en control_material_almacen_smd ===');
    const [triggers] = await pool.query("SHOW TRIGGERS WHERE `Table` = 'control_material_almacen_smd'");
    triggers.forEach(t => console.log(`- ${t.Trigger} (${t.Event})`));

  } catch (err) {
    console.error('❌ Error:', err.message);
  }

  await pool.end();
}

run();
