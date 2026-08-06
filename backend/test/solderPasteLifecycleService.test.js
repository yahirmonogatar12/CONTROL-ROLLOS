'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { pool } = require('../config/database');
const service = require('../services/solderPasteLifecycleService');

test('cada estado de pasta devuelve el siguiente paso operativo acordado', () => {
  const expected = new Map([
    [null, 'Retirar del refrigerador e iniciar acondicionamiento desde Proceso y seguimiento'],
    [service.STATUS.TEMPERING, 'Esperar el tiempo restante a temperatura ambiente'],
    [service.STATUS.READY_FOR_AGITATION, 'Agitar antes de 8 h o regresar al refrigerador'],
    [service.STATUS.AGITATING, 'Esperar a que termine el temporizador de 60 segundos'],
    [service.STATUS.READY_FOR_LINE, 'Seleccionar SMT A, B, C, D o E'],
    [service.STATUS.IN_LINE, 'Utilizar antes del vencimiento, marcar Material consumido o retornar al almacén'],
    [service.STATUS.CONSUMED, 'Proceso terminado; no se requiere otra acción'],
    [service.STATUS.SCRAP, 'Depositar en scrap; si nunca llegó a línea, un usuario autorizado puede retornarlo'],
    [service.STATUS.CANCELLED, 'Proceso cancelado; puede iniciarse nuevamente si corresponde'],
    [service.STATUS.RETURNED_TO_COLD, 'Material regresado al refrigerador; puede iniciar otro ciclo respetando FIFO'],
  ]);

  for (const [status, message] of expected) {
    assert.equal(service.nextActionForStatus(status), message);
  }
});

test('la consulta sin proceso es de solo lectura y distingue material disponible', async (t) => {
  const originalQuery = pool.query;
  const calls = [];
  pool.query = async (sql, params) => {
    calls.push({ sql, params });
    if (calls.length === 1) return [[]];
    return [[{
      codigo_material_recibido: '49111007000-202607060055',
      numero_parte: '49111007000',
      cancelado: 0,
      estado_desecho: 0,
      tiene_salida: 0,
      en_cuarentena: 0,
      stock_actual: 1,
    }]];
  };
  t.after(() => { pool.query = originalQuery; });

  const result = await service.getStatusByCode(' 49111007000-202607060055 ');

  assert.equal(result.inventory_status, 'AVAILABLE');
  assert.equal(result.process, null);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].params, ['49111007000-202607060055']);
  assert.match(calls[1].sql, /FROM control_material_almacen cma/i);
  assert.doesNotMatch(calls[1].sql, /control_material_almacen_smd/i);
  for (const call of calls) {
    assert.match(call.sql.trim(), /^SELECT/i);
    assert.doesNotMatch(call.sql, /\b(?:INSERT|UPDATE|DELETE)\b/i);
  }
});

test('el primer escaneo genera la salida en el inventario general de almacén', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  const processRow = {
    id: 44,
    warehousing_id: 81,
    inventory_lot_id: null,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    codigo_material_recibido: '49111007000-202607060055',
    numero_parte: '49111007000',
    numero_lote: 'LOT-1',
    issued_quantity: 1,
    unit: 'EA',
    inventory_outgoing_id: 333,
    cycle_no: 1,
    status: service.STATUS.TEMPERING,
    effective_status: service.STATUS.TEMPERING,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM control_material_almacen cma/i.test(sql)) {
        return [[{
          id: 81,
          codigo_material_recibido: processRow.codigo_material_recibido,
          numero_parte: processRow.numero_parte,
          numero_lote_material: processRow.numero_lote,
          codigo_material: processRow.numero_parte,
          fecha_recibo: '2026-07-06 08:00:00',
          cantidad_actual: 1,
          unidad_medida: 'EA',
          especificacion: 'Bote',
          vendedor: 'Proveedor',
          cancelado: 0,
          estado_desecho: 0,
          tiene_salida: 0,
          en_cuarentena: 0,
        }]];
      }
      if (/DATE\(fecha_recibo\) < DATE\(\?\)/i.test(sql)) return [[]];
      if (/FROM control_material_almacen\s+WHERE/i.test(sql)) {
        return [[{
          id: 81,
          codigo_material_recibido: processRow.codigo_material_recibido,
          fecha_recibo: '2026-07-06 08:00:00',
          cantidad_actual: 1,
        }]];
      }
      if (/SELECT \* FROM solder_paste_process_smd/i.test(sql)) return [[]];
      if (/FROM blacklisted_lots/i.test(sql)) return [[]];
      if (/INSERT INTO control_material_salida\s/i.test(sql)) return [{ insertId: 333 }];
      if (/UPDATE control_material_almacen\s/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_process_smd/i.test(sql)) return [{ insertId: 44 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 1 }];
      if (/FROM solder_paste_process_smd sp/i.test(sql)) return [[processRow]];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.scanMaterial({
    code: processRow.codigo_material_recibido,
    usuario: 'tester',
    usuarioId: 7,
  });

  assert.equal(result.inventory_source, service.INVENTORY_SOURCE.WAREHOUSE);
  const inventoryQuery = queries.find((call) => /FROM control_material_almacen cma/i.test(call.sql));
  assert.ok(inventoryQuery);
  assert.doesNotMatch(inventoryQuery.sql, /control_material_almacen_smd/i);
  const insert = queries.find((call) => /INSERT INTO solder_paste_process_smd/i.test(call.sql));
  assert.match(insert.sql, /inventory_source/i);
  assert.ok(insert.params.includes(service.INVENTORY_SOURCE.WAREHOUSE));
  assert.ok(insert.params.includes(333));
  assert.match(insert.sql, /DATE_ADD\(NOW\(\), INTERVAL 10 HOUR\)/i);
  const outgoing = queries.find((call) => /INSERT INTO control_material_salida\s/i.test(call.sql));
  assert.ok(outgoing);
  assert.match(outgoing.sql, /'PASTA_SOLDADURA'/);
  assert.match(outgoing.sql, /linea_proceso/i);
  assert.match(outgoing.sql, /VALUES \(\?, \?, \?, NULL, NULL,/i);
  assert.equal(outgoing.params[3], 1);
  assert.ok(
    queries.findIndex((call) => call === outgoing)
      < queries.findIndex((call) => call === insert),
  );
});

test('asignar línea reutiliza la salida creada en el primer escaneo', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const readyProcess = {
    id: 52,
    warehousing_id: 91,
    inventory_lot_id: null,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    codigo_material_recibido: 'PASTA-ALMACEN-1',
    numero_parte: 'NP-PASTA',
    numero_lote: 'LOTE-PASTA',
    issued_quantity: 3,
    unit: 'EA',
    inventory_outgoing_id: 333,
    status: service.STATUS.READY_FOR_LINE,
    effective_status: service.STATUS.READY_FOR_LINE,
    agitation_due: 0,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? readyProcess
          : { ...readyProcess, status: service.STATUS.IN_LINE, effective_status: service.STATUS.IN_LINE, line_code: 'SMT E' }]];
      }
      if (/FROM control_material_salida/i.test(sql)) {
        return [[{ id: 333, cantidad_salida: 3, cancelado: 0 }]];
      }
      if (/UPDATE control_material_salida/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 2 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.assignLine({ processId: 52, line: 'SMT E', usuario: 'tester' });

  assert.equal(result.status, service.STATUS.IN_LINE);
  const outgoingUpdate = queries.find((call) => /UPDATE control_material_salida/i.test(call.sql));
  assert.ok(outgoingUpdate);
  assert.match(outgoingUpdate.sql, /SET linea_proceso = \?/i);
  assert.doesNotMatch(outgoingUpdate.sql, /SET modelo = \?/i);
  assert.deepEqual(outgoingUpdate.params, ['SMT E', 333]);
  const processUpdate = queries.find(
    (call) => /UPDATE solder_paste_process_smd/i.test(call.sql),
  );
  assert.ok(processUpdate);
  assert.doesNotMatch(processUpdate.sql, /expires_at/i);
  assert.equal(queries.some((call) => /INSERT INTO control_material_salida/i.test(call.sql)), false);
  assert.equal(queries.some((call) => /FROM control_material_almacen/i.test(call.sql)), false);
});

test('las 12 horas comienzan al terminar la agitación y no al seleccionar línea', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const readyProcess = {
    id: 53,
    status: service.STATUS.READY_FOR_AGITATION,
    effective_status: service.STATUS.READY_FOR_AGITATION,
    ready_for_agitation_due: 0,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? readyProcess
          : {
              ...readyProcess,
              status: service.STATUS.AGITATING,
              effective_status: service.STATUS.AGITATING,
              agitation_remaining_seconds: 60,
              line_remaining_seconds: 43260,
            }]];
      }
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 3 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.startAgitation({
    processId: readyProcess.id,
    usuario: 'tester',
  });

  assert.equal(result.status, service.STATUS.AGITATING);
  const update = queries.find(
    (call) => /UPDATE solder_paste_process_smd/i.test(call.sql),
  );
  assert.ok(update);
  assert.match(
    update.sql,
    /expires_at\s*=\s*DATE_ADD\(\s*DATE_ADD\(NOW\(\), INTERVAL 60 SECOND\),\s*INTERVAL 12 HOUR\s*\)/i,
  );
});

test('cancelar antes de línea conserva historial y libera la salida de almacén', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const process = {
    id: 61,
    warehousing_id: 101,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    inventory_outgoing_id: 444,
    codigo_material_recibido: 'PASTA-CANCEL-1',
    status: service.STATUS.TEMPERING,
    effective_status: service.STATUS.TEMPERING,
    ambient_due: 0,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? process
          : { ...process, status: service.STATUS.CANCELLED, effective_status: service.STATUS.CANCELLED }]];
      }
      if (/UPDATE control_material_salida/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE control_material_almacen cma/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 4 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.cancel({ processId: 61, usuario: 'tester' });

  assert.equal(result.status, service.STATUS.CANCELLED);
  const cancelOutgoing = queries.find((call) => /UPDATE control_material_salida/i.test(call.sql));
  assert.deepEqual(cancelOutgoing.params, [444, 'PASTA-CANCEL-1']);
  const releaseWarehouse = queries.find((call) => /SET cma\.tiene_salida = 0/i.test(call.sql));
  assert.ok(releaseWarehouse);
  assert.match(releaseWarehouse.sql, /cms\.cantidad_salida > 0/i);
});

test('FIFO impide retirar una pasta si existe una etiqueta anterior disponible', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM control_material_almacen cma/i.test(sql)) {
        return [[{
          id: 82,
          codigo_material_recibido: 'PASTA-NUEVA',
          numero_parte: 'NP-PASTA',
          codigo_material: 'MAT-PASTA',
          fecha_recibo: '2026-08-02 08:00:00',
          cantidad_actual: 1,
          unidad_medida: 'BOTE',
          cancelado: 0,
          estado_desecho: 0,
          tiene_salida: 0,
          en_cuarentena: 0,
        }]];
      }
      if (/SELECT \* FROM solder_paste_process_smd/i.test(sql)) return [[]];
      if (/FROM control_material_almacen\s+WHERE/i.test(sql)) {
        return [[{
          id: 80,
          codigo_material_recibido: 'PASTA-ANTERIOR',
          fecha_recibo: '2026-08-01 08:00:00',
          cantidad_actual: 1,
        }]];
      }
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  await assert.rejects(
    service.scanMaterial({ code: 'PASTA-NUEVA', usuario: 'tester' }),
    (error) => error.code === 'FIFO_VIOLATION'
      && /PASTA-ANTERIOR/.test(error.message),
  );
  assert.equal(
    queries.some((call) => /INSERT INTO control_material_salida/i.test(call.sql)),
    false,
  );
  const fifoQuery = queries.find(
    (call) => /DATE\(fecha_recibo\) < DATE\(\?\)/i.test(call.sql),
  );
  assert.ok(fifoQuery);
  assert.deepEqual(fifoQuery.params, ['MAT-PASTA', '2026-08-02 08:00:00']);
  assert.match(fifoQuery.sql, /WHERE codigo_material = \?/i);
  assert.doesNotMatch(fifoQuery.sql, /fecha_recibo ASC/i);
});

test('FIFO permite cualquier etiqueta del mismo material recibida el mismo día', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  const processRow = {
    id: 65,
    warehousing_id: 84,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    codigo_material_recibido: 'PASTA-MISMO-DIA-TARDE',
    numero_parte: 'NP-MISMO-DIA',
    numero_lote: null,
    issued_quantity: 1,
    unit: 'BOTE',
    inventory_outgoing_id: 448,
    cycle_no: 1,
    status: service.STATUS.TEMPERING,
    effective_status: service.STATUS.TEMPERING,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM control_material_almacen cma/i.test(sql)) {
        return [[{
          id: 84,
          codigo_material_recibido: processRow.codigo_material_recibido,
          numero_parte: processRow.numero_parte,
          numero_lote_material: null,
          codigo_material: 'MAT-MISMO-DIA',
          fecha_recibo: '2026-08-02 17:45:00',
          cantidad_actual: 1,
          unidad_medida: 'BOTE',
          especificacion: 'Pasta',
          vendedor: 'Proveedor',
          cancelado: 0,
          estado_desecho: 0,
          tiene_salida: 0,
          en_cuarentena: 0,
        }]];
      }
      if (/SELECT \* FROM solder_paste_process_smd/i.test(sql)) return [[]];
      if (/DATE\(fecha_recibo\) < DATE\(\?\)/i.test(sql)) return [[]];
      if (/INSERT INTO control_material_salida/i.test(sql)) return [{ insertId: 448 }];
      if (/UPDATE control_material_almacen/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_process_smd/i.test(sql)) return [{ insertId: 65 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 1 }];
      if (/FROM solder_paste_process_smd sp/i.test(sql)) return [[processRow]];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.scanMaterial({
    code: processRow.codigo_material_recibido,
    usuario: 'tester',
  });

  assert.equal(result.status, service.STATUS.TEMPERING);
  const fifoQuery = queries.find(
    (call) => /DATE\(fecha_recibo\) < DATE\(\?\)/i.test(call.sql),
  );
  assert.deepEqual(fifoQuery.params, [
    'MAT-MISMO-DIA',
    '2026-08-02 17:45:00',
  ]);
  assert.ok(queries.some((call) => /INSERT INTO control_material_salida/i.test(call.sql)));
});

test('FIFO desactivado permite retirar una etiqueta disponible fuera de orden', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  const processRow = {
    id: 63,
    warehousing_id: 82,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    codigo_material_recibido: 'PASTA-NUEVA',
    numero_parte: 'NP-PASTA',
    numero_lote: 'LOT-NUEVO',
    issued_quantity: 1,
    unit: 'BOTE',
    inventory_outgoing_id: 446,
    cycle_no: 1,
    status: service.STATUS.TEMPERING,
    effective_status: service.STATUS.TEMPERING,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM control_material_almacen cma/i.test(sql)) {
        return [[{
          id: 82,
          codigo_material_recibido: processRow.codigo_material_recibido,
          numero_parte: processRow.numero_parte,
          numero_lote_material: processRow.numero_lote,
          codigo_material: 'MAT-PASTA',
          fecha_recibo: '2026-08-02 08:00:00',
          cantidad_actual: 1,
          unidad_medida: 'BOTE',
          especificacion: 'Bote',
          vendedor: 'Proveedor',
          cancelado: 0,
          estado_desecho: 0,
          tiene_salida: 0,
          en_cuarentena: 0,
        }]];
      }
      if (/SELECT \* FROM solder_paste_process_smd/i.test(sql)) return [[]];
      if (/FROM blacklisted_lots/i.test(sql)) return [[]];
      if (/INSERT INTO control_material_salida\s/i.test(sql)) return [{ insertId: 446 }];
      if (/UPDATE control_material_almacen\s/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_process_smd/i.test(sql)) return [{ insertId: 63 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 6 }];
      if (/FROM solder_paste_process_smd sp/i.test(sql)) return [[processRow]];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.scanMaterial({
    code: processRow.codigo_material_recibido,
    usuario: 'tester',
    enforceFifo: false,
  });

  assert.equal(result.status, service.STATUS.TEMPERING);
  assert.equal(
    queries.some((call) => /DATE\(fecha_recibo\) < DATE\(\?\)/i.test(call.sql)),
    false,
  );
  assert.ok(queries.some((call) => /INSERT INTO control_material_salida/i.test(call.sql)));
});

test('regresar al refrigerador registra el retorno de Almacén y permite un ciclo futuro', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const process = {
    id: 62,
    warehousing_id: 102,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    inventory_outgoing_id: 445,
    codigo_material_recibido: 'PASTA-RETORNO-1',
    numero_parte: 'NP-RETORNO-1',
    numero_lote: 'LOTE-RETORNO-1',
    issued_quantity: 2,
    status: service.STATUS.READY_FOR_AGITATION,
    effective_status: service.STATUS.READY_FOR_AGITATION,
    ready_for_agitation_due: 0,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? process
          : {
              ...process,
              status: service.STATUS.RETURNED_TO_COLD,
              effective_status: service.STATUS.RETURNED_TO_COLD,
            }]];
      }
      if (/FROM control_material_almacen/i.test(sql)) {
        return [[{
          id: 102,
          numero_parte: process.numero_parte,
          numero_lote_material: process.numero_lote,
          codigo_material_recibido: process.codigo_material_recibido,
          cantidad_actual: 2,
          tiene_salida: 1,
        }]];
      }
      if (/FROM control_material_salida/i.test(sql)) {
        return [[{ id: 445, cantidad_salida: 2 }]];
      }
      if (/INSERT INTO material_return/i.test(sql)) return [{ insertId: 801 }];
      if (/UPDATE control_material_salida/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE control_material_almacen/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 5 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.returnToCold({ processId: 62, usuario: 'tester' });

  assert.equal(result.status, service.STATUS.RETURNED_TO_COLD);
  const materialReturn = queries.find((call) => /INSERT INTO material_return/i.test(call.sql));
  assert.deepEqual(materialReturn.params, [
    102,
    process.codigo_material_recibido,
    process.numero_parte,
    process.numero_lote,
    2,
    'Retorno de pasta de soldadura al refrigerador de Almacén',
    'tester',
  ]);
  const outgoingUpdate = queries.find((call) => /UPDATE control_material_salida/i.test(call.sql));
  assert.deepEqual(outgoingUpdate.params, [0, 445]);
  const warehouseUpdate = queries.find((call) => /UPDATE control_material_almacen/i.test(call.sql));
  assert.deepEqual(warehouseUpdate.params, [2, 102]);
  assert.equal(queries.some((call) => /SET cancelado = 1/i.test(call.sql)), false);
  const event = queries.find((call) => /INSERT INTO solder_paste_event_smd/i.test(call.sql));
  assert.ok(event.params.includes('RETURNED_TO_COLD'));
  assert.match(
    event.params.find((param) => typeof param === 'string' && param.includes('material_return_id')),
    /"material_return_id":801/,
  );
});

test('retornar desde línea libera la salida de almacén y permite iniciar otro ciclo', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const process = {
    id: 64,
    warehousing_id: 104,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    inventory_outgoing_id: 447,
    codigo_material_recibido: 'PASTA-RETORNO-LINEA',
    numero_parte: 'NP-RETORNO-LINEA',
    numero_lote: 'LOTE-RETORNO-LINEA',
    issued_quantity: 3,
    line_code: 'SMT B',
    status: service.STATUS.IN_LINE,
    effective_status: service.STATUS.IN_LINE,
    line_due: 0,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? process
          : {
              ...process,
              status: service.STATUS.RETURNED_TO_COLD,
              effective_status: service.STATUS.RETURNED_TO_COLD,
            }]];
      }
      if (/FROM control_material_almacen/i.test(sql)) {
        return [[{
          id: 104,
          numero_parte: process.numero_parte,
          numero_lote_material: process.numero_lote,
          codigo_material_recibido: process.codigo_material_recibido,
          cantidad_actual: 3,
          tiene_salida: 1,
        }]];
      }
      if (/FROM control_material_salida/i.test(sql)) {
        return [[{ id: 447, cantidad_salida: 3 }]];
      }
      if (/INSERT INTO material_return/i.test(sql)) return [{ insertId: 802 }];
      if (/UPDATE control_material_salida/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE control_material_almacen/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 7 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.returnToCold({ processId: 64, usuario: 'tester' });

  assert.equal(result.status, service.STATUS.RETURNED_TO_COLD);
  const materialReturn = queries.find((call) => /INSERT INTO material_return/i.test(call.sql));
  assert.ok(materialReturn);
  assert.deepEqual(materialReturn.params.slice(0, 5), [
    104,
    process.codigo_material_recibido,
    process.numero_parte,
    process.numero_lote,
    3,
  ]);
  assert.match(materialReturn.params[5], /SMT B/);
  const outgoingUpdate = queries.find((call) => /UPDATE control_material_salida/i.test(call.sql));
  assert.deepEqual(outgoingUpdate.params, [0, 447]);
  const warehouseUpdate = queries.find((call) => /UPDATE control_material_almacen/i.test(call.sql));
  assert.deepEqual(warehouseUpdate.params, [3, 104]);
  assert.equal(queries.some((call) => /SET cancelado = 1/i.test(call.sql)), false);
  const processUpdate = queries.find((call) => /UPDATE solder_paste_process_smd/i.test(call.sql));
  assert.equal(processUpdate.params.at(-1), service.STATUS.IN_LINE);
  const event = queries.find((call) => /INSERT INTO solder_paste_event_smd/i.test(call.sql));
  assert.ok(event.params.includes(service.STATUS.IN_LINE));
  const metadata = event.params.find(
    (param) => typeof param === 'string' && param.includes('WAREHOUSE_COLD_STORAGE'),
  );
  assert.match(metadata, /"warehouse_return_created":true/);
  assert.match(metadata, /"material_return_id":802/);
  assert.match(metadata, /"returned_from_line":true/);
});

test('permite retornar desde cualquier etapa activa recuperable', async (t) => {
  const originalGetConnection = pool.getConnection;
  let currentStatus = service.STATUS.TEMPERING;
  let processReads = 0;
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql) => {
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[{
          id: 80 + processReads,
          inventory_source: service.INVENTORY_SOURCE.SMD_LEGACY,
          codigo_material_recibido: `PASTA-${currentStatus}`,
          status: processReads % 2 === 1
            ? currentStatus
            : service.STATUS.RETURNED_TO_COLD,
          effective_status: processReads % 2 === 1
            ? currentStatus
            : service.STATUS.RETURNED_TO_COLD,
          ambient_due: 0,
          ready_for_agitation_due: 0,
          agitation_due: 0,
        }]];
      }
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 1 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  for (const status of [
    service.STATUS.TEMPERING,
    service.STATUS.AGITATING,
    service.STATUS.READY_FOR_LINE,
  ]) {
    currentStatus = status;
    processReads = 0;
    const result = await service.returnToCold({
      processId: 80,
      usuario: 'tester',
    });
    assert.equal(result.status, service.STATUS.RETURNED_TO_COLD, status);
  }
});

test('un usuario autorizado puede recuperar scrap que nunca llegó a línea', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  const process = {
    id: 90,
    warehousing_id: 190,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    inventory_outgoing_id: 290,
    codigo_material_recibido: 'PASTA-SCRAP-SIN-ABRIR',
    numero_parte: 'NP-SCRAP',
    numero_lote: 'LOTE-SCRAP',
    issued_quantity: 1,
    status: service.STATUS.SCRAP,
    effective_status: service.STATUS.SCRAP,
    scrap_record_id: 390,
    line_code: null,
    line_started_at: null,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? process
          : {
              ...process,
              status: service.STATUS.RETURNED_TO_COLD,
              effective_status: service.STATUS.RETURNED_TO_COLD,
              scrap_record_id: null,
              scrapped_at: null,
            }]];
      }
      if (/FROM usuarios_sistema/i.test(sql)) {
        return [[{
          id: 77,
          username: 'supervisor',
          nombre_completo: 'Supervisor SMT',
          departamento: 'SMT',
        }]];
      }
      if (/FROM user_permissions_materiales/i.test(sql)) return [[{ id: 1 }]];
      if (/FROM control_material_almacen/i.test(sql)) {
        return [[{
          id: 190,
          numero_parte: process.numero_parte,
          numero_lote_material: process.numero_lote,
          codigo_material_recibido: process.codigo_material_recibido,
          cantidad_actual: 1,
          tiene_salida: 1,
        }]];
      }
      if (/FROM control_material_salida/i.test(sql)) {
        return [[{ id: 290, cantidad_salida: 1 }]];
      }
      if (/INSERT INTO material_return/i.test(sql)) return [{ insertId: 490 }];
      if (/UPDATE control_material_salida/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE control_material_almacen/i.test(sql)) return [{ affectedRows: 1 }];
      if (/DELETE FROM scrap_records/i.test(sql)) return [{ affectedRows: 1 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 1 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.returnToCold({
    processId: process.id,
    usuario: 'supervisor',
    usuarioId: 77,
  });

  assert.equal(result.status, service.STATUS.RETURNED_TO_COLD);
  const permission = queries.find((call) => /FROM user_permissions_materiales/i.test(call.sql));
  assert.deepEqual(permission.params, [77, service.SCRAP_RETURN_PERMISSION]);
  assert.deepEqual(
    queries.find((call) => /DELETE FROM scrap_records/i.test(call.sql)).params,
    [390],
  );
  const event = queries.find((call) => /INSERT INTO solder_paste_event_smd/i.test(call.sql));
  const metadata = event.params.find(
    (param) => typeof param === 'string' && param.includes('scrap_return_authorized'),
  );
  assert.match(metadata, /"scrap_return_authorized":true/);
  assert.match(metadata, /"authorized_by_user_id":77/);
  assert.match(metadata, /"reversed_scrap_record_id":390/);
  assert.match(metadata, /"restart_on_next_scan":true/);
});

test('rechaza recuperar scrap sin permiso o después de llegar a línea', async (t) => {
  const originalGetConnection = pool.getConnection;
  let process = {
    id: 91,
    inventory_source: service.INVENTORY_SOURCE.WAREHOUSE,
    codigo_material_recibido: 'PASTA-SCRAP-BLOQUEADA',
    status: service.STATUS.SCRAP,
    effective_status: service.STATUS.SCRAP,
    line_code: null,
    line_started_at: null,
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql) => {
      if (/FROM solder_paste_process_smd sp/i.test(sql)) return [[process]];
      if (/FROM usuarios_sistema/i.test(sql)) {
        return [[{ id: 78, username: 'operador', departamento: 'SMT' }]];
      }
      if (/FROM user_permissions_materiales/i.test(sql)) return [[]];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  await assert.rejects(
    service.returnToCold({ processId: 91, usuario: 'operador', usuarioId: 78 }),
    (error) => error.code === 'SCRAP_RETURN_PERMISSION_REQUIRED'
      && error.statusCode === 403,
  );

  process = {
    ...process,
    line_code: 'SMT A',
    line_started_at: '2026-08-04 10:00:00',
  };
  await assert.rejects(
    service.returnToCold({ processId: 91, usuario: 'supervisor', usuarioId: 77 }),
    (error) => error.code === 'OPENED_SCRAP_RETURN_FORBIDDEN',
  );
});

test('el siguiente escaneo de un retorno crea automáticamente un ciclo nuevo', async (t) => {
  const originalGetConnection = pool.getConnection;
  const queries = [];
  const code = 'PASTA-CICLO-NUEVO';
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM control_material_almacen cma/i.test(sql)) {
        return [[{
          id: 200,
          codigo_material_recibido: code,
          numero_parte: 'NP-CICLO',
          numero_lote_material: null,
          codigo_material: 'NP-CICLO',
          fecha_recibo: '2026-08-04 08:00:00',
          cantidad_actual: 1,
          unidad_medida: 'BOTE',
          especificacion: 'Pasta',
          vendedor: 'Proveedor',
          cancelado: 0,
          estado_desecho: 0,
          tiene_salida: 0,
          en_cuarentena: 0,
        }]];
      }
      if (/SELECT \* FROM solder_paste_process_smd/i.test(sql)) {
        return [[{
          id: 99,
          codigo_material_recibido: code,
          cycle_no: 3,
          status: service.STATUS.RETURNED_TO_COLD,
        }]];
      }
      if (/INSERT INTO control_material_salida/i.test(sql)) return [{ insertId: 500 }];
      if (/UPDATE control_material_almacen/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_process_smd/i.test(sql)) return [{ insertId: 100 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 1 }];
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        return [[{
          id: 100,
          codigo_material_recibido: code,
          cycle_no: 4,
          status: service.STATUS.TEMPERING,
          effective_status: service.STATUS.TEMPERING,
        }]];
      }
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => { pool.getConnection = originalGetConnection; });

  const result = await service.scanMaterial({
    code,
    usuario: 'tester',
    usuarioId: 7,
    enforceFifo: false,
  });

  assert.equal(result.cycle_no, 4);
  assert.equal(result.status, service.STATUS.TEMPERING);
  const insert = queries.find((call) => /INSERT INTO solder_paste_process_smd/i.test(call.sql));
  assert.equal(insert.params[5], 4);
  assert.equal(insert.params[6], service.STATUS.TEMPERING);
});

test('al vencer 8 horas listo para agitación genera scrap automático', async (t) => {
  const originalQuery = pool.query;
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  pool.query = async (sql) => {
    queries.push({ sql, params: [] });
    return [[{ id: 72 }]];
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? {
              id: 72,
              codigo_material_recibido: 'PASTA-VENCIDA-8H',
              numero_parte: 'NP-PASTA',
              issued_quantity: 1,
              unit: 'BOTE',
              status: service.STATUS.READY_FOR_AGITATION,
              effective_status: service.STATUS.SCRAP,
              ready_for_agitation_due: 1,
            }
          : {
              id: 72,
              codigo_material_recibido: 'PASTA-VENCIDA-8H',
              status: service.STATUS.SCRAP,
              effective_status: service.STATUS.SCRAP,
            }]];
      }
      if (/INSERT IGNORE INTO scrap_motivos/i.test(sql)) return [{ affectedRows: 0 }];
      if (/SELECT id FROM scrap_motivos/i.test(sql)) return [[{ id: 18 }]];
      if (/INSERT INTO scrap_records/i.test(sql)) return [{ insertId: 901 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 6 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => {
    pool.query = originalQuery;
    pool.getConnection = originalGetConnection;
  });

  const reconciled = await service.reconcileAll();

  assert.equal(reconciled, 1);
  const scrap = queries.find((call) => /INSERT INTO scrap_records/i.test(call.sql));
  assert.ok(scrap);
  assert.ok(scrap.params.includes(service.READY_FOR_AGITATION_SCRAP_REASON));
  const event = queries.find((call) => /INSERT INTO solder_paste_event_smd/i.test(call.sql));
  assert.ok(event.params.includes('READY_FOR_AGITATION_EXPIRED'));
});

test('al vencer 12 horas sin seleccionar línea genera scrap automático', async (t) => {
  const originalQuery = pool.query;
  const originalGetConnection = pool.getConnection;
  const queries = [];
  let processReads = 0;
  pool.query = async (sql) => {
    queries.push({ sql, params: [] });
    return [[{ id: 73 }]];
  };
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (/FROM solder_paste_process_smd sp/i.test(sql)) {
        processReads += 1;
        return [[processReads === 1
          ? {
              id: 73,
              codigo_material_recibido: 'PASTA-SIN-LINEA-12H',
              numero_parte: 'NP-PASTA',
              issued_quantity: 1,
              unit: 'BOTE',
              status: service.STATUS.READY_FOR_LINE,
              effective_status: service.STATUS.SCRAP,
              line_due: 1,
              line_code: null,
            }
          : {
              id: 73,
              codigo_material_recibido: 'PASTA-SIN-LINEA-12H',
              status: service.STATUS.SCRAP,
              effective_status: service.STATUS.SCRAP,
            }]];
      }
      if (/INSERT IGNORE INTO scrap_motivos/i.test(sql)) return [{ affectedRows: 0 }];
      if (/SELECT id FROM scrap_motivos/i.test(sql)) return [[{ id: 19 }]];
      if (/INSERT INTO scrap_records/i.test(sql)) return [{ insertId: 902 }];
      if (/UPDATE solder_paste_process_smd/i.test(sql)) return [{ affectedRows: 1 }];
      if (/INSERT INTO solder_paste_event_smd/i.test(sql)) return [{ insertId: 7 }];
      throw new Error(`Consulta no simulada: ${sql}`);
    },
  };
  pool.getConnection = async () => connection;
  t.after(() => {
    pool.query = originalQuery;
    pool.getConnection = originalGetConnection;
  });

  const reconciled = await service.reconcileAll();

  assert.equal(reconciled, 1);
  const scrap = queries.find((call) => /INSERT INTO scrap_records/i.test(call.sql));
  assert.ok(scrap);
  assert.ok(scrap.params.includes(service.SCRAP_REASON));
  assert.ok(scrap.params.some((param) => String(param).includes('Sin asignar')));
  const event = queries.find((call) => /INSERT INTO solder_paste_event_smd/i.test(call.sql));
  assert.ok(event.params.includes('LINE_LIFE_EXPIRED'));
  assert.ok(event.params.some(
    (param) => typeof param === 'string' && param.includes('"stage":"READY_FOR_LINE"'),
  ));
});

test('la consulta distingue etiqueta inexistente', async (t) => {
  const originalQuery = pool.query;
  let queryCount = 0;
  pool.query = async () => {
    queryCount += 1;
    return [[]];
  };
  t.after(() => { pool.query = originalQuery; });

  const result = await service.getStatusByCode('NO-EXISTE');

  assert.equal(result.found, false);
  assert.equal(result.inventory_status, 'NOT_FOUND');
  assert.equal(queryCount, 2);
});

test('solo acepta las cinco líneas SMT permitidas', async () => {
  for (const line of ['SMT X', 'SMT', '', null]) {
    await assert.rejects(
      service.assignLine({ processId: 1, line, usuario: 'tester' }),
      (error) => error.code === 'INVALID_LINE' && error.statusCode === 400,
    );
  }
  assert.deepEqual(
    [...service.ALLOWED_LINES],
    ['SMT A', 'SMT B', 'SMT C', 'SMT D', 'SMT E'],
  );
});

test('salida, ajuste y devolución detectan etiquetas controladas por pasta', async () => {
  const executor = {
    query: async () => [[{
      id: 9,
      status: service.STATUS.IN_LINE,
      codigo_material_recibido: 'ETIQUETA-1',
    }]],
  };

  await assert.rejects(
    service.assertNotReserved(executor, 'ETIQUETA-1'),
    (error) => error.code === 'SOLDER_PASTE_RESERVED',
  );
  await assert.rejects(
    service.assertReturnAllowed(executor, 'ETIQUETA-1'),
    (error) => error.code === 'SOLDER_PASTE_RETURN_FORBIDDEN',
  );

  executor.query = async () => [[{
    id: 10,
    status: service.STATUS.TEMPERING,
    codigo_material_recibido: 'ETIQUETA-2',
  }]];
  await assert.rejects(
    service.assertReturnAllowed(executor, 'ETIQUETA-2'),
    (error) => error.code === 'SOLDER_PASTE_RESERVED',
  );
});
