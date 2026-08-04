'use strict';

const NOTIFIABLE_EVENTS = Object.freeze([
  'AMBIENT_READY',
  'AGITATION_COMPLETED',
  'ASSIGNED_TO_LINE',
  'CONSUMED',
  'RETURNED_TO_COLD',
  'CANCELLED',
  'READY_FOR_AGITATION_EXPIRED',
  'LINE_LIFE_EXPIRED',
]);

const EVENT_TITLES = Object.freeze({
  AMBIENT_READY: 'Pasta lista para agitación',
  AGITATION_COMPLETED: 'Agitación terminada',
  ASSIGNED_TO_LINE: 'Pasta asignada a línea',
  CONSUMED: 'Proceso de pasta terminado',
  RETURNED_TO_COLD: 'Pasta regresada al refrigerador',
  CANCELLED: 'Proceso de pasta cancelado',
  READY_FOR_AGITATION_EXPIRED: 'Tiempo para agitación vencido',
  LINE_LIFE_EXPIRED: 'Tiempo de pasta en línea vencido',
});

function normalizeLimit(value) {
  return Math.min(Math.max(Number(value) || 100, 1), 500);
}

function normalizeCursor(value) {
  return Math.max(Number.parseInt(String(value || '0'), 10) || 0, 0);
}

function lineLabel(lineCode) {
  const normalized = String(lineCode || '').trim().toUpperCase();
  const labels = { SA: 'SMT A', SB: 'SMT B', SC: 'SMT C', SD: 'SMT D', SE: 'SMT E' };
  return labels[normalized] || normalized;
}

function buildNotification(row) {
  const eventType = String(row.event_type || '').trim().toUpperCase();
  const materialCode = String(row.codigo_material_recibido || '').trim();
  const partNumber = String(row.numero_parte || '').trim();
  const material = materialCode || partNumber || `Proceso ${row.process_id}`;
  const line = lineLabel(row.line_code);

  let body;
  switch (eventType) {
    case 'AMBIENT_READY':
      body = `${material} terminó su tiempo a temperatura ambiente`;
      break;
    case 'AGITATION_COMPLETED':
      body = `${material} está lista para asignar a línea`;
      break;
    case 'ASSIGNED_TO_LINE':
      body = `${material} inició su proceso${line ? ` en ${line}` : ' en línea'}`;
      break;
    case 'CONSUMED':
      body = `${material} terminó su proceso`;
      break;
    case 'RETURNED_TO_COLD':
      body = `${material} regresó a refrigeración y reinició su proceso`;
      break;
    case 'CANCELLED':
      body = `${material} fue cancelada`;
      break;
    case 'READY_FOR_AGITATION_EXPIRED':
      body = `${material} excedió el tiempo permitido antes de agitación`;
      break;
    case 'LINE_LIFE_EXPIRED':
      body = `${material} excedió su tiempo permitido${line ? ` en ${line}` : ' en línea'}`;
      break;
    default:
      body = `${material} cambió de etapa`;
  }

  return {
    id: Number(row.id),
    processId: Number(row.process_id),
    eventType,
    title: EVENT_TITLES[eventType] || 'Control de pasta',
    body,
    materialCode,
    partNumber,
    lineCode: String(row.line_code || ''),
    createdAt: row.created_at,
  };
}

async function getLocalNotificationFeed(pool, { afterId, limit = 100 } = {}) {
  const [[maxRow]] = await pool.query(
    'SELECT COALESCE(MAX(id), 0) AS max_id FROM solder_paste_event_smd',
  );
  const currentMax = normalizeCursor(maxRow?.max_id);
  const hasCursor = afterId !== undefined && afterId !== null && String(afterId).trim() !== '';

  // La primera consulta solo establece el cursor para evitar avisar todo el historial.
  if (!hasCursor) {
    return { cursor: currentMax, events: [], hasMore: false, initialized: true };
  }

  const cursor = normalizeCursor(afterId);
  if (cursor >= currentMax) {
    return { cursor: currentMax, events: [], hasMore: false, initialized: true };
  }

  const safeLimit = normalizeLimit(limit);
  const placeholders = NOTIFIABLE_EVENTS.map(() => '?').join(', ');
  const [rows] = await pool.query(`
    SELECT e.id, e.process_id, e.event_type, e.created_at,
           p.codigo_material_recibido, p.numero_parte, p.line_code
    FROM solder_paste_event_smd e
    INNER JOIN solder_paste_process_smd p ON p.id = e.process_id
    WHERE e.id > ?
      AND e.id <= ?
      AND e.event_type IN (${placeholders})
    ORDER BY e.id ASC
    LIMIT ?
  `, [cursor, currentMax, ...NOTIFIABLE_EVENTS, safeLimit]);

  const hasMore = rows.length === safeLimit;
  const nextCursor = hasMore ? Number(rows[rows.length - 1].id) : currentMax;
  return {
    cursor: nextCursor,
    events: rows.map(buildNotification),
    hasMore,
    initialized: true,
  };
}

module.exports = {
  EVENT_TITLES,
  NOTIFIABLE_EVENTS,
  buildNotification,
  getLocalNotificationFeed,
  normalizeCursor,
  normalizeLimit,
};
