const zlib = require('zlib');

const JSON_CONTENT_TYPE_PATTERN = /\bapplication\/json\b/i;

function gzipJsonBodyParser(req, res, next) {
  const contentEncoding = String(req.headers['content-encoding'] || '').toLowerCase();
  if (!contentEncoding.includes('gzip')) {
    return next();
  }

  const contentType = String(req.headers['content-type'] || '');
  if (!JSON_CONTENT_TYPE_PATTERN.test(contentType)) {
    return res.status(415).json({
      error: 'Solo se soportan cuerpos gzip con Content-Type application/json',
      code: 'UNSUPPORTED_GZIP_CONTENT_TYPE',
    });
  }

  const chunks = [];

  req.on('data', (chunk) => {
    chunks.push(chunk);
  });

  req.on('error', next);

  req.on('end', () => {
    const compressedBody = Buffer.concat(chunks);

    if (compressedBody.length === 0) {
      req.rawBody = '';
      req.body = {};
      req._body = true;
      return next();
    }

    zlib.gunzip(compressedBody, (error, decompressedBuffer) => {
      if (error) {
        return res.status(400).json({
          error: 'No se pudo descomprimir el cuerpo gzip',
          code: 'INVALID_GZIP_BODY',
        });
      }

      try {
        const rawBody = decompressedBuffer.toString('utf8');
        req.rawBody = rawBody;
        req.body = rawBody ? JSON.parse(rawBody) : {};
        req._body = true;
        delete req.headers['content-encoding'];
        req.headers['content-length'] = String(decompressedBuffer.length);
        next();
      } catch (parseError) {
        res.status(400).json({
          error: 'El cuerpo JSON descomprimido no es válido',
          code: 'INVALID_JSON_BODY',
        });
      }
    });
  });
}

module.exports = gzipJsonBodyParser;
