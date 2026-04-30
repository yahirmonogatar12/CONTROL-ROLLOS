/**
 * Requirements Controller - Requerimientos de Material
 * Módulo para gestionar solicitudes de material por área
 */

const { pool } = require('../config/database');

// Áreas disponibles (constantes)
const AVAILABLE_AREAS = [
    'SMD',
    'Assy',
    'Molding',
    'Pre-Assy',
    'Empaque',
    'Rework',
    'Mantenimiento',
    'Ingeniería',
    'Calidad',
    'Otro'
];

// GET /api/requirements - Listar todos los requerimientos
exports.getAll = async (req, res, next) => {
    try {
        const { area, status, fecha_inicio, fecha_fin, prioridad, pending_only } = req.query;

        let query = `
      SELECT 
        mr.*,
        COUNT(mri.id) as total_items,
        SUM(mri.cantidad_requerida) as total_qty_requerida,
        SUM(mri.cantidad_entregada) as total_qty_entregada
      FROM material_requirements mr
      LEFT JOIN material_requirement_items mri ON mr.id = mri.requirement_id
      WHERE 1=1
    `;
        const params = [];

        if (area) {
            query += ' AND mr.area_destino = ?';
            params.push(area);
        }
        if (status) {
            query += ' AND mr.status = ?';
            params.push(status);
        }
        // Si pending_only=true, excluir Entregado y Cancelado
        if (pending_only === 'true' && !status) {
            query += " AND mr.status NOT IN ('Entregado', 'Cancelado')";
        }
        if (prioridad) {
            query += ' AND mr.prioridad = ?';
            params.push(prioridad);
        }
        if (fecha_inicio) {
            query += ' AND mr.fecha_requerida >= ?';
            params.push(fecha_inicio);
        }
        if (fecha_fin) {
            query += ' AND mr.fecha_requerida <= ?';
            params.push(fecha_fin);
        }

        query += ' GROUP BY mr.id ORDER BY mr.prioridad DESC, mr.fecha_requerida ASC, mr.id DESC';

        const [rows] = await pool.query(query, params);
        res.json(rows);
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/pending-by-area - Pendientes agrupados por área
exports.getPendingByArea = async (req, res, next) => {
    try {
        const [rows] = await pool.query(`
      SELECT 
        area_destino,
        COUNT(*) as total_requirements,
        SUM(CASE WHEN prioridad = 'Crítico' THEN 1 ELSE 0 END) as criticos,
        SUM(CASE WHEN prioridad = 'Urgente' THEN 1 ELSE 0 END) as urgentes
      FROM material_requirements
      WHERE status NOT IN ('Entregado', 'Cancelado')
      GROUP BY area_destino
      ORDER BY criticos DESC, urgentes DESC
    `);
        res.json(rows);
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/count-pending - Contador total de pendientes (para badge)
exports.getCountPending = async (req, res, next) => {
    try {
        const [rows] = await pool.query(`
      SELECT COUNT(*) as count
      FROM material_requirements
      WHERE status NOT IN ('Entregado', 'Cancelado')
    `);
        res.json({ count: rows[0].count });
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/areas - Listar áreas disponibles
exports.getAreas = async (req, res, next) => {
    try {
        res.json(AVAILABLE_AREAS);
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/:id - Obtener requerimiento con items
exports.getById = async (req, res, next) => {
    try {
        const { id } = req.params;

        // Obtener encabezado
        const [requirements] = await pool.query(
            'SELECT * FROM material_requirements WHERE id = ?',
            [id]
        );

        if (requirements.length === 0) {
            return res.status(404).json({ error: 'Requerimiento no encontrado' });
        }

        // Obtener items con especificación y cantidad disponible en inventario
        const [items] = await pool.query(`
      SELECT 
        mri.*, 
        m.especificacion_material, 
        m.ubicacion_material,
        COALESCE(
          (SELECT SUM(cma.cantidad_actual) 
           FROM control_material_almacen_smd cma 
           WHERE cma.numero_parte = mri.numero_parte 
           AND cma.tiene_salida = 0 
           AND cma.cancelado = 0),
          0
        ) as cantidad_disponible,
        (SELECT GROUP_CONCAT(DISTINCT cma2.ubicacion_salida ORDER BY cma2.ubicacion_salida SEPARATOR ', ')
         FROM control_material_almacen_smd cma2 
         WHERE cma2.numero_parte = mri.numero_parte 
         AND cma2.tiene_salida = 0 
         AND cma2.cancelado = 0
         AND cma2.ubicacion_salida IS NOT NULL 
         AND cma2.ubicacion_salida != ''
        ) as ubicaciones_disponibles
      FROM material_requirement_items mri
      LEFT JOIN materiales m ON mri.numero_parte = m.numero_parte
      WHERE mri.requirement_id = ?
      ORDER BY mri.id
    `, [id]);

        res.json({
            ...requirements[0],
            items
        });
    } catch (err) {
        next(err);
    }
};

// POST /api/requirements - Crear nuevo requerimiento
exports.create = async (req, res, next) => {
    try {
        const {
            area_destino,
            modelo,
            fecha_requerida,
            turno,
            prioridad,
            notas,
            creado_por,
            items
        } = req.body;

        if (!area_destino || !fecha_requerida || !creado_por) {
            return res.status(400).json({
                error: 'Campos requeridos: area_destino, fecha_requerida, creado_por'
            });
        }

        // Generar código de requerimiento (REQ-YYYYMMDD-###)
        const codigoRequerimiento = await generateRequirementCode();

        // Crear requerimiento
        const [result] = await pool.query(`
      INSERT INTO material_requirements 
        (codigo_requerimiento, area_destino, modelo, fecha_requerida, turno, prioridad, notas, creado_por)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [
            codigoRequerimiento,
            area_destino,
            modelo || null,
            fecha_requerida,
            turno || null,
            prioridad || 'Normal',
            notas || null,
            creado_por
        ]);

        const requirementId = result.insertId;

        // Agregar items si vienen incluidos
        if (items && Array.isArray(items) && items.length > 0) {
            for (const item of items) {
                await pool.query(`
          INSERT INTO material_requirement_items 
            (requirement_id, numero_parte, descripcion, cantidad_requerida, notas)
          VALUES (?, ?, ?, ?, ?)
        `, [
                    requirementId,
                    item.numero_parte,
                    item.descripcion || null,
                    item.cantidad_requerida || 0,
                    item.notas || null
                ]);
            }
        }

        res.status(201).json({
            success: true,
            id: requirementId,
            codigo_requerimiento: codigoRequerimiento,
            message: 'Requerimiento creado exitosamente'
        });
    } catch (err) {
        next(err);
    }
};

// Helper: Generar código de requerimiento único (REQ-YYYYMMDD-###)
async function generateRequirementCode() {
    const today = new Date();
    const dateStr = today.toISOString().slice(0, 10).replace(/-/g, ''); // YYYYMMDD
    const prefix = `REQ-${dateStr}-`;

    // Buscar el último número del día
    const [rows] = await pool.query(`
      SELECT codigo_requerimiento 
      FROM material_requirements 
      WHERE codigo_requerimiento LIKE ?
      ORDER BY codigo_requerimiento DESC 
      LIMIT 1
    `, [`${prefix}%`]);

    let nextNumber = 1;
    if (rows.length > 0 && rows[0].codigo_requerimiento) {
        const lastCode = rows[0].codigo_requerimiento;
        const lastNumber = parseInt(lastCode.split('-').pop()) || 0;
        nextNumber = lastNumber + 1;
    }

    return `${prefix}${nextNumber.toString().padStart(3, '0')}`;
}

// GET /api/requirements/pending-for-outgoing - Requerimientos pendientes para módulo de salidas
exports.getPendingForOutgoing = async (req, res, next) => {
    try {
        const { area } = req.query;

        let query = `
          SELECT 
            mr.id,
            mr.codigo_requerimiento,
            mr.area_destino,
            mr.fecha_requerida,
            mr.prioridad,
            mr.status,
            mr.creado_por,
            mr.fecha_creacion,
            COUNT(mri.id) as total_items,
            SUM(mri.cantidad_requerida) as total_qty_requerida,
            SUM(mri.cantidad_entregada) as total_qty_entregada
          FROM material_requirements mr
          LEFT JOIN material_requirement_items mri ON mr.id = mri.requirement_id
          WHERE mr.status NOT IN ('Entregado', 'Cancelado')
        `;
        const params = [];

        if (area) {
            query += ' AND mr.area_destino = ?';
            params.push(area);
        }

        query += ' GROUP BY mr.id ORDER BY mr.prioridad DESC, mr.fecha_requerida ASC';

        const [rows] = await pool.query(query, params);
        res.json(rows);
    } catch (err) {
        next(err);
    }
};

// PUT /api/requirements/:id - Actualizar requerimiento
exports.update = async (req, res, next) => {
    try {
        const { id } = req.params;
        const {
            area_destino,
            modelo,
            fecha_requerida,
            turno,
            status,
            prioridad,
            notas,
            actualizado_por
        } = req.body;

        let query = 'UPDATE material_requirements SET ';
        const updates = [];
        const params = [];

        if (area_destino !== undefined) { updates.push('area_destino = ?'); params.push(area_destino); }
        if (modelo !== undefined) { updates.push('modelo = ?'); params.push(modelo); }
        if (fecha_requerida !== undefined) { updates.push('fecha_requerida = ?'); params.push(fecha_requerida); }
        if (turno !== undefined) { updates.push('turno = ?'); params.push(turno); }
        if (status !== undefined) { updates.push('status = ?'); params.push(status); }
        if (prioridad !== undefined) { updates.push('prioridad = ?'); params.push(prioridad); }
        if (notas !== undefined) { updates.push('notas = ?'); params.push(notas); }
        if (actualizado_por) { updates.push('actualizado_por = ?'); params.push(actualizado_por); }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No hay campos para actualizar' });
        }

        query += updates.join(', ') + ' WHERE id = ?';
        params.push(id);

        await pool.query(query, params);

        res.json({ success: true, message: 'Requerimiento actualizado' });
    } catch (err) {
        next(err);
    }
};

// DELETE /api/requirements/:id - Cancelar requerimiento
exports.cancel = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { actualizado_por } = req.body;

        await pool.query(
            `UPDATE material_requirements 
       SET status = 'Cancelado', actualizado_por = ?
       WHERE id = ?`,
            [actualizado_por || null, id]
        );

        res.json({ success: true, message: 'Requerimiento cancelado' });
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/:id/items - Listar items de un requerimiento
exports.getItems = async (req, res, next) => {
    try {
        const { id } = req.params;

        const [items] = await pool.query(`
      SELECT 
        mri.*, 
        m.especificacion_material, 
        m.ubicacion_material,
        COALESCE(
          (SELECT SUM(cma.cantidad_actual) 
           FROM control_material_almacen_smd cma 
           WHERE cma.numero_parte = mri.numero_parte 
           AND cma.tiene_salida = 0 
           AND cma.cancelado = 0),
          0
        ) as cantidad_disponible,
        (SELECT GROUP_CONCAT(DISTINCT cma2.ubicacion_salida ORDER BY cma2.ubicacion_salida SEPARATOR ', ')
         FROM control_material_almacen_smd cma2 
         WHERE cma2.numero_parte = mri.numero_parte 
         AND cma2.tiene_salida = 0 
         AND cma2.cancelado = 0
         AND cma2.ubicacion_salida IS NOT NULL 
         AND cma2.ubicacion_salida != ''
        ) as ubicaciones_disponibles
      FROM material_requirement_items mri
      LEFT JOIN materiales m ON mri.numero_parte = m.numero_parte
      WHERE mri.requirement_id = ?
      ORDER BY mri.id
    `, [id]);

        res.json(items);
    } catch (err) {
        next(err);
    }
};

// POST /api/requirements/:id/items - Agregar items a un requerimiento
exports.addItems = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { items } = req.body;

        if (!items || !Array.isArray(items) || items.length === 0) {
            return res.status(400).json({ error: 'Se requiere un array de items' });
        }

        for (const item of items) {
            await pool.query(`
        INSERT INTO material_requirement_items 
          (requirement_id, numero_parte, descripcion, cantidad_requerida, notas)
        VALUES (?, ?, ?, ?, ?)
      `, [
                id,
                item.numero_parte,
                item.descripcion || null,
                item.cantidad_requerida || 0,
                item.notas || null
            ]);
        }

        // NOTE: Status should NOT change here. It only changes to 'En Preparación' 
        // when outgoing starts (linkOutgoing) - see updateRequirementStatus()

        res.json({ success: true, message: `${items.length} items agregados` });
    } catch (err) {
        next(err);
    }
};

// PUT /api/requirements/:id/items/:itemId - Actualizar item
exports.updateItem = async (req, res, next) => {
    try {
        const { id, itemId } = req.params;
        const {
            cantidad_requerida,
            cantidad_preparada,
            cantidad_entregada,
            status,
            notas
        } = req.body;

        let query = 'UPDATE material_requirement_items SET ';
        const updates = [];
        const params = [];

        if (cantidad_requerida !== undefined) { updates.push('cantidad_requerida = ?'); params.push(cantidad_requerida); }
        if (cantidad_preparada !== undefined) { updates.push('cantidad_preparada = ?'); params.push(cantidad_preparada); }
        if (cantidad_entregada !== undefined) { updates.push('cantidad_entregada = ?'); params.push(cantidad_entregada); }
        if (status !== undefined) { updates.push('status = ?'); params.push(status); }
        if (notas !== undefined) { updates.push('notas = ?'); params.push(notas); }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No hay campos para actualizar' });
        }

        query += updates.join(', ') + ' WHERE id = ? AND requirement_id = ?';
        params.push(itemId, id);

        await pool.query(query, params);

        // Verificar si todos los items están entregados para actualizar status del requerimiento
        await updateRequirementStatus(id);

        res.json({ success: true, message: 'Item actualizado' });
    } catch (err) {
        next(err);
    }
};

// DELETE /api/requirements/:id/items/:itemId - Eliminar item
exports.removeItem = async (req, res, next) => {
    try {
        const { id, itemId } = req.params;

        await pool.query(
            'DELETE FROM material_requirement_items WHERE id = ? AND requirement_id = ?',
            [itemId, id]
        );

        res.json({ success: true, message: 'Item eliminado' });
    } catch (err) {
        next(err);
    }
};

// POST /api/requirements/:id/items/delete-multiple - Eliminar múltiples items
exports.removeMultipleItems = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { itemIds, usuario } = req.body;

        if (!itemIds || !Array.isArray(itemIds) || itemIds.length === 0) {
            return res.status(400).json({ error: 'No se especificaron items para eliminar' });
        }

        // Eliminar los items
        const placeholders = itemIds.map(() => '?').join(',');
        const [result] = await pool.query(
            `DELETE FROM material_requirement_items WHERE id IN (${placeholders}) AND requirement_id = ?`,
            [...itemIds, id]
        );

        res.json({ 
            success: true, 
            message: `${result.affectedRows} items eliminados` 
        });
    } catch (err) {
        next(err);
    }
};

// GET /api/requirements/import-bom/:modelo - Importar items desde BOM
exports.importFromBom = async (req, res, next) => {
    try {
        const { modelo } = req.params;
        const { cantidad } = req.query; // Multiplicador opcional

        const multiplier = parseInt(cantidad) || 1;

        // Buscar BOM del modelo
        const [bomItems] = await pool.query(`
      SELECT 
        bom.part_no as numero_parte,
        m.especificacion_material as descripcion,
        (bom.quantity * ?) as cantidad_requerida
      FROM bom
      LEFT JOIN materiales m ON bom.part_no = m.numero_parte
      WHERE bom.modelo = ?
    `, [multiplier, modelo]);

        if (bomItems.length === 0) {
            return res.status(404).json({ error: 'No se encontró BOM para el modelo' });
        }

        res.json(bomItems);
    } catch (err) {
        next(err);
    }
};

// POST /api/requirements/link-outgoing - Vincular salida a items de requerimiento
exports.linkOutgoing = async (req, res, next) => {
    try {
        const { numero_parte, area_destino, cantidad, codigo_salida } = req.body;

        if (!numero_parte || !area_destino || !cantidad) {
            return res.status(400).json({
                error: 'Se requiere: numero_parte, area_destino, cantidad'
            });
        }

        // Buscar items pendientes que coincidan
        const [items] = await pool.query(`
      SELECT mri.*, mr.id as requirement_id
      FROM material_requirement_items mri
      JOIN material_requirements mr ON mri.requirement_id = mr.id
      WHERE mri.numero_parte = ?
        AND mr.area_destino = ?
        AND mr.status NOT IN ('Entregado', 'Cancelado')
        AND mri.cantidad_entregada < mri.cantidad_requerida
      ORDER BY mr.prioridad DESC, mr.fecha_requerida ASC
      LIMIT 1
    `, [numero_parte, area_destino]);

        if (items.length === 0) {
            return res.json({
                linked: false,
                message: 'No hay requerimientos pendientes para este material y área'
            });
        }

        const item = items[0];
        const newDelivered = Math.min(
            item.cantidad_entregada + cantidad,
            item.cantidad_requerida
        );

        // Actualizar codigos_salida (JSON array)
        let codigosSalida = [];
        try {
            codigosSalida = item.codigos_salida ? JSON.parse(item.codigos_salida) : [];
        } catch (e) {
            codigosSalida = [];
        }
        if (codigo_salida) {
            codigosSalida.push(codigo_salida);
        }

        // Determinar nuevo status del item
        let newStatus = 'Pendiente';
        if (newDelivered >= item.cantidad_requerida) {
            newStatus = 'Entregado';
        } else if (newDelivered > 0) {
            newStatus = 'Parcial';
        }

        // Actualizar item
        await pool.query(`
      UPDATE material_requirement_items 
      SET cantidad_entregada = ?, status = ?, codigos_salida = ?
      WHERE id = ?
    `, [newDelivered, newStatus, JSON.stringify(codigosSalida), item.id]);

        // Actualizar status del requerimiento
        await updateRequirementStatus(item.requirement_id);

        res.json({
            linked: true,
            requirement_id: item.requirement_id,
            item_id: item.id,
            cantidad_entregada: newDelivered,
            message: 'Salida vinculada a requerimiento'
        });
    } catch (err) {
        next(err);
    }
};

// Helper: Actualizar status del requerimiento basado en sus items
async function updateRequirementStatus(requirementId) {
    try {
        const [items] = await pool.query(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Entregado' THEN 1 ELSE 0 END) as entregados,
        SUM(CASE WHEN status IN ('Parcial', 'Preparado') THEN 1 ELSE 0 END) as en_proceso
      FROM material_requirement_items
      WHERE requirement_id = ?
    `, [requirementId]);

        if (items.length === 0) return;

        const { total, entregados, en_proceso } = items[0];

        let newStatus;
        if (entregados >= total && total > 0) {
            newStatus = 'Entregado';
        } else if (entregados > 0 || en_proceso > 0) {
            newStatus = 'En Preparación';
        } else {
            newStatus = 'Pendiente';
        }

        await pool.query(
            `UPDATE material_requirements SET status = ? WHERE id = ? AND status NOT IN ('Cancelado')`,
            [newStatus, requirementId]
        );
    } catch (err) {
        console.error('Error actualizando status de requerimiento:', err.message);
    }
}
