#!/usr/bin/env node
// Ejecuta backend/sql/apply_smd_triggers.sql de forma segura (ejecuta bloques CREATE TRIGGER por separado)
// Uso: node backend/scripts/apply_smd_triggers.js

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });
const { pool } = require('../config/database');

const SQL_PATH = path.resolve(__dirname, '..', 'sql', 'apply_smd_triggers.sql');

const extractTriggerBlocks = (sql) => {
  // Normalizar y eliminar declaraciones DELIMITER (soporta $$ u otros usados en el SQL generado)
  let normalized = sql.replace(/\r\n/g, '\n').replace(/^\s*DELIMITER\s+\S+\s*$/gim, '');
  // convertir terminadores personalizados (ej. $$) a ';' cuando siguen a END
  normalized = normalized.replace(/END\s*\$\$/gi, 'END;');
  normalized = normalized.replace(/END\s*\/\//gi, 'END;');
  // quitar delimitadores sueltos (líneas que contienen solo $$) y variantes como ";$$"
  normalized = normalized.replace(/^\s*\$\$\s*$/gim, '');
  normalized = normalized.replace(/;\s*\$\$/g, ';');
  // eliminar cualquier token DELIMITER remanente
  normalized = normalized.replace(/DELIMITER\s+\$\$/gi, '');
  // limpiar dobles puntos y espacios
  normalized = normalized.replace(/;;+/g, ';');

  const re = /CREATE\s+TRIGGER[\s\S]*?END\s*;/gi;
  const blocks = [];
  let m;
  while ((m = re.exec(normalized)) !== null) {
    blocks.push(m[0]);
  }
  const remainder = normalized.replace(re, '\n');
  return { blocks, remainder };
};

const splitStatements = (sql) => {
  return sql
    .split(';')
    .map(s => s.trim())
    .filter(s => s.length > 0 && !/^--/.test(s));
};

(async () => {
  console.log('⚙️  apply_smd_triggers: comenzando (usar en staging, haga backup antes)');
  const conn = await pool.getConnection();
  try {
    // Crear tablas fork explícitamente (evita parsear el SQL completo)
    const createStmts = [
      "CREATE TABLE IF NOT EXISTS control_material_salida_smd LIKE control_material_salida",
      "CREATE TABLE IF NOT EXISTS inventario_lotes_smd LIKE inventario_lotes",
      "CREATE TABLE IF NOT EXISTS material_return_smd LIKE material_return"
    ];

    for (const s of createStmts) {
      console.log('> ejecutando:', s);
      await conn.query(s + ';');
    }

    // Trigger definitions (adaptadas al esquema _smd)
    const triggerDefs = [
      {
        name: 'trg_almacen_ai_smd',
        sql: `DROP TRIGGER IF EXISTS trg_almacen_ai_smd; CREATE TRIGGER trg_almacen_ai_smd
AFTER INSERT ON control_material_almacen_smd
FOR EACH ROW
BEGIN
  IF NEW.iqc_status IN ('Released', 'NotRequired') THEN
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
END;`
      },
      {
        name: 'trg_almacen_au_smd',
        sql: `DROP TRIGGER IF EXISTS trg_almacen_au_smd; CREATE TRIGGER trg_almacen_au_smd
AFTER UPDATE ON control_material_almacen_smd
FOR EACH ROW
BEGIN
  DECLARE diff DECIMAL(12,2);
  DECLARE antes_se_contaba TINYINT(1);
  DECLARE ahora_se_cuenta  TINYINT(1);

  IF (OLD.cancelado = 0 OR OLD.cancelado IS NULL) AND NEW.cancelado = 1 THEN
    UPDATE inventario_lotes_smd
    SET total_entrada = GREATEST(0, total_entrada - OLD.cantidad_actual)
    WHERE codigo_material_recibido = OLD.codigo_material_recibido
      AND numero_parte = OLD.numero_parte
      AND numero_lote = OLD.numero_lote_material;
  ELSE
    IF NEW.cancelado = 0 OR NEW.cancelado IS NULL THEN
      SET antes_se_contaba = (OLD.iqc_status IN ('Released', 'NotRequired'));
      SET ahora_se_cuenta  = (NEW.iqc_status IN ('Released', 'NotRequired'));

      IF antes_se_contaba = 0 AND ahora_se_cuenta = 1 THEN
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

      ELSEIF antes_se_contaba = 1 AND ahora_se_cuenta = 1 AND OLD.cantidad_actual <> NEW.cantidad_actual THEN
        SET diff = NEW.cantidad_actual - OLD.cantidad_actual;
        UPDATE inventario_lotes_smd
        SET total_entrada = total_entrada + diff
        WHERE codigo_material_recibido = NEW.codigo_material_recibido
          AND numero_parte = NEW.numero_parte
          AND numero_lote = NEW.numero_lote_material;

      ELSEIF antes_se_contaba = 1 AND ahora_se_cuenta = 0 THEN
        UPDATE inventario_lotes_smd
        SET total_entrada = total_entrada - OLD.cantidad_actual
        WHERE codigo_material_recibido = OLD.codigo_material_recibido
          AND numero_parte = OLD.numero_parte
          AND numero_lote = OLD.numero_lote_material;
      END IF;
    END IF;
  END IF;
END;`
      },
      {
        name: 'trg_salida_ai_smd',
        sql: `DROP TRIGGER IF EXISTS trg_salida_ai_smd; CREATE TRIGGER trg_salida_ai_smd
AFTER INSERT ON control_material_salida_smd
FOR EACH ROW
INSERT INTO inventario_lotes_smd (
  codigo_material_recibido,
  numero_parte,
  numero_lote,
  total_salida,
  ultima_salida
)
VALUES (
  NEW.codigo_material_recibido,
  NEW.numero_parte,
  NEW.numero_lote,
  NEW.cantidad_salida,
  NEW.fecha_salida
)
ON DUPLICATE KEY UPDATE
  total_salida  = total_salida + NEW.cantidad_salida,
  ultima_salida = GREATEST(ultima_salida, NEW.fecha_salida);`
      },
      {
        name: 'trg_return_ai_smd',
        sql: `DROP TRIGGER IF EXISTS trg_return_ai_smd; CREATE TRIGGER trg_return_ai_smd
AFTER INSERT ON material_return_smd
FOR EACH ROW
BEGIN
  UPDATE inventario_lotes_smd
  SET total_salida = GREATEST(0, total_salida - NEW.return_qty)
  WHERE codigo_material_recibido = NEW.material_warehousing_code
    AND numero_parte = NEW.part_number
    AND numero_lote = NEW.material_lot_no;
END;`
      }
    ];

    for (const tdef of triggerDefs) {
      console.log('> asegurar trigger:', tdef.name);
      // ejecutar DROP y CREATE por separado (pool no tiene multipleStatements)
      try {
        await conn.query(`DROP TRIGGER IF EXISTS \`${tdef.name}\``);
      } catch (e) {
        // ignore
      }
      const createOnly = tdef.sql.replace(/DROP\s+TRIGGER[\s\S]*?;\s*/i, '');
      await conn.query(createOnly);
      console.log('  ✔ asegurado:', tdef.name);
    }

    // Verificar
    const [rows] = await conn.query(
      "SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME LIKE '%_smd'"
    );

    console.log('\n✅ Triggers `_smd` instalados/encontrados:');
    rows.forEach(r => console.log(` - ${r.TRIGGER_NAME}  on ${r.EVENT_OBJECT_TABLE}  (${r.ACTION_TIMING} ${r.EVENT_MANIPULATION})`));

    console.log('\n🔎 Revisa `backend/sql/test_smd_triggers.sql` y ejecuta las pruebas en staging.');
  } catch (err) {
    console.error('❌ Error al aplicar SQL:', err && err.message ? err.message : err);
    process.exitCode = 2;
  } finally {
    conn.release();
    await pool.end();
  }
})();
