const { pool } = require('../config/database');
const path = require('path');
const fs = require('fs');

// GET /api/updates/check - Verificar si hay actualizaciones disponibles
exports.checkForUpdates = async (req, res, next) => {
  try {
    const { currentVersion } = req.query;
    
    if (!currentVersion) {
      return res.status(400).json({ 
        success: false, 
        message: 'Current version is required' 
      });
    }
    
    // Obtener la versión más reciente activa
    const [rows] = await pool.query(`
      SELECT 
        version,
        release_date,
        download_url,
        release_notes,
        is_mandatory,
        min_version
      FROM app_versions 
      WHERE is_active = TRUE
      ORDER BY release_date DESC
      LIMIT 1
    `);
    
    if (rows.length === 0) {
      return res.json({ 
        success: true, 
        updateAvailable: false,
        message: 'No versions available'
      });
    }
    
    const latestVersion = rows[0];
    const hasUpdate = compareVersions(latestVersion.version, currentVersion) > 0;
    
    // Verificar si es obligatoria (versión actual menor que min_version)
    let isMandatory = latestVersion.is_mandatory;
    if (latestVersion.min_version) {
      isMandatory = isMandatory || compareVersions(latestVersion.min_version, currentVersion) > 0;
    }
    
    res.json({
      success: true,
      updateAvailable: hasUpdate,
      currentVersion,
      latestVersion: latestVersion.version,
      releaseDate: latestVersion.release_date,
      downloadUrl: latestVersion.download_url,
      releaseNotes: latestVersion.release_notes,
      isMandatory: hasUpdate ? isMandatory : false
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/updates/versions - Lista de todas las versiones
exports.getAllVersions = async (req, res, next) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        id,
        version,
        release_date,
        download_url,
        release_notes,
        is_mandatory,
        min_version,
        created_by,
        is_active
      FROM app_versions 
      ORDER BY release_date DESC
    `);
    
    res.json({
      success: true,
      versions: rows
    });
  } catch (err) {
    next(err);
  }
};

// POST /api/updates/versions - Registrar nueva versión
exports.createVersion = async (req, res, next) => {
  try {
    const { 
      version, 
      download_url, 
      release_notes, 
      is_mandatory = false,
      min_version,
      created_by 
    } = req.body;
    
    if (!version) {
      return res.status(400).json({ 
        success: false, 
        message: 'Version is required' 
      });
    }
    
    // Verificar si la versión ya existe
    const [existing] = await pool.query(
      'SELECT id FROM app_versions WHERE version = ?',
      [version]
    );
    
    if (existing.length > 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Version already exists' 
      });
    }
    
    const [result] = await pool.query(`
      INSERT INTO app_versions 
        (version, download_url, release_notes, is_mandatory, min_version, created_by)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [version, download_url, release_notes, is_mandatory ? 1 : 0, min_version, created_by]);
    
    res.json({
      success: true,
      message: 'Version created successfully',
      id: result.insertId
    });
  } catch (err) {
    next(err);
  }
};

// PUT /api/updates/versions/:id - Actualizar versión
exports.updateVersion = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { 
      download_url, 
      release_notes, 
      is_mandatory,
      min_version,
      is_active 
    } = req.body;
    
    const [result] = await pool.query(`
      UPDATE app_versions SET
        download_url = COALESCE(?, download_url),
        release_notes = COALESCE(?, release_notes),
        is_mandatory = COALESCE(?, is_mandatory),
        min_version = COALESCE(?, min_version),
        is_active = COALESCE(?, is_active)
      WHERE id = ?
    `, [download_url, release_notes, is_mandatory, min_version, is_active, id]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'Version not found' 
      });
    }
    
    res.json({
      success: true,
      message: 'Version updated successfully'
    });
  } catch (err) {
    next(err);
  }
};

// DELETE /api/updates/versions/:id - Eliminar versión
exports.deleteVersion = async (req, res, next) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.query(
      'DELETE FROM app_versions WHERE id = ?',
      [id]
    );
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'Version not found' 
      });
    }
    
    res.json({
      success: true,
      message: 'Version deleted successfully'
    });
  } catch (err) {
    next(err);
  }
};

// GET /api/updates/download/:version - Descargar instalador
exports.downloadInstaller = async (req, res, next) => {
  try {
    const { version } = req.params;
    
    // Buscar la versión
    const [rows] = await pool.query(
      'SELECT download_url FROM app_versions WHERE version = ? AND is_active = TRUE',
      [version]
    );
    
    if (rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'Version not found' 
      });
    }
    
    const downloadUrl = rows[0].download_url;
    
    // Si es una URL externa, redirigir
    if (downloadUrl && (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://'))) {
      return res.redirect(downloadUrl);
    }
    
    // Si es un archivo local
    const installerPath = path.join(__dirname, '..', 'installers', `MaterialControl_${version}_Setup.exe`);
    
    if (!fs.existsSync(installerPath)) {
      return res.status(404).json({ 
        success: false, 
        message: 'Installer file not found' 
      });
    }
    
    res.download(installerPath, `MaterialControl_${version}_Setup.exe`);
  } catch (err) {
    next(err);
  }
};

// Función auxiliar para comparar versiones (ej: "1.0.8" vs "1.0.9")
function compareVersions(v1, v2) {
  const parts1 = v1.split('.').map(Number);
  const parts2 = v2.split('.').map(Number);
  
  const maxLength = Math.max(parts1.length, parts2.length);
  
  for (let i = 0; i < maxLength; i++) {
    const num1 = parts1[i] || 0;
    const num2 = parts2[i] || 0;
    
    if (num1 > num2) return 1;
    if (num1 < num2) return -1;
  }
  
  return 0;
}

module.exports = exports;
