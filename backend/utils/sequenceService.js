/**
 * Servicio para generar secuencias de forma segura sin race conditions
 * Usa bloqueos a nivel de MySQL para garantizar unicidad
 */
const { pool } = require('../config/database');

// Cache local para reducir consultas a la BD
const sequenceCache = new Map();
const CACHE_TTL = 5000; // 5 segundos

/**
 * Obtener siguiente secuencia de etiqueta de forma segura
 * Usa SELECT FOR UPDATE para evitar duplicados
 * @param {string} partNumber - Número de parte
 * @param {string} date - Fecha en formato YYMMDD
 * @returns {Promise<{nextSequence: number, nextCode: string}>}
 */
const getNextLabelSequenceSafe = async (partNumber, date) => {
  const cacheKey = `${partNumber}-${date}`;
  const connection = await pool.getConnection();
  
  try {
    await connection.beginTransaction();
    
    const pattern = `${partNumber}-${date}%`;
    
    // SELECT con FOR UPDATE bloquea los registros que coinciden
    // Esto previene que dos dispositivos obtengan el mismo número
    const [rows] = await connection.query(`
      SELECT codigo_material_recibido 
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido LIKE ?
      ORDER BY codigo_material_recibido DESC 
      LIMIT 1
      FOR UPDATE
    `, [pattern]);

    let nextSequence = 1;

    if (rows.length > 0) {
      const lastCode = rows[0].codigo_material_recibido;
      const sequencePart = lastCode.slice(-4);
      const lastSequence = parseInt(sequencePart, 10);
      if (!isNaN(lastSequence)) {
        nextSequence = lastSequence + 1;
      }
    }

    // Verificar también el cache local por si hay una transacción pendiente
    const cached = sequenceCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
      if (cached.sequence >= nextSequence) {
        nextSequence = cached.sequence + 1;
      }
    }

    // Actualizar cache
    sequenceCache.set(cacheKey, {
      sequence: nextSequence,
      timestamp: Date.now()
    });

    await connection.commit();

    return {
      nextSequence,
      nextCode: `${partNumber}-${date}${nextSequence.toString().padStart(4, '0')}`
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
};

/**
 * Obtener siguiente secuencia de etiqueta SOLO PARA PREVIEW
 * NO actualiza el cache - solo consulta la DB
 * Usar para mostrar el código de preview en el formulario
 * @param {string} partNumber - Número de parte
 * @param {string} date - Fecha en formato YYYYMMDD
 * @returns {Promise<{nextSequence: number, nextCode: string}>}
 */
const getNextLabelSequencePreview = async (partNumber, date) => {
  const connection = await pool.getConnection();
  
  try {
    const pattern = `${partNumber}-${date}%`;
    
    // Solo consulta, sin FOR UPDATE ni cache
    const [rows] = await connection.query(`
      SELECT codigo_material_recibido 
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido LIKE ?
      ORDER BY codigo_material_recibido DESC 
      LIMIT 1
    `, [pattern]);

    let nextSequence = 1;

    if (rows.length > 0) {
      const lastCode = rows[0].codigo_material_recibido;
      const sequencePart = lastCode.slice(-4);
      const lastSequence = parseInt(sequencePart, 10);
      if (!isNaN(lastSequence)) {
        nextSequence = lastSequence + 1;
      }
    }

    // NO actualizamos el cache aquí - es solo preview

    return {
      nextSequence,
      nextCode: `${partNumber}-${date}${nextSequence.toString().padStart(4, '0')}`
    };
  } finally {
    connection.release();
  }
};

/**
 * Obtener siguiente secuencia de lote interno de forma segura
 * Formato: DD/MM/YYYY/XXXXX
 * @returns {Promise<{nextSequence: number, nextLotNumber: string}>}
 */
const getNextInternalLotSequenceSafe = async () => {
  const connection = await pool.getConnection();
  
  try {
    await connection.beginTransaction();
    
    const [rows] = await connection.query(`
      SELECT numero_lote_material 
      FROM control_material_almacen_smd 
      WHERE numero_lote_material REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}/[0-9]{5}$'
      ORDER BY CAST(SUBSTRING_INDEX(numero_lote_material, '/', -1) AS UNSIGNED) DESC 
      LIMIT 1
      FOR UPDATE
    `);

    let nextSequence = 1;

    if (rows.length > 0) {
      const lastLot = rows[0].numero_lote_material;
      const parts = lastLot.split('/');
      if (parts.length === 4) {
        const lastSequence = parseInt(parts[3], 10);
        if (!isNaN(lastSequence)) {
          nextSequence = lastSequence + 1;
        }
      }
    }

    // Generar número de lote con fecha actual
    const now = new Date();
    const dd = String(now.getDate()).padStart(2, '0');
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const yyyy = now.getFullYear();

    await connection.commit();

    return {
      nextSequence,
      nextLotNumber: `${dd}/${mm}/${yyyy}/${nextSequence.toString().padStart(5, '0')}`
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
};

/**
 * Reservar una secuencia para un lote específico
 * Útil cuando vas a imprimir varias etiquetas del mismo lote
 * @param {string} partNumber 
 * @param {string} date 
 * @param {number} count - Cuántas secuencias reservar
 * @returns {Promise<{startSequence: number, endSequence: number, codes: string[]}>}
 */
const reserveLabelSequences = async (partNumber, date, count = 1) => {
  if (count < 1 || count > 100) {
    throw new Error('El número de secuencias a reservar debe ser entre 1 y 100');
  }

  const connection = await pool.getConnection();
  
  try {
    await connection.beginTransaction();
    
    const pattern = `${partNumber}-${date}%`;
    
    const [rows] = await connection.query(`
      SELECT codigo_material_recibido 
      FROM control_material_almacen_smd 
      WHERE codigo_material_recibido LIKE ?
      ORDER BY codigo_material_recibido DESC 
      LIMIT 1
      FOR UPDATE
    `, [pattern]);

    let startSequence = 1;

    if (rows.length > 0) {
      const lastCode = rows[0].codigo_material_recibido;
      const sequencePart = lastCode.slice(-4);
      const lastSequence = parseInt(sequencePart, 10);
      if (!isNaN(lastSequence)) {
        startSequence = lastSequence + 1;
      }
    }

    const cacheKey = `${partNumber}-${date}`;
    const cached = sequenceCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
      if (cached.sequence >= startSequence) {
        startSequence = cached.sequence + 1;
      }
    }

    const endSequence = startSequence + count - 1;
    const codes = [];
    
    for (let seq = startSequence; seq <= endSequence; seq++) {
      codes.push(`${partNumber}-${date}${seq.toString().padStart(4, '0')}`);
    }

    // Actualizar cache con la última secuencia reservada
    sequenceCache.set(cacheKey, {
      sequence: endSequence,
      timestamp: Date.now()
    });

    await connection.commit();

    return {
      startSequence,
      endSequence,
      codes
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
};

/**
 * Versión que usa una conexión existente (para usar dentro de otra transacción)
 * NO hace beginTransaction/commit/rollback - eso lo maneja el llamador
 */
const reserveLabelSequencesWithConnection = async (connection, partNumber, date, count = 1) => {
  if (count < 1 || count > 100) {
    throw new Error('El número de secuencias a reservar debe ser entre 1 y 100');
  }

  const pattern = `${partNumber}-${date}%`;
  
  // Buscar el último código SIN FOR UPDATE para evitar deadlocks
  const [rows] = await connection.query(`
    SELECT codigo_material_recibido 
    FROM control_material_almacen_smd 
    WHERE codigo_material_recibido LIKE ?
    ORDER BY codigo_material_recibido DESC 
    LIMIT 1
  `, [pattern]);

  let startSequence = 1;

  if (rows.length > 0) {
    const lastCode = rows[0].codigo_material_recibido;
    const sequencePart = lastCode.slice(-4);
    const lastSequence = parseInt(sequencePart, 10);
    if (!isNaN(lastSequence)) {
      startSequence = lastSequence + 1;
    }
  }

  const cacheKey = `${partNumber}-${date}`;
  const cached = sequenceCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    if (cached.sequence >= startSequence) {
      startSequence = cached.sequence + 1;
    }
  }

  const endSequence = startSequence + count - 1;
  const codes = [];
  
  for (let seq = startSequence; seq <= endSequence; seq++) {
    codes.push(`${partNumber}-${date}${seq.toString().padStart(4, '0')}`);
  }

  // Actualizar cache con la última secuencia reservada
  sequenceCache.set(cacheKey, {
    sequence: endSequence,
    timestamp: Date.now()
  });

  return {
    startSequence,
    endSequence,
    codes
  };
};

// Limpiar cache viejo cada minuto
setInterval(() => {
  const now = Date.now();
  for (const [key, data] of sequenceCache.entries()) {
    if (now - data.timestamp > 60000) {
      sequenceCache.delete(key);
    }
  }
}, 60000);

module.exports = {
  getNextLabelSequenceSafe,
  getNextLabelSequencePreview,
  getNextInternalLotSequenceSafe,
  reserveLabelSequences,
  reserveLabelSequencesWithConnection
};
