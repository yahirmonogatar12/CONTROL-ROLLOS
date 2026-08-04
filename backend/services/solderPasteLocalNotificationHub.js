'use strict';

const { WebSocket, WebSocketServer } = require('ws');

const SOCKET_PATH = '/ws/solder-paste';
const SIGNAL_TYPE = 'solder_paste_events_available';

function createSolderPasteNotificationHub({ socketPath = SOCKET_PATH } = {}) {
  let httpServer = null;
  let websocketServer = null;
  let heartbeatTimer = null;
  let upgradeHandler = null;

  function attach(server) {
    if (httpServer === server && websocketServer) return websocketServer;
    if (httpServer) throw new Error('El hub WebSocket de Control de pasta ya está conectado');

    httpServer = server;
    websocketServer = new WebSocketServer({ noServer: true });

    upgradeHandler = (request, socket, head) => {
      let pathname;
      try {
        pathname = new URL(request.url, 'http://localhost').pathname;
      } catch (_) {
        socket.destroy();
        return;
      }
      if (pathname !== socketPath) return;

      websocketServer.handleUpgrade(request, socket, head, (client) => {
        websocketServer.emit('connection', client, request);
      });
    };
    server.on('upgrade', upgradeHandler);

    websocketServer.on('connection', (client) => {
      client.isAlive = true;
      client.on('pong', () => { client.isAlive = true; });
      client.send(JSON.stringify({
        type: 'connected',
        channel: 'solder_paste_process',
      }));
    });

    heartbeatTimer = setInterval(() => {
      for (const client of websocketServer.clients) {
        if (client.isAlive === false) {
          client.terminate();
          continue;
        }
        client.isAlive = false;
        client.ping();
      }
    }, 30000);
    heartbeatTimer.unref?.();

    return websocketServer;
  }

  function signalEventsAvailable() {
    if (!websocketServer) return 0;
    const message = JSON.stringify({
      type: SIGNAL_TYPE,
      timestamp: new Date().toISOString(),
    });
    let delivered = 0;
    for (const client of websocketServer.clients) {
      if (client.readyState !== WebSocket.OPEN) continue;
      try {
        client.send(message);
        delivered += 1;
      } catch (_) {
        // Una desconexión simultánea no debe afectar el proceso de pasta.
      }
    }
    return delivered;
  }

  async function close() {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = null;
    if (httpServer && upgradeHandler) httpServer.off('upgrade', upgradeHandler);
    httpServer = null;
    upgradeHandler = null;

    const currentServer = websocketServer;
    websocketServer = null;
    if (!currentServer) return;
    for (const client of currentServer.clients) client.terminate();
    await new Promise((resolve) => currentServer.close(resolve));
  }

  function clientCount() {
    return websocketServer?.clients.size || 0;
  }

  return {
    attach,
    clientCount,
    close,
    signalEventsAvailable,
  };
}

const defaultHub = createSolderPasteNotificationHub();

module.exports = {
  SIGNAL_TYPE,
  SOCKET_PATH,
  attachSolderPasteNotificationHub: defaultHub.attach,
  createSolderPasteNotificationHub,
  signalSolderPasteEventsAvailable: defaultHub.signalEventsAvailable,
};
