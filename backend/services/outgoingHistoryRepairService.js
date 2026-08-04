const EPSILON = 0.0001;

function numeric(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function summarizeCandidates(candidates) {
  return {
    count: candidates.length,
    totalQuantity: candidates.reduce(
      (total, candidate) => total + numeric(candidate.stock_actual),
      0
    )
  };
}

function assertExpectedScope(summary, { expectedCount, expectedTotal }) {
  if (expectedCount !== undefined && summary.count !== expectedCount) {
    throw new Error(
      `Alcance inesperado: se esperaban ${expectedCount} registros y se encontraron ${summary.count}`
    );
  }

  if (
    expectedTotal !== undefined
    && Math.abs(summary.totalQuantity - expectedTotal) >= EPSILON
  ) {
    throw new Error(
      `Alcance inesperado: se esperaban ${expectedTotal} unidades y se encontraron ${summary.totalQuantity}`
    );
  }
}

async function findRepairCandidates(connection) {
  const [rows] = await connection.query(`
    SELECT
      salida.id AS salida_id,
      salida.codigo_material_recibido,
      almacen.id AS warehousing_id,
      almacen.numero_parte,
      almacen.numero_lote_material,
      inventario.id AS inventory_lot_id,
      inventario.stock_actual
    FROM control_material_salida_smd salida
    INNER JOIN control_material_almacen_smd almacen
      ON almacen.codigo_material_recibido = salida.codigo_material_recibido
    INNER JOIN inventario_lotes_smd inventario
      ON inventario.codigo_material_recibido = salida.codigo_material_recibido
    WHERE salida.cantidad_salida = 0
      AND COALESCE(salida.cancelado, 0) = 0
      AND UPPER(TRIM(COALESCE(salida.comparacion_resultado, ''))) = 'NG'
      AND inventario.stock_actual > 0
      AND salida.id = (
        SELECT salida_cero.id
        FROM control_material_salida_smd salida_cero
        WHERE salida_cero.codigo_material_recibido = salida.codigo_material_recibido
          AND salida_cero.cantidad_salida = 0
          AND COALESCE(salida_cero.cancelado, 0) = 0
          AND UPPER(TRIM(COALESCE(salida_cero.comparacion_resultado, ''))) = 'NG'
        ORDER BY salida_cero.id DESC
        LIMIT 1
      )
      AND NOT EXISTS (
        SELECT 1
        FROM control_material_salida_smd salida_positiva
        WHERE salida_positiva.codigo_material_recibido = salida.codigo_material_recibido
          AND salida_positiva.cantidad_salida > 0
          AND COALESCE(salida_positiva.cancelado, 0) = 0
      )
    ORDER BY salida.id
  `);

  return rows;
}

async function repairCandidate(connection, candidate, actor) {
  const [[warehouse]] = await connection.query(`
    SELECT id, numero_parte, numero_lote_material
    FROM control_material_almacen_smd
    WHERE id = ?
      AND codigo_material_recibido = ?
    FOR UPDATE
  `, [candidate.warehousing_id, candidate.codigo_material_recibido]);

  if (!warehouse) {
    throw new Error('El registro de almacén dejó de estar disponible durante la reparación');
  }

  const [[inventory]] = await connection.query(`
    SELECT id, stock_actual
    FROM inventario_lotes_smd
    WHERE id = ?
      AND codigo_material_recibido = ?
    FOR UPDATE
  `, [candidate.inventory_lot_id, candidate.codigo_material_recibido]);

  const quantity = numeric(inventory?.stock_actual);
  if (!inventory || quantity <= 0) {
    throw new Error('El lote ya no tiene stock disponible para reparar el historial');
  }

  const [[positiveOutgoing]] = await connection.query(`
    SELECT id
    FROM control_material_salida_smd
    WHERE codigo_material_recibido = ?
      AND cantidad_salida > 0
      AND COALESCE(cancelado, 0) = 0
    LIMIT 1
    FOR UPDATE
  `, [candidate.codigo_material_recibido]);

  if (positiveOutgoing) {
    throw new Error('La etiqueta ya tiene una salida positiva; no se reparará el intento NG');
  }

  const [[latestZero]] = await connection.query(`
    SELECT id, fecha_salida
    FROM control_material_salida_smd
    WHERE codigo_material_recibido = ?
      AND cantidad_salida = 0
      AND COALESCE(cancelado, 0) = 0
      AND UPPER(TRIM(COALESCE(comparacion_resultado, ''))) = 'NG'
    ORDER BY id DESC
    LIMIT 1
    FOR UPDATE
  `, [candidate.codigo_material_recibido]);

  if (!latestZero || Number(latestZero.id) !== Number(candidate.salida_id)) {
    throw new Error('El historial cambió durante la reparación; no se modificó la etiqueta');
  }

  const [inventoryUpdate] = await connection.query(`
    UPDATE inventario_lotes_smd
    SET total_salida = total_salida + ?,
        ultima_salida = COALESCE(?, NOW())
    WHERE id = ?
      AND stock_actual >= ?
  `, [quantity, latestZero.fecha_salida, inventory.id, quantity]);

  if (inventoryUpdate.affectedRows !== 1) {
    throw new Error('No fue posible descontar el stock del lote durante la reparación');
  }

  const [historyUpdate] = await connection.query(`
    UPDATE control_material_salida_smd
    SET cantidad_salida = ?
    WHERE id = ?
      AND cantidad_salida = 0
      AND COALESCE(cancelado, 0) = 0
      AND UPPER(TRIM(COALESCE(comparacion_resultado, ''))) = 'NG'
  `, [quantity, candidate.salida_id]);

  if (historyUpdate.affectedRows !== 1) {
    throw new Error('No fue posible actualizar la cantidad del historial');
  }

  await connection.query(`
    UPDATE control_material_almacen_smd
    SET tiene_salida = 1
    WHERE id = ?
  `, [warehouse.id]);

  await connection.query(`
    INSERT INTO inventory_adjustment_smd (
      warehousing_id,
      inventory_lot_id,
      codigo_material_recibido,
      numero_parte,
      numero_lote,
      quantity_before,
      quantity_after,
      adjustment_quantity,
      movement_type,
      reason,
      usuario_registro,
      usuario_registro_id
    ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, 'Exit', ?, ?, NULL)
  `, [
    warehouse.id,
    inventory.id,
    candidate.codigo_material_recibido,
    warehouse.numero_parte,
    warehouse.numero_lote_material,
    quantity,
    quantity,
    `Reparación de salida histórica NG #${candidate.salida_id}`,
    actor
  ]);

  const [[verification]] = await connection.query(`
    SELECT
      inventario.stock_actual,
      salida.cantidad_salida,
      almacen.tiene_salida
    FROM inventario_lotes_smd inventario
    INNER JOIN control_material_salida_smd salida ON salida.id = ?
    INNER JOIN control_material_almacen_smd almacen ON almacen.id = ?
    WHERE inventario.id = ?
    FOR UPDATE
  `, [candidate.salida_id, warehouse.id, inventory.id]);

  if (
    !verification
    || Math.abs(numeric(verification.stock_actual)) >= EPSILON
    || Math.abs(numeric(verification.cantidad_salida) - quantity) >= EPSILON
    || Number(verification.tiene_salida) !== 1
  ) {
    throw new Error('La verificación final de la reparación no coincidió con el resultado esperado');
  }

  return quantity;
}

async function repairZeroNgOutgoingHistory(pool, options = {}) {
  const {
    apply = false,
    actor = 'Sistema - reparación historial',
    expectedCount,
    expectedTotal
  } = options;
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    const candidates = await findRepairCandidates(connection);
    const before = summarizeCandidates(candidates);
    assertExpectedScope(before, { expectedCount, expectedTotal });

    if (!apply) {
      await connection.rollback();
      return { applied: false, before, repaired: { count: 0, totalQuantity: 0 } };
    }

    let repairedTotal = 0;
    for (const candidate of candidates) {
      repairedTotal += await repairCandidate(connection, candidate, actor);
    }

    await connection.commit();
    return {
      applied: true,
      before,
      repaired: { count: candidates.length, totalQuantity: repairedTotal }
    };
  } catch (error) {
    try {
      await connection.rollback();
    } catch (_) {
      // Conservar el error original.
    }
    throw error;
  } finally {
    connection.release();
  }
}

module.exports = {
  assertExpectedScope,
  findRepairCandidates,
  repairZeroNgOutgoingHistory,
  summarizeCandidates
};
