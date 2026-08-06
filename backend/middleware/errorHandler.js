/**
 * Middleware centralizado para manejo de errores
 */
const {
  buildRequestLogContext,
  formatRequestLogContext,
} = require('../utils/requestLogContext');

const errorHandler = (err, req, res, next) => {
  console.error('❌ Error:', err.message);
  console.error(`   ${formatRequestLogContext(buildRequestLogContext(req))}`);
  
  // Error de MySQL
  if (err.code) {
    console.error('   SQL Error Code:', err.code);
    console.error('   SQL State:', err.sqlState);
  }

  const rawMessage = err.message || '';
  const isInsufficientStock = rawMessage.includes('INSUFFICIENT_STOCK_SMD');
  const isNegativeStockAttempt = rawMessage.includes('NEGATIVE_STOCK_NOT_ALLOWED_SMD');
  const isInvalidOutgoingQty = rawMessage.includes('INVALID_OUTGOING_QUANTITY_SMD');

  // Traducir los SIGNAL de MySQL para no exponer mensajes internos al cliente.
  const statusCode = err.statusCode
    || (isInsufficientStock || isNegativeStockAttempt ? 409 : null)
    || (isInvalidOutgoingQty ? 400 : 500);
  const message = isInsufficientStock
    ? 'Stock insuficiente: la salida excede la existencia disponible del lote'
    : isNegativeStockAttempt
      ? 'La operación fue rechazada porque dejaría el lote con stock negativo'
      : isInvalidOutgoingQty
        ? 'La cantidad de salida debe ser mayor o igual a cero'
        : rawMessage || 'Error interno del servidor';
  const code = isInsufficientStock
    ? 'INSUFFICIENT_STOCK'
    : isNegativeStockAttempt
      ? 'NEGATIVE_STOCK_NOT_ALLOWED'
      : isInvalidOutgoingQty
        ? 'INVALID_OUTGOING_QUANTITY'
        : err.code || 'INTERNAL_ERROR';

  res.status(statusCode).json({
    success: false,
    error: message,
    message,
    code
  });
};

module.exports = errorHandler;
