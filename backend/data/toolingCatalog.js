'use strict';

// Catalogo base de la columna "No control" del archivo
// DATOS METAL Y SQUEGUEE.xlsx. La ubicacion de las mascaras coincide con el
// codigo sin el sufijo de control -001.
const MASK_CODES = [
  'MM1-1-001', 'MM1-2-001', 'MM1-3-001', 'MM1-4-001', 'MM1-5-001',
  'MM1-6-001', 'MM1-7-001', 'MM2-1-001', 'MM2-2-001', 'MM2-3-001',
  'MM2-4-001', 'MM2-5-001', 'MM2-6-001', 'MM2-7-001', 'MM2-8-001',
  'MM2-9-001', 'MM2-10-001', 'MM2-11-001', 'MM2-12-001', 'MM2-13-001',
  'MM2-14-001', 'MM2-15-001', 'MM3-1-001', 'MM3-2-001', 'MM3-3-001',
  'MM3-4-001', 'MM3-5-001', 'MM3-6-001', 'MM3-7-001', 'MM3-8-001',
  'MM3-9-001', 'MM3-10-001', 'MM3-11-001', 'MM3-12-001', 'MM3-13-001',
  'MM3-14-001', 'MM3-15-001', 'MM4-1-001', 'MM4-2-001', 'MM4-3-001',
  'MM4-4-001', 'MM4-5-001', 'MM4-6-001', 'MM4-7-001', 'MM4-8-001',
  'MM4-9-001', 'MM4-10-001', 'MM5-1-001', 'MM5-2-001', 'MM5-3-001',
  'MM5-4-001', 'MM5-5-001', 'MM5-6-001', 'MM5-7-001', 'MM5-8-001',
  'MM5-9-001', 'MM5-10-001', 'MM5-11-001', 'MM5-12-001', 'MM5-13-001',
  'MM5-14-001', 'MM5-15-001', 'MM5-16-001', 'MM5-17-001', 'MM5-18-001',
  'MM5-19-001', 'MM5-20-001', 'MM5-21-001', 'MM5-22-001', 'MM5-23-001',
  'MM5-24-001', 'MM5-25-001', 'MM5-26-001', 'MM5-27-001', 'MM5-28-001',
  'MM5-29-001', 'MM5-30-001'
];

const SQUEEGEE_CODES = [
  'SQ340-AF-001', 'SQ340-AR-001', 'SQ340-BF-001', 'SQ340-BR-001',
  'SQ340-CF-001', 'SQ340-CR-001', 'SQ440-DF-001', 'SQ440-DR-001'
];

// Piezas que salen de una sola impresion. El plan viene en piezas, asi que las
// impresiones -- que es lo que desgasta la mask -- son plan / array. Los PCB que
// no aparecen aqui son de a una pieza por impresion (array 1).
const PCB_ARRAY = {
  EAX01882201: 2,
  EAX65150407: 4,
  EAX65150408: 5,
  EAX65868914: 4,
  EAX66932502: 2,
  EAX67445308: 4,
  EAX68065705: 5,
  EAX69003501: 2,
  EAX69003601: 2,
  EAX69456901: 2,
  EAX69577801: 4,
  EAX69577803: 5,
  EAX70205601: 2,
  EAX70206402: 2,
};

const SCRAP_MASK_CODES = new Set([
  'MM1-1-001', 'MM3-2-001', 'MM3-6-001', 'MM5-7-001', 'MM5-18-001'
]);

// Datos por mascarilla de la hoja "Datos METAL MASK". El No PCB se guarda
// sin la version (EAX67860915-1.0 -> EAX67860915), que es contra lo que se
// verifica el BOM. La hoja de squeegee solo trae numero de control: no
// ocupan PCB, fecha ni espesor.
const MASK_DETAILS = {
  'MM1-1-001': { pcbNo: 'EAX67860914', productionDate: null, side: 'TOP', thickness: 0.13 },
  'MM1-2-001': { pcbNo: 'EAX67860915', productionDate: '21.03.04', side: 'TOP', thickness: 0.13 },
  'MM1-3-001': { pcbNo: 'EAX67860917', productionDate: '22.10.04', side: 'TOP', thickness: 0.13 },
  'MM1-4-001': { pcbNo: 'EAX66726314', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM1-5-001': { pcbNo: 'EAX66726315', productionDate: '20.08.26', side: 'TOP', thickness: 0.13 },
  'MM1-6-001': { pcbNo: 'EAX66726317', productionDate: '21.03.09', side: 'TOP', thickness: 0.13 },
  'MM1-7-001': { pcbNo: 'EAX70077701', productionDate: '23.03.22', side: 'TOP', thickness: 0.13 },
  'MM2-1-001': { pcbNo: 'EAX65150407', productionDate: '25.05.13', side: 'BOT', thickness: 0.13 },
  'MM2-2-001': { pcbNo: 'EAX65150407', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM2-3-001': { pcbNo: 'EAX65150408', productionDate: '25.05.13', side: 'BOT', thickness: 0.13 },
  'MM2-4-001': { pcbNo: 'EAX65150408', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM2-5-001': { pcbNo: 'EAX66932502', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM2-6-001': { pcbNo: 'EAX69542801', productionDate: '21.08.27', side: 'TOP', thickness: 0.13 },
  'MM2-7-001': { pcbNo: 'EAX69542803', productionDate: '21.08.27', side: 'TOP', thickness: 0.13 },
  'MM2-8-001': { pcbNo: 'EAX69542805', productionDate: '21.07.26', side: 'TOP', thickness: 0.13 },
  'MM2-9-001': { pcbNo: 'EAX69542834', productionDate: '25.04.21', side: 'TOP', thickness: 0.13 },
  'MM2-10-001': { pcbNo: 'EAX66946003', productionDate: '19.12.16', side: 'TOP', thickness: 0.13 },
  'MM2-11-001': { pcbNo: 'EAX66946003', productionDate: '19.12.16', side: 'TOP', thickness: 0.13 },
  'MM2-12-001': { pcbNo: 'EAX66946005', productionDate: '22.05.04', side: 'TOP', thickness: 0.13 },
  'MM2-13-001': { pcbNo: 'EAX66946010', productionDate: '26.03.03', side: 'TOP', thickness: 0.13 },
  'MM2-14-001': { pcbNo: 'EAX65868914', productionDate: '25.06.11', side: 'TOP', thickness: 0.13 },
  'MM2-15-001': { pcbNo: 'EAX69456901', productionDate: '24.02.08', side: 'TOP', thickness: 0.13 },
  'MM3-1-001': { pcbNo: 'EAX65150407', productionDate: '21.12.15', side: 'BOT', thickness: 0.13 },
  'MM3-2-001': { pcbNo: 'EAX65150407', productionDate: null, side: 'TOP', thickness: 0.13 },
  'MM3-3-001': { pcbNo: 'EAX65150408', productionDate: '22.10.12', side: 'BOT', thickness: 0.13 },
  'MM3-4-001': { pcbNo: 'EAX65150408', productionDate: '22.10.12', side: 'TOP', thickness: 0.13 },
  'MM3-5-001': { pcbNo: 'EAX68065705', productionDate: '24.01.23', side: 'BOT', thickness: 0.13 },
  'MM3-6-001': { pcbNo: 'EAX68065705', productionDate: null, side: 'TOP', thickness: 0.13 },
  'MM3-7-001': { pcbNo: 'EAX66946003', productionDate: '22.07.14', side: 'TOP', thickness: 0.13 },
  'MM3-8-001': { pcbNo: 'EAX66946005', productionDate: '22.05.04', side: 'TOP', thickness: 0.13 },
  'MM3-9-001': { pcbNo: 'EAX69577801', productionDate: '23.08.30', side: 'BOT', thickness: 0.13 },
  'MM3-10-001': { pcbNo: 'EAX69577801', productionDate: '23.08.30', side: 'TOP', thickness: 0.13 },
  'MM3-11-001': { pcbNo: 'EAX69577803', productionDate: '23.10.16', side: 'BOT', thickness: 0.13 },
  'MM3-12-001': { pcbNo: 'EAX69577803', productionDate: '23.08.30', side: 'TOP', thickness: 0.13 },
  'MM3-13-001': { pcbNo: 'EAX68065705', productionDate: '24.01.23', side: 'TOP', thickness: 0.13 },
  'MM3-14-001': { pcbNo: 'EAX67445308', productionDate: '25.06.11', side: 'BOT', thickness: 0.13 },
  'MM3-15-001': { pcbNo: 'EAX67445308', productionDate: '25.06.11', side: 'TOP', thickness: 0.13 },
  'MM4-1-001': { pcbNo: 'EAX67860914', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM4-2-001': { pcbNo: 'EAX67860915', productionDate: '21.03.04', side: 'TOP', thickness: 0.13 },
  'MM4-3-001': { pcbNo: 'EAX67860917', productionDate: '22.10.04', side: 'TOP', thickness: 0.13 },
  'MM4-4-001': { pcbNo: 'EAX67860923', productionDate: '23.11.09', side: 'TOP', thickness: 0.13 },
  'MM4-5-001': { pcbNo: 'EAX69871901', productionDate: '24.02.15', side: 'TOP', thickness: 0.13 },
  'MM4-6-001': { pcbNo: 'EAX69871901', productionDate: '22.03.04', side: 'TOP', thickness: 0.13 },
  'MM4-7-001': { pcbNo: 'EAX68384709', productionDate: '24.02.06', side: 'TOP', thickness: 0.13 },
  'MM4-8-001': { pcbNo: 'EAX66726315', productionDate: '20.08.26', side: 'TOP', thickness: 0.13 },
  'MM4-9-001': { pcbNo: 'EAX66726317', productionDate: '21.03.09', side: 'TOP', thickness: 0.13 },
  'MM4-10-001': { pcbNo: 'EAX70077701', productionDate: '23.03.22', side: 'TOP', thickness: 0.13 },
  'MM5-1-001': { pcbNo: 'EAX67860923', productionDate: '23.11.09', side: 'TOP', thickness: 0.13 },
  'MM5-2-001': { pcbNo: 'EAX69471801', productionDate: '24.02.08', side: 'TOP', thickness: 0.13 },
  'MM5-3-001': { pcbNo: 'EAX69471801', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-4-001': { pcbNo: 'EAX69471803', productionDate: '24.01.18', side: 'TOP', thickness: 0.13 },
  'MM5-5-001': { pcbNo: 'EAX69471805', productionDate: '24.02.08', side: 'TOP', thickness: 0.13 },
  'MM5-6-001': { pcbNo: 'EAX01882201', productionDate: '26.02.10', side: 'TOP', thickness: 0.13 },
  'MM5-7-001': { pcbNo: 'EAX01882201', productionDate: null, side: 'TOP', thickness: 0.13 },
  'MM5-8-001': { pcbNo: 'EAX69542803', productionDate: '21.07.26', side: 'TOP', thickness: 0.13 },
  'MM5-9-001': { pcbNo: 'EAX69003501', productionDate: '22.10.25', side: 'TOP', thickness: 0.13 },
  'MM5-10-001': { pcbNo: 'EAX69003501', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-11-001': { pcbNo: 'EAX69003601', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-12-001': { pcbNo: 'EAX69003601', productionDate: '22.10.25', side: 'TOP', thickness: 0.13 },
  'MM5-13-001': { pcbNo: 'EAX67445308', productionDate: '24.02.14', side: 'BOT', thickness: 0.13 },
  'MM5-14-001': { pcbNo: 'EAX67445308', productionDate: '24.02.14', side: 'TOP', thickness: 0.13 },
  'MM5-15-001': { pcbNo: 'EAX70205601', productionDate: '24.01.18', side: 'TOP', thickness: 0.13 },
  'MM5-16-001': { pcbNo: 'EAX66946003', productionDate: '22.07.14', side: 'TOP', thickness: 0.13 },
  'MM5-17-001': { pcbNo: 'EAX66946005', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-18-001': { pcbNo: 'EAX66726314', productionDate: null, side: 'TOP', thickness: 0.13 },
  'MM5-19-001': { pcbNo: 'EAX66726315', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-20-001': { pcbNo: 'EAX70206401', productionDate: '23.09.19', side: 'TOP', thickness: 0.13 },
  'MM5-21-001': { pcbNo: 'EAX70206402', productionDate: '24.02.08', side: 'TOP', thickness: 0.13 },
  'MM5-22-001': { pcbNo: 'EAX70206501', productionDate: '23.09.19', side: 'TOP', thickness: 0.13 },
  'MM5-23-001': { pcbNo: 'EAX70206502', productionDate: '24.02.08', side: 'TOP', thickness: 0.13 },
  'MM5-24-001': { pcbNo: 'EAX69456901', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-25-001': { pcbNo: 'EAX70077701', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-26-001': { pcbNo: 'EAX69577801', productionDate: '25.05.13', side: 'BOT', thickness: 0.13 },
  'MM5-27-001': { pcbNo: 'EAX69577801', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-28-001': { pcbNo: 'EAX69577803', productionDate: '25.05.13', side: 'BOT', thickness: 0.13 },
  'MM5-29-001': { pcbNo: 'EAX69577803', productionDate: '25.05.13', side: 'TOP', thickness: 0.13 },
  'MM5-30-001': { pcbNo: 'EAX65868914', productionDate: '23.10.17', side: 'TOP', thickness: 0.13 },
};

function rows() {
  return [
    ...MASK_CODES.map((controlCode) => ({
      assetType: 'METAL_MASK',
      controlCode,
      assetNo: controlCode.replace(/-001$/, ''),
      locationCode: controlCode.replace(/-001$/, ''),
      // "Usada"/"Recientes" del Excel solo describian el desgaste, no la
      // disponibilidad: ambas quedan ACTIVE y listas para usar. Solo SCRAP bloquea.
      lifecycleStatus: SCRAP_MASK_CODES.has(controlCode) ? 'SCRAP' : 'ACTIVE',
      arraySize: PCB_ARRAY[MASK_DETAILS[controlCode]?.pcbNo] || 1,
      ...(MASK_DETAILS[controlCode] || {}),
    })),
    ...SQUEEGEE_CODES.map((controlCode) => ({
      assetType: 'SQUEEGEE',
      controlCode,
      assetNo: controlCode.replace(/-001$/, ''),
      locationCode: null,
      lifecycleStatus: 'ACTIVE',
    })),
  ];
}

module.exports = { rows, MASK_DETAILS, PCB_ARRAY };
