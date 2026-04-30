/**
 * Customers Controller - Catálogo de Clientes
 */

const { pool } = require('../config/database');

// GET /api/customers - Lista clientes únicos
exports.getAll = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT DISTINCT cliente as name 
      FROM control_material_almacen_smd 
      WHERE cliente IS NOT NULL AND cliente != ''
      ORDER BY cliente
    `);
    res.json(rows);
  } catch (err) {
    next(err);
  }
};
