/**
 * Part Number Helpers
 * Utilidades para manejo de números de parte con versión
 */

/**
 * Extrae el número de parte base, removiendo sufijos de versión
 * Soporta formatos:
 * - Letra al final: EAX66932502-A → EAX66932502
 * - Número con punto: EAX66932502-1.1 → EAX66932502
 * - Múltiples letras: EAX66932502-AB → EAX66932502
 * 
 * @param {string} partNumber - Número de parte completo (puede incluir versión)
 * @returns {string} - Número de parte base sin versión
 */
function getBasePartNumber(partNumber) {
  if (!partNumber) return partNumber;
  
  // Regex para detectar sufijos de versión comunes:
  // -A, -B, -AB, -1.1, -2.0, etc.
  // El patrón busca: guión + (letras mayúsculas O números con punto) al final
  const versionPattern = /-([A-Z]+|\d+\.\d+)$/i;
  
  return partNumber.replace(versionPattern, '');
}

/**
 * Busca configuración de material primero por part number exacto,
 * luego por part number base si no encuentra
 * 
 * @param {object} pool - Pool de conexión MySQL
 * @param {string} partNumber - Número de parte (puede incluir versión)
 * @param {string} selectFields - Campos a seleccionar (default: *)
 * @returns {Promise<object|null>} - Configuración del material o null
 */
async function findMaterialConfig(pool, partNumber, selectFields = '*') {
  const basePartNumber = getBasePartNumber(partNumber);
  
  // Buscar exacto primero, luego base
  const [rows] = await pool.query(
    `SELECT ${selectFields} FROM materiales 
     WHERE numero_parte = ? OR numero_parte = ?
     ORDER BY CASE WHEN numero_parte = ? THEN 0 ELSE 1 END
     LIMIT 1`,
    [partNumber, basePartNumber, partNumber]
  );
  
  return rows.length > 0 ? rows[0] : null;
}

module.exports = {
  getBasePartNumber,
  findMaterialConfig
};
