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
