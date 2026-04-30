/**
 * Script de Importación Masiva de Entradas de Material
 * 
 * Uso:
 *   node bulk_import_warehousing.js --file inventario.csv --user "admin" [--url http://localhost:3000]
 * 
 * Formato CSV requerido:
 *   codigo_material_recibido,numero_parte,numero_lote_material,cantidad_actual,fecha_recibo,fecha_fabricacion,ubicacion_salida,especificacion,unidad_empaque
 * 
 * Campos requeridos: codigo_material_recibido, numero_parte, cantidad_actual, fecha_recibo, ubicacion_salida, especificacion
 * Campos opcionales: numero_lote_material, fecha_fabricacion, unidad_empaque (default: EA)
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

// Configuración
const CONFIG = {
  BATCH_SIZE: 500,         // Registros por batch enviados al API
  API_TIMEOUT: 120000,     // 2 minutos timeout por batch
  DEFAULT_URL: 'http://localhost:3000'
};

// Colores para consola
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  bold: '\x1b[1m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

// Parsear argumentos de línea de comando
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    file: null,
    user: 'bulk_import',
    url: CONFIG.DEFAULT_URL
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--file':
      case '-f':
        options.file = args[++i];
        break;
      case '--user':
      case '-u':
        options.user = args[++i];
        break;
      case '--url':
        options.url = args[++i];
        break;
      case '--help':
      case '-h':
        printHelp();
        process.exit(0);
    }
  }

  return options;
}

function printHelp() {
  console.log(`
${colors.bold}Importación Masiva de Entradas de Material${colors.reset}

${colors.cyan}Uso:${colors.reset}
  node bulk_import_warehousing.js --file <archivo.csv> [opciones]

${colors.cyan}Opciones:${colors.reset}
  --file, -f    Archivo CSV a importar (requerido)
  --user, -u    Usuario que realiza la importación (default: bulk_import)
  --url         URL del API (default: http://localhost:3000)
  --help, -h    Mostrar esta ayuda

${colors.cyan}Formato CSV:${colors.reset}
  Columnas requeridas:
    - codigo_material_recibido  (ej: EAE66213501-202501070001)
    - numero_parte              (ej: EAE66213501)
    - cantidad_actual           (ej: 1000)
    - fecha_recibo              (ej: 2025-01-07)
    - ubicacion_salida          (ej: A-01-02)
    - especificacion            (ej: LG Display Panel)

  Columnas opcionales:
    - numero_lote_material      (ej: LOT-2025-001, puede estar vacío)
    - fecha_fabricacion         (ej: 2024-12-15, puede estar vacío)
    - unidad_empaque            (ej: EA, default: EA)

${colors.cyan}Ejemplo:${colors.reset}
  node bulk_import_warehousing.js --file inventario.csv --user "admin"
`);
}

// Parsear CSV línea por línea (más eficiente para archivos grandes)
async function parseCSV(filePath) {
  return new Promise((resolve, reject) => {
    const entries = [];
    let headers = null;
    let lineNumber = 0;

    const fileStream = fs.createReadStream(filePath, { encoding: 'utf8' });
    const rl = readline.createInterface({
      input: fileStream,
      crlfDelay: Infinity
    });

    rl.on('line', (line) => {
      lineNumber++;
      
      // Ignorar líneas vacías
      if (!line.trim()) return;

      // Parsear CSV (soporta campos entre comillas)
      const values = parseCSVLine(line);

      if (!headers) {
        // Primera línea son los headers
        headers = values.map(h => h.trim().toLowerCase());
        return;
      }

      // Crear objeto con los valores
      const entry = {};
      headers.forEach((header, index) => {
        let value = values[index] || '';
        value = value.trim();
        
        // Limpiar comillas
        if (value.startsWith('"') && value.endsWith('"')) {
          value = value.slice(1, -1);
        }
        
        // Convertir números (quitar comas de miles como "1,000" -> 1000)
        if (header === 'cantidad_actual') {
          value = parseInt(value.replace(/,/g, '')) || 0;
        }
        
        // Campos vacíos a null para opcionales
        if (value === '' && ['numero_lote_material', 'fecha_fabricacion'].includes(header)) {
          value = null;
        }
        
        entry[header] = value;
      });

      entry._row = lineNumber;
      entries.push(entry);
    });

    rl.on('close', () => {
      resolve(entries);
    });

    rl.on('error', (err) => {
      reject(err);
    });
  });
}

// Parsear una línea CSV respetando comillas
function parseCSVLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const nextChar = line[i + 1];

    if (char === '"') {
      if (inQuotes && nextChar === '"') {
        current += '"';
        i++; // Skip next quote
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }

  result.push(current);
  return result;
}

// Validar entrada antes de enviar
function validateEntry(entry) {
  const errors = [];
  const requiredFields = [
    'codigo_material_recibido',
    'numero_parte', 
    'cantidad_actual',
    'fecha_recibo',
    'ubicacion_salida',
    'especificacion'
  ];

  for (const field of requiredFields) {
    if (!entry[field] && entry[field] !== 0) {
      errors.push(`Campo requerido faltante: ${field}`);
    }
  }

  // Validar formato de fecha
  if (entry.fecha_recibo && !/^\d{4}-\d{2}-\d{2}/.test(entry.fecha_recibo)) {
    errors.push(`Formato de fecha_recibo inválido: ${entry.fecha_recibo} (usar YYYY-MM-DD)`);
  }

  // Validar cantidad
  if (entry.cantidad_actual !== undefined && (isNaN(entry.cantidad_actual) || entry.cantidad_actual < 0)) {
    errors.push(`cantidad_actual inválida: ${entry.cantidad_actual}`);
  }

  return errors;
}

// Enviar batch al API
async function sendBatch(entries, apiUrl, usuario) {
  const url = `${apiUrl}/api/warehousing/bulk-import`;
  
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), CONFIG.API_TIMEOUT);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        entries,
        usuario_registro: usuario
      }),
      signal: controller.signal
    });

    clearTimeout(timeout);

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }

    return await response.json();
  } catch (err) {
    clearTimeout(timeout);
    throw err;
  }
}

// Guardar reporte de errores
function saveErrorReport(errors, originalFile) {
  if (errors.length === 0) return null;

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const baseName = path.basename(originalFile, path.extname(originalFile));
  const errorFile = `bulk_import_errors_${baseName}_${timestamp}.json`;

  fs.writeFileSync(errorFile, JSON.stringify(errors, null, 2), 'utf8');
  return errorFile;
}

// Función principal
async function main() {
  const options = parseArgs();

  // Validar archivo
  if (!options.file) {
    log('Error: Se requiere especificar un archivo CSV con --file', 'red');
    printHelp();
    process.exit(1);
  }

  if (!fs.existsSync(options.file)) {
    log(`Error: Archivo no encontrado: ${options.file}`, 'red');
    process.exit(1);
  }

  log(`\n${'='.repeat(60)}`, 'cyan');
  log('  IMPORTACIÓN MASIVA DE ENTRADAS DE MATERIAL', 'bold');
  log(`${'='.repeat(60)}`, 'cyan');
  log(`\nArchivo: ${options.file}`, 'cyan');
  log(`Usuario: ${options.user}`, 'cyan');
  log(`API URL: ${options.url}`, 'cyan');

  // Leer CSV
  log('\n[1/4] Leyendo archivo CSV...', 'yellow');
  const startRead = Date.now();
  const entries = await parseCSV(options.file);
  log(`      ${entries.length} registros leídos en ${Date.now() - startRead}ms`, 'green');

  if (entries.length === 0) {
    log('Error: El archivo CSV está vacío o no tiene datos válidos', 'red');
    process.exit(1);
  }

  // Validar localmente
  log('\n[2/4] Validando datos...', 'yellow');
  const validEntries = [];
  const localErrors = [];

  for (const entry of entries) {
    const errors = validateEntry(entry);
    if (errors.length > 0) {
      localErrors.push({
        row: entry._row,
        codigo: entry.codigo_material_recibido || 'N/A',
        errors
      });
    } else {
      // Remover campo interno _row antes de enviar
      const { _row, ...cleanEntry } = entry;
      validEntries.push(cleanEntry);
    }
  }

  log(`      ${validEntries.length} registros válidos`, 'green');
  if (localErrors.length > 0) {
    log(`      ${localErrors.length} registros con errores de validación`, 'red');
  }

  if (validEntries.length === 0) {
    log('\nError: No hay registros válidos para importar', 'red');
    const errorFile = saveErrorReport(localErrors, options.file);
    if (errorFile) {
      log(`Ver errores en: ${errorFile}`, 'yellow');
    }
    process.exit(1);
  }

  // Procesar en batches
  log('\n[3/4] Enviando al servidor...', 'yellow');
  const totalBatches = Math.ceil(validEntries.length / CONFIG.BATCH_SIZE);
  let totalSuccess = 0;
  let totalFailed = 0;
  const allErrors = [...localErrors];

  const startProcess = Date.now();

  for (let i = 0; i < validEntries.length; i += CONFIG.BATCH_SIZE) {
    const batchNum = Math.floor(i / CONFIG.BATCH_SIZE) + 1;
    const batch = validEntries.slice(i, i + CONFIG.BATCH_SIZE);

    process.stdout.write(`      Batch ${batchNum}/${totalBatches} (${batch.length} registros)... `);

    try {
      const result = await sendBatch(batch, options.url, options.user);
      
      totalSuccess += result.results.success;
      totalFailed += result.results.failed;
      
      if (result.results.errors && result.results.errors.length > 0) {
        allErrors.push(...result.results.errors);
      }

      log(`✓ ${result.results.success} éxitos, ${result.results.failed} errores`, 'green');
    } catch (err) {
      log(`✗ Error: ${err.message}`, 'red');
      totalFailed += batch.length;
      
      // Marcar todo el batch como fallido
      batch.forEach((entry, idx) => {
        allErrors.push({
          row: i + idx + 1,
          codigo: entry.codigo_material_recibido,
          error: `Error de conexión: ${err.message}`
        });
      });
    }
  }

  const processingTime = ((Date.now() - startProcess) / 1000).toFixed(2);

  // Resumen final
  log('\n[4/4] Generando reporte...', 'yellow');
  
  log(`\n${'='.repeat(60)}`, 'cyan');
  log('  RESUMEN DE IMPORTACIÓN', 'bold');
  log(`${'='.repeat(60)}`, 'cyan');
  log(`\n  Total en archivo:    ${entries.length}`, 'cyan');
  log(`  Importados:          ${totalSuccess}`, 'green');
  log(`  Fallidos:            ${totalFailed + localErrors.length}`, totalFailed + localErrors.length > 0 ? 'red' : 'green');
  log(`  Tiempo:              ${processingTime} segundos`, 'cyan');
  log(`  Velocidad:           ${(entries.length / parseFloat(processingTime)).toFixed(0)} registros/segundo`, 'cyan');

  if (allErrors.length > 0) {
    const errorFile = saveErrorReport(allErrors, options.file);
    log(`\n  Errores guardados en: ${errorFile}`, 'yellow');
  }

  log(`\n${'='.repeat(60)}\n`, 'cyan');

  process.exit(allErrors.length > 0 ? 1 : 0);
}

// Ejecutar
main().catch(err => {
  log(`\nError fatal: ${err.message}`, 'red');
  console.error(err);
  process.exit(1);
});
