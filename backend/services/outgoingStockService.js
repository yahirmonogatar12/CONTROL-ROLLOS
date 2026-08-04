'use strict';

function stockError(message, code, statusCode) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

function resolveOutgoingQuantity({
  availableQty,
  requestedQty,
  useAvailableStock = false
}) {
  const available = Number(availableQty);
  if (!Number.isFinite(available) || available <= 0) {
    throw stockError(
      'El lote no tiene stock disponible para salida',
      'NO_AVAILABLE_STOCK',
      400
    );
  }

  const isMissingQuantity = requestedQty === null
    || requestedQty === undefined
    || (typeof requestedQty === 'string' && requestedQty.trim() === '');
  const outgoingQty = useAvailableStock ? available : Number(requestedQty);

  if ((!useAvailableStock && isMissingQuantity)
      || !Number.isFinite(outgoingQty)
      || outgoingQty <= 0) {
    throw stockError(
      'La cantidad de salida debe ser un número mayor a cero',
      'INVALID_OUTGOING_QUANTITY',
      400
    );
  }

  if (outgoingQty > available) {
    throw stockError(
      `Stock insuficiente. Disponible: ${available}; solicitado: ${outgoingQty}`,
      'INSUFFICIENT_STOCK',
      409
    );
  }

  return outgoingQty;
}

module.exports = { resolveOutgoingQuantity };
