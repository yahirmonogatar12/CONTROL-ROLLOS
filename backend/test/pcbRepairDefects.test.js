'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeDefectsPayload, summarizeDefects, buildPreviousRepairData } =
  require('../controllers/pcb-inventory.controller')._test;

test('mantiene compatibilidad con una entrada de un solo defecto', () => {
  const defects = normalizeDefectsPayload({
    repairArea: true,
    defectType: ' soldadura fria ',
    componentLocation: ' r12 ',
    etapaDeteccion: 'ais',
    defectSourceArea: null,
    defectDataId: null,
  });

  assert.deepStrictEqual(defects, [{
    sort_order: 1,
    defect_type: 'SOLDADURA FRIA',
    component_location: 'R12',
    etapa_deteccion: 'AIS',
    defect_source_area: null,
    defect_data_id: null,
  }]);
});

test('normaliza varios defectos sin acumularlos fuera de su entrada', () => {
  const defects = normalizeDefectsPayload({
    repairArea: true,
    defects: [
      {
        defect_type: 'corto',
        component_location: 'u1',
        etapa_deteccion: 'lqc',
        defect_data_id: '100',
      },
      {
        defect_type: 'componente faltante',
        component_location: 'c4',
        etapa_deteccion: 'ais',
      },
    ],
  });

  assert.equal(defects.length, 2);
  assert.equal(defects[0].sort_order, 1);
  assert.equal(defects[0].defect_type, 'CORTO');
  assert.equal(defects[1].sort_order, 2);
  assert.equal(defects[1].component_location, 'C4');
  assert.equal(summarizeDefects(defects), 'CORTO, COMPONENTE FALTANTE');
});

test('ignora defectos para una entrada que no es de reparacion', () => {
  const defects = normalizeDefectsPayload({
    repairArea: false,
    defects: [{ defect_type: 'CORTO' }],
  });

  assert.deepStrictEqual(defects, []);
});

test('el aviso de retorno contiene solo los defectos del ultimo ciclo reparado', () => {
  const data = buildPreviousRepairData({
    entry_scan_id: 20,
    exit_scan_id: 21,
    scanned_original: 'PCB-1',
    pcb_part_no: 'EBR12345678',
    modelo: 'MODELO A',
    repair_area: 'REPARACION',
    repaired_at: '2026-08-24 10:30:00',
  }, [
    { sort_order: 1, defect_type: 'CORTO', component_location: 'C4' },
    { sort_order: 2, defect_type: 'SOLDADURA FRIA', component_location: 'R8' },
  ]);

  assert.equal(data.entry_scan_id, 20);
  assert.equal(data.exit_scan_id, 21);
  assert.deepStrictEqual(
    data.defects.map(defect => defect.defect_type),
    ['CORTO', 'SOLDADURA FRIA']
  );
});

test('parsea QR con ; y barcode continuo EBR', () => {
  const { parseScannedCode } = require('../controllers/pcb-inventory.controller')._test;
  assert.equal(parseScannedCode('A1;smd;ebr12345678;X9').pcb_part_no, 'EBR12345678');
  assert.equal(parseScannedCode('A1;SMD;EBR12345678;X9').assy_type, 'SMD');
  const bc = parseScannedCode('ebr86093798922509201401');
  assert.equal(bc.pcb_part_no, 'EBR86093798');
  assert.equal(bc.token3, '922509201401');
  assert.equal(parseScannedCode('EBR86093798;').pcb_part_no, 'EBR86093798');
  assert.equal(parseScannedCode('XYZ123').pcb_part_no, null);
});

test('arma historial PCB con ciclos de reparacion y defectos', () => {
  const { buildPcbHistory } = require('../controllers/pcb-inventory.controller')._test;
  const history = buildPcbHistory([
    { id: 1, tipo_movimiento: 'ENTRADA', area: 'REPARACION', pcb_part_no: 'EBR87145141', modelo: 'M1', created_at: '2026-09-01 08:00:00' },
    { id: 2, tipo_movimiento: 'SALIDA', area: 'REPARACION', source_entry_id: 1, defect_type: 'CORTO', pcb_part_no: 'EBR87145141', modelo: 'M1', created_at: '2026-09-01 09:00:00' },
    { id: 3, tipo_movimiento: 'ENTRADA', area: 'INVENTARIO', defect_type: 'LEGACY', pcb_part_no: 'EBR87145141', modelo: 'M1', created_at: '2026-09-02 08:00:00' },
    { id: 4, tipo_movimiento: 'SCRAP', area: 'INVENTARIO', pcb_part_no: 'EBR87145141', modelo: 'M1', created_at: '2026-09-03 08:00:00' },
  ], [
    { entry_scan_id: 1, sort_order: 1, defect_type: 'CORTO', repair_status: 'REPAIRED' },
    { entry_scan_id: 1, sort_order: 2, defect_type: 'FALTANTE', repair_status: 'REPAIRED' },
  ]);

  assert.equal(history.movements[0].defects.length, 2);
  assert.equal(history.movements[1].defects.length, 0); // salida ligada no repite defectos
  assert.equal(history.movements[2].defects[0].defect_type, 'LEGACY');
  assert.deepStrictEqual(
    { ...history.summary, last_movement: history.summary.last_movement.tipo_movimiento },
    { total_entradas: 2, total_salidas: 1, total_scrap: 1, repair_cycles: 1, total_defects: 3, last_movement: 'SCRAP' }
  );
  assert.equal(buildPcbHistory([], []).summary.last_movement, null);
});
