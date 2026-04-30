/**
 * UDP Discovery Service
 * Emite beacons UDP para que las apps móviles descubran el servidor automáticamente
 */

const dgram = require('dgram');
const os = require('os');

const DISCOVERY_PORT = 41234; // Puerto UDP para discovery
const BEACON_INTERVAL = 3000; // Emitir beacon cada 3 segundos
const SERVICE_NAME = 'MaterialControl';

/**
 * Obtiene la IP local de la máquina
 */
function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

/**
 * Obtiene la dirección de broadcast de la red local
 */
function getBroadcastAddress() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal && iface.netmask) {
        // Calcular broadcast: IP OR (NOT netmask)
        const ipParts = iface.address.split('.').map(Number);
        const maskParts = iface.netmask.split('.').map(Number);
        const broadcastParts = ipParts.map((ip, i) => ip | (~maskParts[i] & 255));
        return broadcastParts.join('.');
      }
    }
  }
  return '255.255.255.255';
}

/**
 * Inicia el servicio de discovery UDP
 * @param {number} httpPort - Puerto HTTP del servidor API
 * @returns {object} - Objeto con método stop() para detener el servicio
 */
function startDiscoveryService(httpPort) {
  const server = dgram.createSocket('udp4');
  let beaconInterval = null;
  
  const localIP = getLocalIP();
  const broadcastAddr = getBroadcastAddress();
  
  // Mensaje beacon que se envía periódicamente
  const beaconMessage = JSON.stringify({
    service: SERVICE_NAME,
    version: '1.0',
    ip: localIP,
    port: httpPort,
    name: os.hostname(),
    timestamp: Date.now()
  });

  server.on('error', (err) => {
    console.error(`❌ Error UDP Discovery: ${err.message}`);
    server.close();
  });

  server.on('listening', () => {
    const address = server.address();
    console.log(`🔍 UDP Discovery escuchando en puerto ${address.port}`);
    
    // Habilitar broadcast
    server.setBroadcast(true);
    
    // Enviar beacon inicial
    sendBeacon();
    
    // Programar envío periódico de beacons
    beaconInterval = setInterval(sendBeacon, BEACON_INTERVAL);
  });

  // Responder a solicitudes de discovery
  server.on('message', (msg, rinfo) => {
    try {
      const request = JSON.parse(msg.toString());
      
      // Si es una solicitud de discovery, responder directamente
      if (request.type === 'DISCOVER' && request.service === SERVICE_NAME) {
        const response = JSON.stringify({
          type: 'ANNOUNCE',
          service: SERVICE_NAME,
          version: '1.0',
          ip: localIP,
          port: httpPort,
          name: os.hostname(),
          timestamp: Date.now()
        });
        
        server.send(response, rinfo.port, rinfo.address, (err) => {
          if (err) {
            console.error('Error respondiendo discovery:', err);
          } else {
            console.log(`📡 Respondido a discovery desde ${rinfo.address}:${rinfo.port}`);
          }
        });
      }
    } catch (e) {
      // Ignorar mensajes que no son JSON válido
    }
  });

  function sendBeacon() {
    // Actualizar timestamp en cada beacon
    const beacon = JSON.stringify({
      type: 'BEACON',
      service: SERVICE_NAME,
      version: '1.0',
      ip: localIP,
      port: httpPort,
      name: os.hostname(),
      timestamp: Date.now()
    });
    
    server.send(beacon, DISCOVERY_PORT, broadcastAddr, (err) => {
      // Ignorar errores de red no disponible (normal en algunas interfaces)
      if (err && !['ENOENT', 'ENETUNREACH', 'EHOSTUNREACH', 'ENETDOWN'].includes(err.code)) {
        console.error('Error enviando beacon:', err.message);
      }
    });
  }

  // Bind al puerto de discovery
  server.bind(DISCOVERY_PORT);

  return {
    stop: () => {
      if (beaconInterval) {
        clearInterval(beaconInterval);
      }
      server.close();
      console.log('🔍 UDP Discovery detenido');
    },
    getInfo: () => ({
      ip: localIP,
      port: httpPort,
      broadcastAddr,
      discoveryPort: DISCOVERY_PORT
    })
  };
}

module.exports = {
  startDiscoveryService,
  DISCOVERY_PORT,
  SERVICE_NAME
};
