-- SQL idempotente para crear tablas `_smd` y sus triggers asociados
-- Ruta: backend/sql/apply_smd_triggers.sql
-- Recomendación: ejecutar en STAGING primero. HACER BACKUP antes de aplicar.

-- 1) Crear tablas fork (copian estructura + índices)
CREATE TABLE IF NOT EXISTS control_material_salida_smd LIKE control_material_salida;
CREATE TABLE IF NOT EXISTS inventario_lotes_smd LIKE inventario_lotes;
CREATE TABLE IF NOT EXISTS material_return_smd LIKE material_return;

-- 2) Triggers: control_material_almacen_smd (ENTRY) - INSERT
DROP TRIGGER IF EXISTS trg_almacen_ai_smd;
DELIMITER $$
CREATE TRIGGER trg_almacen_ai_smd
AFTER INSERT ON control_material_almacen_smd
FOR EACH ROW
BEGIN
  -- `cancelado` no existe en la tabla _smd: validar solo IQC
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
END$$
DELIMITER ;

-- 3) Triggers: control_material_almacen_smd (ENTRY) - UPDATE
DROP TRIGGER IF EXISTS trg_almacen_au_smd;
DELIMITER $$
CREATE TRIGGER trg_almacen_au_smd
AFTER UPDATE ON control_material_almacen_smd
FOR EACH ROW
BEGIN
  DECLARE diff DECIMAL(12,2);
  DECLARE antes_se_contaba TINYINT(1);
  DECLARE ahora_se_cuenta  TINYINT(1);

  -- Cancelacion: si cancelado cambia de 0 a 1, restar total_entrada
  IF (OLD.cancelado = 0 OR OLD.cancelado IS NULL) AND NEW.cancelado = 1 THEN
    UPDATE inventario_lotes_smd
    SET total_entrada = GREATEST(0, total_entrada - OLD.cantidad_actual)
    WHERE codigo_material_recibido = OLD.codigo_material_recibido
      AND numero_parte = OLD.numero_parte
      AND numero_lote = OLD.numero_lote_material;
  ELSE
    -- Solo procesar cambios de IQC/cantidad si NO esta cancelado
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
END$$
DELIMITER ;

-- 4) Trigger: control_material_salida_smd (EXIT) - INSERT
DROP TRIGGER IF EXISTS trg_salida_ai_smd;
DELIMITER $$
CREATE TRIGGER trg_salida_ai_smd
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
  ultima_salida = GREATEST(ultima_salida, NEW.fecha_salida);
$$
DELIMITER ;

-- 5) Trigger: material_return_smd (RETURN) - INSERT (adaptado a columnas _smd)
DROP TRIGGER IF EXISTS trg_return_ai_smd;
DELIMITER $$
CREATE TRIGGER trg_return_ai_smd
AFTER INSERT ON material_return_smd
FOR EACH ROW
BEGIN
  -- ajustar total_salida en inventario_lotes_smd cuando hay devolución
  UPDATE inventario_lotes_smd
  SET total_salida = GREATEST(0, total_salida - NEW.return_qty)
  WHERE codigo_material_recibido = NEW.material_warehousing_code
    AND numero_parte = NEW.part_number
    AND numero_lote = NEW.material_lot_no;
END$$
DELIMITER ;

-- 6) Trigger: historial_cambio_material_smt (MOUNTER SCAN) - INSERT
--    Genera salida automatica cuando se escanea un barcode en mounter
--    que existe en almacen con tiene_salida=0, cancelado=0, estado_desecho=0
--    Mapeo: 1line->LINEA A, 2line->LINEA B, 3line->LINEA C, 4line->LINEA D
--    Compatible con retornos: return.controller resetea tiene_salida=0
DROP TRIGGER IF EXISTS trg_mounter_ai_smd;
DELIMITER $$
CREATE TRIGGER trg_mounter_ai_smd
AFTER INSERT ON historial_cambio_material_smt
FOR EACH ROW
BEGIN
  DECLARE v_almacen_id INT DEFAULT NULL;
  DECLARE v_numero_parte TEXT;
  DECLARE v_numero_lote TEXT;
  DECLARE v_cantidad_actual INT;
  DECLARE v_vendedor VARCHAR(100);
  DECLARE v_especificacion TEXT;
  DECLARE v_linea_nombre VARCHAR(20);

  SET v_linea_nombre = CASE NEW.linea
    WHEN '1line' THEN 'LINEA A'
    WHEN '2line' THEN 'LINEA B'
    WHEN '3line' THEN 'LINEA C'
    WHEN '4line' THEN 'LINEA D'
    ELSE CONCAT('LINEA ', UPPER(LEFT(NEW.linea, 1)))
  END;

  SELECT id, numero_parte, numero_lote_material, cantidad_actual, vendedor, especificacion
  INTO v_almacen_id, v_numero_parte, v_numero_lote, v_cantidad_actual, v_vendedor, v_especificacion
  FROM control_material_almacen_smd
  WHERE codigo_material_recibido = NEW.Barcode
    AND (cancelado = 0 OR cancelado IS NULL)
    AND (tiene_salida = 0 OR tiene_salida IS NULL)
    AND (estado_desecho = 0 OR estado_desecho IS NULL)
  LIMIT 1;

  IF v_almacen_id IS NOT NULL THEN
    INSERT INTO control_material_salida_smd (
      codigo_material_recibido, numero_parte, numero_lote,
      depto_salida, proceso_salida, linea_proceso,
      cantidad_salida, fecha_salida, fecha_registro,
      especificacion_material, usuario_registro, vendedor
    ) VALUES (
      NEW.Barcode, v_numero_parte, v_numero_lote,
      'SMD', 'Mounter', v_linea_nombre,
      v_cantidad_actual, NOW(), NOW(),
      v_especificacion, 'SISTEMA_MOUNTER', v_vendedor
    );

    UPDATE control_material_almacen_smd
    SET tiene_salida = 1
    WHERE id = v_almacen_id;
  END IF;
END$$
DELIMITER ;

-- 7) Backfill opcional (DESCOMENTAR si quieres copiar datos existentes a las tablas _smd)
-- INSERT INTO inventario_lotes_smd SELECT * FROM inventario_lotes;
-- INSERT INTO control_material_salida_smd SELECT * FROM control_material_salida;

-- 8) Verificaciones rápidas
SELECT 'tables' AS what, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (
   'control_material_salida_smd','inventario_lotes_smd','material_return_smd'
 );

SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION
 FROM INFORMATION_SCHEMA.TRIGGERS
 WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME LIKE 'trg\_%\_smd';

-- FIN
