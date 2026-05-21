/**
 * Defect Data Controller - Lookup en tabla externa defect_data
 * Una PCB (codigo) puede tener varias filas (varios defectos LQC/OQC)
 */

const { pool } = require('../config/database');

// ============================================
// GET /api/defect-data/lookup?codigo=XYZ
// Devuelve todas las filas accionables de defect_data para ese codigo
// ============================================
exports.lookup = async (req, res, next) => {
  try {
    const codigo = (req.query.codigo || '').toString().trim();
    if (!codigo) {
      return res.status(400).json({
        success: false,
        message: 'codigo es requerido',
        code: 'MISSING_CODIGO',
        data: [],
        count: 0,
      });
    }

    const [rows] = await pool.query(
      `SELECT id, fecha, linea, codigo, defecto, ubicacion, area, modelo,
              tipo_inspeccion, etapa_deteccion, status, registrado_por
       FROM defect_data
       WHERE codigo = ?
         AND status IN ('Pendiente_Reparacion','En_Reparacion','Rechazado')
       ORDER BY fecha DESC
       LIMIT 10`,
      [codigo]
    );

    return res.json({
      success: true,
      data: rows,
      count: rows.length,
    });
  } catch (err) {
    if (err && err.code === 'ER_NO_SUCH_TABLE') {
      return res.json({
        success: true,
        data: [],
        count: 0,
        warning: 'defect_data table not found',
      });
    }
    next(err);
  }
};
