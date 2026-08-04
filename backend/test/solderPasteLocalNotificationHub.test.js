const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { once } = require('events');
const WebSocket = require('ws');

const {
  SIGNAL_TYPE,
  createSolderPasteNotificationHub,
} = require('../services/solderPasteLocalNotificationHub');

test('el backend envía la señal solo a clientes WebSocket conectados', async (t) => {
  const server = http.createServer((_req, res) => res.end('ok'));
  const hub = createSolderPasteNotificationHub();
  hub.attach(server);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');

  const address = server.address();
  const client = new WebSocket(`ws://127.0.0.1:${address.port}/ws/solder-paste`);
  t.after(async () => {
    client.terminate();
    await hub.close();
    await new Promise((resolve) => server.close(resolve));
  });

  const [connectedRaw] = await once(client, 'message');
  const connected = JSON.parse(connectedRaw.toString());
  assert.equal(connected.type, 'connected');
  assert.equal(hub.clientCount(), 1);

  const signalPromise = once(client, 'message');
  assert.equal(hub.signalEventsAvailable(), 1);
  const [signalRaw] = await signalPromise;
  const signal = JSON.parse(signalRaw.toString());
  assert.equal(signal.type, SIGNAL_TYPE);
  assert.ok(signal.timestamp);
});

test('señalar sin móviles conectados no genera trabajo adicional', async () => {
  const hub = createSolderPasteNotificationHub();
  assert.equal(hub.signalEventsAvailable(), 0);
  await hub.close();
});
