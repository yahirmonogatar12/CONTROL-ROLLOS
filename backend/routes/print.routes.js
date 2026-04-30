/**
 * Print Routes - Impresión remota para móviles
 * Permite a dispositivos móviles imprimir vía el servidor backend
 * Soporta: TCP/IP directo (impresora en red) o RawPrinterHelper de Windows (USB/Driver)
 */

const express = require('express');
const net = require('net');
const { exec, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const router = express.Router();

// Configuración de impresora desde variables de entorno
let PRINTER_IP = process.env.PRINTER_IP || '';
let PRINTER_PORT = parseInt(process.env.PRINTER_PORT) || 9100;
// Nombre de la impresora instalada en Windows (para USB)
let PRINTER_NAME = process.env.PRINTER_NAME || 'ZDesigner ZT230-200dpi ZPL';
// Archivo de configuración local para persistir cambios
function getConfigPaths() {
  const envPath = (process.env.PRINTER_CONFIG_PATH || '').trim();
  if (envPath) {
    return {
      configFile: envPath,
      fallbackFiles: [],
    };
  }

  if (process.pkg) {
    const localAppData = (process.env.LOCALAPPDATA || process.env.APPDATA || '').trim();
    const configFile = localAppData
      ? path.join(localAppData, 'Control inventario SMD', 'printer_config.json')
      : path.join(path.dirname(process.execPath), 'printer_config.json');
    const legacyFile = path.join(path.dirname(process.execPath), 'printer_config.json');

    return {
      configFile,
      fallbackFiles: configFile === legacyFile ? [] : [legacyFile],
    };
  }

  return {
    configFile: path.join(process.cwd(), 'printer_config.json'),
    fallbackFiles: [],
  };
}

const { configFile: CONFIG_FILE, fallbackFiles: CONFIG_FALLBACK_FILES } =
  getConfigPaths();

// Cargar configuración guardada si existe
function loadSavedConfig() {
  try {
    const configFilesToTry = [CONFIG_FILE, ...CONFIG_FALLBACK_FILES];
    for (const configFile of configFilesToTry) {
      if (!configFile || !fs.existsSync(configFile)) {
        continue;
      }

      const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
      if (config.printerName) PRINTER_NAME = config.printerName;
      if (config.printerIp) PRINTER_IP = config.printerIp;
      if (config.printerPort) PRINTER_PORT = config.printerPort;
      return;
    }
  } catch (e) {
    // Ignorar errores de configuración de impresora
  }
}

// Guardar configuración
function saveConfig() {
  try {
    const dir = path.dirname(CONFIG_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(CONFIG_FILE, JSON.stringify({
      printerName: PRINTER_NAME,
      printerIp: PRINTER_IP,
      printerPort: PRINTER_PORT,
    }, null, 2), 'utf8');
  } catch (e) {
    console.error('Error guardando configuración de impresora:', e);
  }
}

// Cargar configuración al iniciar
loadSavedConfig();

/**
 * GET /api/print/status
 * Verifica si hay una impresora configurada en el servidor
 */
router.get('/status', async (req, res) => {
  // Verificar si hay impresora por IP o por nombre de Windows
  const hasNetworkPrinter = PRINTER_IP && PRINTER_IP !== '' && PRINTER_IP !== '127.0.0.1';
  const hasWindowsPrinter = PRINTER_NAME && PRINTER_NAME !== '';
  
  // Listar impresoras instaladas en Windows
  let installedPrinters = [];
  try {
    installedPrinters = await listWindowsPrinters();
  } catch (e) {
    console.error('Error listando impresoras:', e);
  }
  
  const printerExists = installedPrinters.some(p => 
    p.toLowerCase().includes(PRINTER_NAME.toLowerCase()) ||
    PRINTER_NAME.toLowerCase().includes(p.toLowerCase())
  );
  
  res.json({
    configured: hasNetworkPrinter || (hasWindowsPrinter && printerExists),
    mode: hasNetworkPrinter ? 'network' : 'windows',
    printerIp: PRINTER_IP || null,
    printerPort: PRINTER_PORT,
    printerName: PRINTER_NAME,
    printerFound: printerExists,
    installedPrinters: installedPrinters,
  });
});

/**
 * GET /api/print/printers
 * Lista todas las impresoras instaladas en Windows
 */
router.get('/printers', async (req, res) => {
  try {
    const printers = await listWindowsPrinters();
    res.json({
      success: true,
      printers: printers,
      currentPrinter: PRINTER_NAME,
    });
  } catch (e) {
    res.status(500).json({
      success: false,
      error: e.message,
    });
  }
});

/**
 * POST /api/print/configure
 * Configura la impresora a usar para impresión desde móvil
 * Body: { printerName?: string, printerIp?: string, printerPort?: number }
 */
  router.post('/configure', async (req, res) => {
    try {
      const { printerName, printerIp, printerPort } = req.body;
      
      const normalizedPrinterIp = printerIp === null || printerIp === undefined
        ? ''
        : String(printerIp).trim();
      const hasNetworkPrinter = normalizedPrinterIp !== '';

      if (printerName !== undefined) {
        const normalizedPrinterName = printerName === null ? '' : String(printerName);
        // Verificar que la impresora existe solo si NO se configuró IP
        if (!hasNetworkPrinter && normalizedPrinterName !== '') {
          try {
            const printers = await listWindowsPrinters();
            const exists = printers.some(p => 
              p.toLowerCase() === normalizedPrinterName.toLowerCase() ||
              p.toLowerCase().includes(normalizedPrinterName.toLowerCase())
            );
            
            if (!exists) {
              return res.status(400).json({
                success: false,
                error: `Impresora no encontrada: ${normalizedPrinterName}`,
                availablePrinters: printers,
              });
            }
          } catch (e) {
            console.warn('No se pudo validar impresora en Windows:', e.message || e);
          }
        }
        
        PRINTER_NAME = normalizedPrinterName;
      }
      
      if (printerIp !== undefined) {
        PRINTER_IP = normalizedPrinterIp;
      }
    
    if (printerPort !== undefined) {
      PRINTER_PORT = parseInt(printerPort) || 9100;
    }
    
    // Guardar configuración
    saveConfig();
    
    res.json({
      success: true,
      config: {
        printerName: PRINTER_NAME,
        printerIp: PRINTER_IP,
        printerPort: PRINTER_PORT,
      },
    });
  } catch (e) {
    res.status(500).json({
      success: false,
      error: e.message,
    });
  }
});

/**
 * POST /api/print/label
 * Envía código ZPL a la impresora configurada
 * Body: { zpl: string }
 */
router.post('/label', async (req, res) => {
  try {
    const { zpl } = req.body;

    if (!zpl) {
      return res.status(400).json({
        success: false,
        error: 'ZPL code is required',
      });
    }

    let result;
    
    // Si hay IP configurada, usar TCP/IP directo
    if (PRINTER_IP && PRINTER_IP !== '' && PRINTER_IP !== '127.0.0.1') {
      console.log('Imprimiendo vía TCP/IP a', PRINTER_IP);
      result = await sendToZebraPrinter(zpl, PRINTER_IP, PRINTER_PORT);
    } else {
      // Usar impresora de Windows
      console.log('Imprimiendo vía Windows a', PRINTER_NAME);
      result = await printViaWindows(zpl, PRINTER_NAME);
    }

    if (result.success) {
      res.json({ success: true });
    } else {
      res.status(500).json({
        success: false,
        error: result.error,
      });
    }
  } catch (error) {
    console.error('Error en /api/print/label:', error.message);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * POST /api/print/zpl
 * Envía código ZPL a una impresora específica (para móviles usando Vercel + PC intermediario)
 * Body: { zpl: string, printerIp?: string, printerPort?: number }
 */
router.post('/zpl', async (req, res) => {
  try {
    const { zpl, printerIp, printerPort = 9100 } = req.body;

    if (!zpl) {
      return res.status(400).json({
        success: false,
        message: 'ZPL code is required',
      });
    }

    let result;
    const targetIp = printerIp || PRINTER_IP;
    const targetPort = printerPort || PRINTER_PORT;
    
    // Si hay IP específica o configurada, usar TCP/IP directo
    if (targetIp && targetIp !== '' && targetIp !== '127.0.0.1') {
      console.log(`Imprimiendo vía TCP/IP a ${targetIp}:${targetPort}`);
      result = await sendToZebraPrinter(zpl, targetIp, targetPort);
    } else {
      // Usar impresora de Windows
      console.log('Imprimiendo vía Windows a', PRINTER_NAME);
      result = await printViaWindows(zpl, PRINTER_NAME);
    }

    if (result.success) {
      res.json({ 
        success: true,
        message: 'Print job sent successfully'
      });
    } else {
      res.status(500).json({
        success: false,
        message: result.error,
      });
    }
  } catch (error) {
    console.error('Error en /api/print/zpl:', error.message);
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
});

/**
 * Lista las impresoras instaladas en Windows
 */
function listWindowsPrinters() {
  return new Promise((resolve, reject) => {
    if (os.platform() !== 'win32') {
      resolve([]);
      return;
    }
    
    exec('wmic printer get name', { encoding: 'utf8' }, (error, stdout, stderr) => {
      if (error) {
        reject(error);
        return;
      }
      
      const printers = stdout
        .split('\n')
        .map(line => line.trim())
        .filter(line => line && line !== 'Name');
      
      resolve(printers);
    });
  });
}

/**
 * Imprime ZPL usando RawPrinterHelper de Windows (envío directo vía winspool.drv)
 * Este es el mismo método que usa el cliente Flutter en PC y funciona correctamente
 * @param {string} zpl - Código ZPL
 * @param {string} printerName - Nombre de la impresora en Windows
 */
function printViaWindows(zpl, printerName) {
  return new Promise((resolve) => {
    const tempDir = os.tmpdir();
    const scriptFile = path.join(tempDir, `print_raw_${Date.now()}.ps1`);
    
    // Script PowerShell con RawPrinterHelper - mismo método que printer_service.dart
    const psScript = `
param([string]$PrinterName, [string]$ZplData)

\$signature = @'
[DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool ClosePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool StartDocPrinter(IntPtr hPrinter, int Level, ref DOCINFOA pDocInfo);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool EndDocPrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool StartPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool EndPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", SetLastError = true)]
public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DOCINFOA {
    [MarshalAs(UnmanagedType.LPStr)]
    public string pDocName;
    [MarshalAs(UnmanagedType.LPStr)]
    public string pOutputFile;
    [MarshalAs(UnmanagedType.LPStr)]
    public string pDataType;
}
'@

try {
    Add-Type -MemberDefinition \$signature -Name 'RawPrinterHelper' -Namespace 'Win32' -PassThru | Out-Null
} catch {
    # Type may already exist
}

function Send-RawDataToPrinter {
    param([string]\$printerName, [string]\$data)
    
    \$hPrinter = [IntPtr]::Zero
    
    if (-not [Win32.RawPrinterHelper]::OpenPrinter(\$printerName, [ref]\$hPrinter, [IntPtr]::Zero)) {
        throw "No se pudo abrir la impresora: \$printerName (Error: \$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
    
    try {
        \$di = New-Object Win32.RawPrinterHelper+DOCINFOA
        \$di.pDocName = "ZPL Label"
        \$di.pDataType = "RAW"
        
        if (-not [Win32.RawPrinterHelper]::StartDocPrinter(\$hPrinter, 1, [ref]\$di)) {
            throw "StartDocPrinter falló"
        }
        
        try {
            if (-not [Win32.RawPrinterHelper]::StartPagePrinter(\$hPrinter)) {
                throw "StartPagePrinter falló"
            }
            
            try {
                \$bytes = [System.Text.Encoding]::UTF8.GetBytes(\$data)
                \$pBytes = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(\$bytes.Length)
                [System.Runtime.InteropServices.Marshal]::Copy(\$bytes, 0, \$pBytes, \$bytes.Length)
                
                \$written = 0
                \$success = [Win32.RawPrinterHelper]::WritePrinter(\$hPrinter, \$pBytes, \$bytes.Length, [ref]\$written)
                
                [System.Runtime.InteropServices.Marshal]::FreeHGlobal(\$pBytes)
                
                if (-not \$success) {
                    throw "WritePrinter falló"
                }
            } finally {
                [Win32.RawPrinterHelper]::EndPagePrinter(\$hPrinter) | Out-Null
            }
        } finally {
            [Win32.RawPrinterHelper]::EndDocPrinter(\$hPrinter) | Out-Null
        }
    } finally {
        [Win32.RawPrinterHelper]::ClosePrinter(\$hPrinter) | Out-Null
    }
    
    return \$true
}

try {
    Send-RawDataToPrinter -printerName \$PrinterName -data \$ZplData
    Write-Output "OK"
} catch {
    Write-Output "ERROR: \$_"
}
`;

    fs.writeFile(scriptFile, psScript, 'utf8', (scriptErr) => {
      if (scriptErr) {
        resolve({ success: false, error: `Error creando script: ${scriptErr.message}` });
        return;
      }

      // Escapar el ZPL para PowerShell (reemplazar comillas dobles y backticks)
      const escapedZpl = zpl
        .replace(/`/g, '``')
        .replace(/"/g, '`"')
        .replace(/\$/g, '`$');

      const args = [
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', scriptFile,
        '-PrinterName', printerName,
        '-ZplData', escapedZpl
      ];

      execFile('powershell.exe', args, { encoding: 'utf8', timeout: 15000 }, (error, stdout, stderr) => {
        // Limpiar archivo temporal
        fs.unlink(scriptFile, () => {});

        const output = (stdout || '').trim();
        
        if (error) {
          console.error('Error ejecutando PowerShell:', error.message);
          console.error('Stderr:', stderr);
          resolve({ success: false, error: error.message || stderr || 'Error desconocido' });
          return;
        }

        if (output === 'OK') {
          console.log('Impresión RAW enviada exitosamente vía RawPrinterHelper');
          resolve({ success: true });
        } else if (output.startsWith('ERROR:')) {
          resolve({ success: false, error: output.substring(7).trim() });
        } else {
          console.log('Output de PowerShell:', output);
          // Si contiene "OK" en algún lugar, considerar éxito
          if (output.includes('OK')) {
            resolve({ success: true });
          } else {
            resolve({ success: false, error: output || 'Respuesta inesperada' });
          }
        }
      });
    });
  });
}

/**
 * Envía código ZPL a una impresora Zebra vía socket TCP
 * @param {string} zpl - Código ZPL a imprimir
 * @param {string} ip - IP de la impresora
 * @param {number} port - Puerto (default 9100)
 * @returns {Promise<{success: boolean, error?: string}>}
 */
function sendToZebraPrinter(zpl, ip, port = 9100) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let resolved = false;

    // Timeout de 5 segundos
    socket.setTimeout(5000);

    socket.on('connect', () => {
      console.log(`Conectado a impresora ${ip}:${port}`);
      socket.write(zpl, 'utf8', () => {
        console.log('ZPL enviado exitosamente');
        socket.end();
      });
    });

    socket.on('close', () => {
      if (!resolved) {
        resolved = true;
        resolve({ success: true });
      }
    });

    socket.on('error', (err) => {
      console.error('Error de socket:', err.message);
      if (!resolved) {
        resolved = true;
        let errorMsg = 'Error de conexión';
        
        if (err.code === 'ECONNREFUSED') {
          errorMsg = `Conexión rechazada: La impresora en ${ip}:${port} no responde`;
        } else if (err.code === 'ETIMEDOUT') {
          errorMsg = `Tiempo de espera agotado al conectar a ${ip}:${port}`;
        } else if (err.code === 'ENOTFOUND' || err.code === 'ENOENT') {
          errorMsg = `No se puede encontrar la impresora en ${ip}`;
        } else {
          errorMsg = err.message;
        }
        
        resolve({ success: false, error: errorMsg });
      }
      socket.destroy();
    });

    socket.on('timeout', () => {
      console.error('Timeout de socket');
      if (!resolved) {
        resolved = true;
        resolve({ success: false, error: 'Tiempo de espera agotado' });
      }
      socket.destroy();
    });

    // Conectar a la impresora
    console.log(`Conectando a impresora ${ip}:${port}...`);
    socket.connect(port, ip);
  });
}

module.exports = router;
