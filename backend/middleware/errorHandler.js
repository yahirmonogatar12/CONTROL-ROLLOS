/**
 * Middleware centralizado para manejo de errores
 */
const errorHandler = (err, req, res, next) => {
  console.error('❌ Error:', err.message);
  
  // Error de MySQL
  if (err.code) {
    console.error('   SQL Error Code:', err.code);
    console.error('   SQL State:', err.sqlState);
  }

  // Determinar código de estado
  const statusCode = err.statusCode || 500;
  
  res.status(statusCode).json({
    error: err.message || 'Error interno del servidor',
    code: err.code || 'INTERNAL_ERROR'
  });
};

module.exports = errorHandler;
