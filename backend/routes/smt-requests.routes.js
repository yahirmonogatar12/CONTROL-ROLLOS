/**
 * SMT Material Requests Routes
 * Proxy al backend central de ESCANEO_INPUT para solicitudes de material SMT
 * Pantalla Flutter: lib/screens/mobile/mobile_smt_requests_screen.dart
 */

const express = require('express');
const router = express.Router();
const fs = require('fs');
const http = require('http');
const path = require('path');
const { pool } = require('../config/database');

// URL del central backend (configurable via .env o archivo local persistente)
let CENTRAL_URL = process.env.CENTRAL_URL || 'http://localhost:4000';

function normalizeCentralUrl(rawUrl) {
    const trimmed = String(rawUrl || '').trim();
    if (!trimmed) {
        throw new Error('CENTRAL_URL no puede estar vacia');
    }

    const withProtocol = /^https?:\/\//i.test(trimmed)
        ? trimmed
        : `http://${trimmed}`;

    const parsed = new URL(withProtocol);
    const isHttps = parsed.protocol === 'https:';
    const defaultPort = isHttps ? '443' : '80';
    const hasCustomPort = parsed.port && parsed.port !== defaultPort;

    return `${parsed.protocol}//${parsed.hostname}${hasCustomPort ? `:${parsed.port}` : ''}`;
}

function parseCentralUrl(rawUrl) {
    const normalized = normalizeCentralUrl(rawUrl);
    const parsed = new URL(normalized);
    const useHttps = parsed.protocol === 'https:';

    return {
        centralUrl: normalized,
        centralHost: parsed.hostname,
        centralPort: parsed.port
            ? parseInt(parsed.port, 10)
            : (useHttps ? 443 : 80),
        centralUseHttps: useHttps,
    };
}

function getConfigPaths() {
    const envPath = (process.env.SMT_REQUESTS_CONFIG_PATH || '').trim();
    if (envPath) {
        return {
            configFile: envPath,
            fallbackFiles: [],
        };
    }

    if (process.pkg) {
        const localAppData = (process.env.LOCALAPPDATA || process.env.APPDATA || '').trim();
        const configFile = localAppData
            ? path.join(localAppData, 'Control inventario SMD', 'smt_requests_config.json')
            : path.join(path.dirname(process.execPath), 'smt_requests_config.json');
        const legacyFile = path.join(path.dirname(process.execPath), 'smt_requests_config.json');

        return {
            configFile,
            fallbackFiles: configFile === legacyFile ? [] : [legacyFile],
        };
    }

    return {
        configFile: path.join(process.cwd(), 'smt_requests_config.json'),
        fallbackFiles: [],
    };
}

const { configFile: CONFIG_FILE, fallbackFiles: CONFIG_FALLBACK_FILES } =
    getConfigPaths();

function loadSavedConfig() {
    try {
        const configFilesToTry = [CONFIG_FILE, ...CONFIG_FALLBACK_FILES];

        for (const configFile of configFilesToTry) {
            if (!configFile || !fs.existsSync(configFile)) {
                continue;
            }

            const saved = JSON.parse(fs.readFileSync(configFile, 'utf8'));
            if (saved && saved.centralUrl) {
                CENTRAL_URL = normalizeCentralUrl(saved.centralUrl);
                return;
            }
        }

        CENTRAL_URL = normalizeCentralUrl(CENTRAL_URL);
    } catch (err) {
        console.error('Error cargando configuracion SMT/FCM:', err.message);
        CENTRAL_URL = normalizeCentralUrl(CENTRAL_URL);
    }
}

function saveConfig() {
    try {
        const dir = path.dirname(CONFIG_FILE);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        fs.writeFileSync(
            CONFIG_FILE,
            JSON.stringify({
                centralUrl: CENTRAL_URL,
            }, null, 2),
            'utf8'
        );
    } catch (err) {
        console.error('Error guardando configuracion SMT/FCM:', err.message);
        throw err;
    }
}

loadSavedConfig();

function getCentralUrl() {
    return CENTRAL_URL;
}

function extractPartNumber(reelCode) {
    const normalized = (reelCode || '').toString().trim();
    if (!normalized) {
        return '';
    }
    return normalized.split('-')[0].trim();
}

async function enrichRequestsWithMaterialData(requests) {
    if (!Array.isArray(requests) || requests.length === 0) {
        return [];
    }

    const partNumbers = Array.from(
        new Set(
            requests
                .map((request) => extractPartNumber(request.reel_code))
                .filter(Boolean)
        )
    );

    if (partNumbers.length === 0) {
        return requests.map((request) => ({
            ...request,
            numero_parte: extractPartNumber(request.reel_code),
            ubicacion_rollos: null,
        }));
    }

    const placeholders = partNumbers.map(() => '?').join(', ');
    const [rows] = await pool.query(
        `SELECT numero_parte,
                ubicacion_rollos,
                ubicacion_material
         FROM materiales
         WHERE numero_parte IN (${placeholders})`,
        partNumbers
    );

    const materialMap = new Map(
        rows.map((row) => [
            row.numero_parte,
            row.ubicacion_rollos || row.ubicacion_material || null,
        ])
    );

    return requests.map((request) => {
        const numeroParte = extractPartNumber(request.reel_code);
        return {
            ...request,
            numero_parte: numeroParte,
            ubicacion_rollos: materialMap.get(numeroParte) || null,
        };
    });
}

/**
 * Helper: proxy request al central backend
 */
async function proxyToCentral(method, path, body = null) {
    const centralUrl = getCentralUrl();
    const url = new URL(path, centralUrl);

    const options = {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method,
        headers: { 'Content-Type': 'application/json' },
        timeout: 10000,
    };

    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    resolve({ ok: false, error: 'Invalid response from central' });
                }
            });
        });

        req.on('error', (err) => {
            resolve({ ok: false, error: `Central unreachable: ${err.message}` });
        });

        req.on('timeout', () => {
            req.destroy();
            resolve({ ok: false, error: 'Central timeout' });
        });

        if (body) {
            req.write(JSON.stringify(body));
        }
        req.end();
    });
}

/**
 * GET /api/smt-requests/config - Obtener configuracion del proxy SMT/FCM
 */
router.get('/config', async (req, res) => {
    try {
        res.json({
            ok: true,
            config: parseCentralUrl(getCentralUrl()),
        });
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * POST /api/smt-requests/config - Guardar configuracion del proxy SMT/FCM
 * Body: { centralHost, centralPort, centralUseHttps } o { centralUrl }
 */
router.post('/config', async (req, res) => {
    try {
        const {
            centralUrl,
            centralHost,
            centralPort,
            centralUseHttps = false,
        } = req.body || {};

        let nextUrl = centralUrl;
        if (!nextUrl) {
            const host = String(centralHost || '').trim();
            const port = parseInt(centralPort, 10) || 4000;

            if (!host) {
                return res.status(400).json({
                    ok: false,
                    error: 'Se requiere centralHost o centralUrl',
                });
            }

            const protocol = centralUseHttps ? 'https' : 'http';
            const defaultPort = centralUseHttps ? 443 : 80;
            nextUrl = port === defaultPort
                ? `${protocol}://${host}`
                : `${protocol}://${host}:${port}`;
        }

        CENTRAL_URL = normalizeCentralUrl(nextUrl);
        saveConfig();

        res.json({
            ok: true,
            message: 'Configuracion SMT/FCM actualizada',
            config: parseCentralUrl(CENTRAL_URL),
        });
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * GET /api/smt-requests - Listar solicitudes de material
 * Query: status, lineId, workingDate, limit
 */
router.get('/', async (req, res) => {
    try {
        const { status, lineId, workingDate, limit, compact } = req.query;
        let path = '/material-requests?';
        if (status) path += `status=${status}&`;
        if (lineId) path += `lineId=${lineId}&`;
        if (workingDate) path += `workingDate=${workingDate}&`;
        if (limit) path += `limit=${limit}&`;

        const result = await proxyToCentral('GET', path);
        if (result?.ok === true && Array.isArray(result.requests)) {
            const enrichedRequests = await enrichRequestsWithMaterialData(
                result.requests
            );
            const useCompact = compact === '1' || compact === 'true';
            const requests = useCompact
                ? enrichedRequests.map((request) => ({
                    id: request.id,
                    status: request.status,
                    line_id: request.line_id,
                    reel_code: request.reel_code,
                    numero_parte: request.numero_parte,
                    ubicacion_rollos: request.ubicacion_rollos,
                    requested_at: request.requested_at,
                    fulfilled_by: request.fulfilled_by,
                    fulfilled_at: request.fulfilled_at,
                }))
                : enrichedRequests;
            return res.json({
                ...result,
                requests,
            });
        }

        res.json(result);
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * GET /api/smt-requests/pending-count - Conteo de pendientes
 */
router.get('/pending-count', async (req, res) => {
    try {
        const { lineId } = req.query;
        let path = '/material-requests/pending-count?';
        if (lineId) path += `lineId=${lineId}&`;

        const result = await proxyToCentral('GET', path);
        res.json(result);
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * PUT /api/smt-requests/:id/fulfill - Marcar como surtido
 */
router.put('/:id/fulfill', async (req, res) => {
    try {
        const result = await proxyToCentral(
            'PUT',
            `/material-requests/${req.params.id}/fulfill`,
            req.body
        );
        res.json(result);
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * PUT /api/smt-requests/:id/cancel - Cancelar solicitud
 */
router.put('/:id/cancel', async (req, res) => {
    try {
        const result = await proxyToCentral(
            'PUT',
            `/material-requests/${req.params.id}/cancel`,
            req.body
        );
        res.json(result);
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

/**
 * POST /api/smt-requests/fcm-token - Registrar token FCM
 */
router.post('/fcm-token', async (req, res) => {
    try {
        const result = await proxyToCentral(
            'POST',
            '/material-requests/fcm-token',
            req.body
        );
        res.json(result);
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

module.exports = router;
