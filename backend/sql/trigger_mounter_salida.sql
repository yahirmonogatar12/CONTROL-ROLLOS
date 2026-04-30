-- ============================================================================
-- Trigger: trg_mounter_ai_smd
-- Tabla origen: historial_cambio_material_smt (escaneo en mounters SMD)
-- Accion: Genera salida automatica en control_material_salida_smd
--         cuando se escanea un barcode que existe en almacen.
--
-- Mapeo de lineas:
--   1line -> LINEA A
--   2line -> LINEA B
--   3line -> LINEA C
--   4line -> LINEA D
--
-- Reglas:
--   1. El Barcode debe existir en control_material_almacen_smd
--   2. El material NO debe estar cancelado (cancelado = 0)
--   3. El material NO debe tener salida previa (tiene_salida = 0)
--   4. El material NO debe estar en desecho (estado_desecho = 0)
--   5. Si ya tiene salida en control_material_salida_smd, se ignora (duplicado)
--   6. La cantidad_salida es la cantidad_actual registrada en almacen
--   7. linea_proceso se asigna segun mapeo de linea de mounter
--
-- Compatibilidad con retornos:
--   - El return.controller.js resetea tiene_salida = 0 al devolver material
--   - Esto permite que si el material se vuelve a escanear en mounter,
--     el trigger genere una nueva salida
--   - El trigger trg_return_ai_smd resta del total_salida en inventario_lotes_smd
--
-- Ruta: backend/sql/trigger_mounter_salida.sql
-- Fecha: 2026-02-06
-- ============================================================================

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

  -- ---------------------------------------------------------------
  -- 1. Mapear linea del mounter a nombre de linea del inventario
  -- ---------------------------------------------------------------
  SET v_linea_nombre = CASE NEW.linea
    WHEN '1line' THEN 'LINEA A'
    WHEN '2line' THEN 'LINEA B'
    WHEN '3line' THEN 'LINEA C'
    WHEN '4line' THEN 'LINEA D'
    ELSE CONCAT('LINEA ', UPPER(LEFT(NEW.linea, 1)))
  END;

  -- ---------------------------------------------------------------
  -- 2. Buscar el barcode en almacen (solo si cumple condiciones)
  --    - No cancelado
  --    - Sin salida previa (tiene_salida = 0)
  --    - No en desecho
  --    La verificacion de tiene_salida = 0 es la proteccion contra
  --    duplicados. Si ya se dio salida, no se vuelve a crear.
  --    El return.controller.js resetea tiene_salida = 0 al devolver,
  --    permitiendo una nueva salida si se re-escanea.
  -- ---------------------------------------------------------------
  SELECT id, numero_parte, numero_lote_material, cantidad_actual, vendedor, especificacion
  INTO v_almacen_id, v_numero_parte, v_numero_lote, v_cantidad_actual, v_vendedor, v_especificacion
  FROM control_material_almacen_smd
  WHERE codigo_material_recibido = NEW.Barcode
    AND (cancelado = 0 OR cancelado IS NULL)
    AND (tiene_salida = 0 OR tiene_salida IS NULL)
    AND (estado_desecho = 0 OR estado_desecho IS NULL)
  LIMIT 1;

  -- ---------------------------------------------------------------
  -- 3. Solo proceder si el barcode existe y cumple condiciones
  -- ---------------------------------------------------------------
  IF v_almacen_id IS NOT NULL THEN

    -- -----------------------------------------------------------
    -- 4. Insertar el registro de salida
    -- -----------------------------------------------------------
    INSERT INTO control_material_salida_smd (
      codigo_material_recibido,
      numero_parte,
      numero_lote,
      depto_salida,
      proceso_salida,
      linea_proceso,
      cantidad_salida,
      fecha_salida,
      fecha_registro,
      especificacion_material,
      usuario_registro,
      vendedor
    ) VALUES (
      NEW.Barcode,
      v_numero_parte,
      v_numero_lote,
      'SMD',
      'Mounter',
      v_linea_nombre,
      v_cantidad_actual,
      CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-06:00'),
      CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-06:00'),
      v_especificacion,
      'SISTEMA_MOUNTER',
      v_vendedor
    );

    -- -----------------------------------------------------------
    -- 5. Marcar el material en almacen como "tiene_salida"
    -- -----------------------------------------------------------
    UPDATE control_material_almacen_smd
    SET tiene_salida = 1
    WHERE id = v_almacen_id;

    -- -----------------------------------------------------------
    -- NOTA: No se necesita actualizar inventario_lotes_smd aqui
    -- porque el trigger existente trg_salida_ai_smd se dispara
    -- automaticamente al insertar en control_material_salida_smd
    -- y se encarga de incrementar total_salida.
    -- -----------------------------------------------------------

  END IF;
  -- Si v_almacen_id es NULL: barcode no existe, ya tiene salida,
  -- esta cancelado o en desecho. No se bloquea la insercion original.

END$$

DELIMITER ;
