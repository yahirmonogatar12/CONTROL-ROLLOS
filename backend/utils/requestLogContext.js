'use strict';

const MAX_LOG_VALUE_LENGTH = 240;

function cleanLogValue(value) {
  if (value === null || value === undefined) return null;
  const normalized = String(value).replace(/[\r\n\t]+/g, ' ').trim();
  if (!normalized) return null;
  return normalized.slice(0, MAX_LOG_VALUE_LENGTH);
}

function firstValue(sources, keys) {
  for (const source of sources) {
    if (!source || typeof source !== 'object') continue;
    for (const key of keys) {
      const value = cleanLogValue(source[key]);
      if (value) return value;
    }
  }
  return null;
}

function normalizeClientIp(req = {}) {
  const forwarded = cleanLogValue(req.headers?.['x-forwarded-for']);
  const rawIp = forwarded?.split(',')[0]?.trim()
    || cleanLogValue(req.ip)
    || cleanLogValue(req.socket?.remoteAddress)
    || 'desconocida';
  return rawIp.replace(/^::ffff:/, '');
}

function buildRequestLogContext(req = {}) {
  const sources = [req.body, req.query, req.params];
  const clientVersion = firstValue([req.headers, req.body], [
    'x-app-version',
    'x-client-version',
    'app_version',
    'client_version',
  ]);
  return {
    method: cleanLogValue(req.method) || 'UNKNOWN',
    path: cleanLogValue(req.originalUrl?.split('?')[0] || req.path) || '/',
    ip: normalizeClientIp(req),
    scannedCode: firstValue(sources, [
      'code',
      'warehousing_code',
      'codigo_material_recibido',
      'material_warehousing_code',
      'codigo_escaneado',
      'scanned_code',
      'barcode',
      'qr_code',
      'label_code',
      'etiqueta',
    ]),
    partNumber: firstValue(sources, ['numero_parte', 'part_number']),
    location: firstValue(sources, [
      'location',
      'ubicacion',
      'ubicacion_destino',
      'ubicacion_salida',
    ]),
    user: firstValue(sources, [
      'usuario',
      'username',
      'returned_by',
      'scanned_by',
      'usuario_registro',
    ]),
    clientVersion,
  };
}

function formatRequestLogContext(context, { includePrefix = true } = {}) {
  const fields = [
    `${context.method} ${context.path}`,
    `IP=${context.ip}`,
  ];
  if (context.scannedCode) fields.push(`código=${context.scannedCode}`);
  if (context.partNumber) fields.push(`parte=${context.partNumber}`);
  if (context.location) fields.push(`ubicación=${context.location}`);
  if (context.user) fields.push(`usuario=${context.user}`);
  fields.push(`versión=${context.clientVersion || 'sin-reportar'}`);
  const detail = fields.join(' | ');
  return includePrefix ? `📋 Solicitud: ${detail}` : detail;
}

module.exports = {
  buildRequestLogContext,
  cleanLogValue,
  formatRequestLogContext,
  normalizeClientIp,
};
