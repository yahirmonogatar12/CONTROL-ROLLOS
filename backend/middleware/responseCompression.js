const zlib = require('zlib');

const MIN_COMPRESSIBLE_SIZE = 1024;
const COMPRESSIBLE_CONTENT_TYPE = /json|text|javascript|xml/i;

function responseCompression(req, res, next) {
  const acceptedEncodings = String(req.headers['accept-encoding'] || '').toLowerCase();
  if (!acceptedEncodings.includes('gzip')) {
    return next();
  }

  const originalSend = res.send.bind(res);

  function maybeCompress(body, defaultContentType) {
    if (res.headersSent || res.getHeader('Content-Encoding')) {
      return originalSend(body);
    }

    if (res.statusCode === 204 || res.statusCode === 304 || body === undefined || body === null) {
      return originalSend(body);
    }

    let payload;
    if (Buffer.isBuffer(body)) {
      payload = body;
    } else if (typeof body === 'string') {
      payload = Buffer.from(body);
    } else {
      payload = Buffer.from(JSON.stringify(body));
      if (!res.getHeader('Content-Type') && defaultContentType) {
        res.setHeader('Content-Type', defaultContentType);
      }
    }

    const contentType = String(res.getHeader('Content-Type') || defaultContentType || '');
    if (payload.length < MIN_COMPRESSIBLE_SIZE || !COMPRESSIBLE_CONTENT_TYPE.test(contentType)) {
      return originalSend(body);
    }

    const compressedPayload = zlib.gzipSync(payload);
    res.setHeader('Content-Encoding', 'gzip');
    res.setHeader('Vary', 'Accept-Encoding');
    res.removeHeader('Content-Length');
    return originalSend(compressedPayload);
  }

  res.json = (body) => {
    if (!res.getHeader('Content-Type')) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
    }
    return maybeCompress(JSON.stringify(body), 'application/json; charset=utf-8');
  };

  res.send = (body) => {
    return maybeCompress(body, typeof body === 'string' ? 'text/plain; charset=utf-8' : '');
  };

  next();
}

module.exports = responseCompression;
